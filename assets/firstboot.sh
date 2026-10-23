#!/bin/sh
# Baked into every image at <install_root>/webui/bin/firstboot.sh and
# launched from cron's @reboot entry (replacing the old direct call to
# supervisor.sh — this script now does the ADR-002 boot-time decision
# and then hands off to supervisor.sh itself).
#
# ADR-002 (IMAGE-BASED-INSTALLATION.md), with the internal/external split:
# on every boot `freedomnas state-boot` mounts the root pool's `.freedomnas`
# (this install's own configuration, created on the first boot) and looks
# at the `.freedomnas` of every other importable pool:
#
#   - local    -> the internal configuration is initialized: it is used;
#   - merged   -> a data pool holds a newer copy written by another install:
#                 only its shares, policies, modules, pools and users are
#                 taken over, never what belongs to this install;
#   - restored -> nothing initialized here (a reinstall): the newest copy
#                 on a data pool is restored;
#   - none     -> nothing anywhere: the WebUI's first-run guard redirects
#                 to /setup/.
#
# Except for none, `freedomnas reconcile --mode declarative` then makes the
# system match config.yaml (hostname, users, shares, ...).
#
# Must never block boot indefinitely and must never abort the chain even
# if reconciliation fails -- the WebUI should still come up so the admin
# can intervene manually.
set -u

# cron's @reboot environment has neither sbin directory on PATH, and every
# administrative tool the reconciler calls -- useradd, zpool, rc-service --
# lives in one of them.
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

# This script is <install_root>/profiles/assets/firstboot.sh, or a copy of it
# in <install_root>/webui/bin: either way the root is three levels up from
# the real file, whatever the edition decided the root is.
INSTALL_ROOT=$(dirname "$(dirname "$(dirname "$(realpath "$0")")")")

# freedomnas-core lives outside every interpreter's site-packages, whose name
# carries the Python version and so moves on an upgrade; naming it here keeps
# `python3 -m freedomnas` working whatever the distribution and version.
PYTHONPATH="$INSTALL_ROOT/core${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONPATH

log() { echo "firstboot: $*"; }

# An image flashed onto a larger disk: take the rest of it. Does nothing once
# the root pool's partition reaches the end of the disk.
python3 -m freedomnas grow-root-pool || log "WARNING: could not grow the root pool"

# Pools already imported when we got here: whatever the admin or the boot
# services set up is not ours to touch.
already_imported=$(zpool list -H -o name 2>/dev/null)

was_already_imported() {
    printf '%s\n' "$already_imported" | grep -qx "$1"
}

# cachefile=none matters more than it looks: without it, importing a pool
# writes it into /etc/zfs/zpool.cache, and from the next boot onward the
# system's own zfs-import/zfs-mount services adopt it and mount its datasets
# over the running system's -- a foreign pool's /var/log shadowing this one's.
#
# -f because the data pool of a reinstalled NAS was last used by the old
# system, under another hostid, and was never exported: the old disk died or
# was wiped. Without -f exactly the pool to restore from stays out. -N, the
# cachefile and the export below keep what -f lets in from staying.
zpool import -a -N -f -o cachefile=none 2>/dev/null || true

# Encrypted-pool unlock (zero-touch USB key, TTY passphrase fallback).
# Delegates entirely to the Python engine/profile layer -- this script never
# touches `zfs load-key` or USB devices directly. The TTY prompt retries for
# up to 5 minutes and then fails open (see keymgmt.py) so boot never blocks
# indefinitely, matching the invariant documented above.
python3 -m freedomnas unlock-pools --tty /dev/console || \
    log "WARNING: one or more encrypted pools remain locked"

state=$(python3 -m freedomnas state-boot) || \
    log "WARNING: could not put the configuration in place"
action=$(printf '%s\n' "$state" | awk '$1 == "action" { print $2 }')
source_pool=$(printf '%s\n' "$state" | awk '$1 == "source" { print $2 }')
keep=$(printf '%s\n' "$state" | awk '$1 == "keep" { print $2 }')
root_dataset=$(zfs list -H -o name / 2>/dev/null)
root_pool="${root_dataset%%/*}"

# Give back everything we imported and did not need. A NAS must not adopt the
# pools of whatever disk happens to be attached -- least of all another
# operating system's root pool.
for pool in $(zpool list -H -o name 2>/dev/null); do
    was_already_imported "$pool" && continue
    [ "$pool" = "$root_pool" ] && continue
    printf '%s\n' "$keep" | grep -qx "$pool" && continue
    log "releasing $pool -- imported while looking for the FreedomNAS dataset"
    zpool export "$pool" 2>/dev/null || true
done

# FreedomNAS's own CA, made once, and the server certificate it signs for this
# host's names and addresses, issued again when they change. Before the
# reconcile, so apps that serve HTTPS with it get the current one.
python3 -m freedomnas ensure-tls || log "WARNING: could not check the TLS certificate"

case "$action" in
    local|merged|restored)
        [ -n "$source_pool" ] && log "configuration $action from $source_pool"
        log "reconciling the configuration (declarative)"
        python3 -m freedomnas reconcile --mode declarative || \
            log "WARNING: reconcile failed, continuing to boot the WebUI anyway"
        ;;
    *)
        log "no existing FreedomNAS config found -- first-run wizard will handle setup"
        ;;
esac

# A restore can change the hostname: the certificate is checked again, for
# names only. Addresses the reconcile brought up (the jails' bridge) wait for
# the next boot, so the WebUI and the apps keep presenting the same one.
python3 -m freedomnas ensure-tls --names-only || log "WARNING: no TLS certificate — the WebUI will serve plain HTTP"

# The system came this far: a new kernel's trial is over, and the automatic
# rollback setting in config.yaml reaches the ESP.
python3 -m freedomnas boot-ok || log "WARNING: could not confirm the boot"

exec "$INSTALL_ROOT/webui/bin/supervisor.sh"
