#!/bin/sh
# Baked into every image and install at <install_root>/webui/bin/firstboot.sh
# (or run from <install_root>/profiles/assets) and launched by cron's @reboot
# entry. It makes the boot-time decision of ADR-002
# (IMAGE-BASED-INSTALLATION.md), then leaves the supervisor and the WebUI
# running under init and exits, so cron's job ends with it. It runs once per
# boot: /var/run/freedomnas-firstboot, which every boot clears, stops a second
# run (restarting FreeBSD's cron runs @reboot entries again).
#
# In order:
#   1. grow-root-pool: an image flashed onto a larger disk takes the rest of it.
#   2. Every importable pool is imported without mounting (-N -f, no cachefile),
#      and encrypted ones are unlocked (USB key, else a passphrase on the
#      console, never blocking for ever).
#   3. `freedomnas state-boot` mounts the root pool's own `.freedomnas` (this
#      install's truth) and compares it with the `.freedomnas` copies on the
#      other pools, newest first by system.saved_at:
#        local         -> the internal configuration is initialized and used as
#                         it is;
#        merged        -> as local, plus the shared sections (shares, snapshot
#                         policies, modules, pools, new users never as admins)
#                         of the newest copy, whatever its age;
#        reinitialized -> the internal one does not match the running system
#                         (another edition, another identity): set up again
#                         from the newest copy, accounts kept;
#        restored      -> nothing initialized here (a reinstall): the newest
#                         copy, or the one the installer chose, is restored;
#        none          -> nothing anywhere: the WebUI's first-run guard
#                         redirects to /setup/.
#      The network comes from the newest copy that knows a card of this
#      machine. state-boot also names the pools to keep imported; every other
#      pool imported in step 2 is exported again.
#   4. ensure-tls: the CA and the server certificate for this host's names and
#      addresses, before the reconcile so apps get the current one.
#   5. A restore (restored, reinitialized, or a restore lock an interrupted one
#      left) writes the lock and starts the supervisor first: the WebUI shows
#      only the restore page with the reconcile's steps until the lock is gone.
#   6. Except for none, `freedomnas reconcile --mode declarative` makes the
#      system match config.yaml.
#   7. ensure-tls --names-only (a restore may change the hostname), then
#      boot-ok ends a new kernel's or boot environment's trial.
#   8. The supervisor starts in the background, unless step 5 started it.
#
# Must never block boot indefinitely and must never abort the chain even if a
# step fails: the WebUI must still come up so the admin can intervene.
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

ran_this_boot=/var/run/freedomnas-firstboot
if [ -e "$ran_this_boot" ]; then
    log "already ran since this boot -- nothing to do"
    exit 0
fi
: > "$ran_this_boot"

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

# A restore (a reinstall, another edition, an install set up again from its
# pool, or one a power cut interrupted) runs with the restore lock in place:
# the WebUI starts first and serves only the page that follows the steps
# the reconcile writes into the lock, until it is gone.
lock=$(python3 -m freedomnas path restoring 2>/dev/null)
restoring=no
case "$action" in restored|reinitialized) restoring=yes ;; esac
[ -n "$lock" ] && [ -e "$lock" ] && restoring=yes
progress=""
if [ "$restoring" = yes ]; then
    python3 -m freedomnas restore-begin --reason "$action" || log "WARNING: could not write the restore lock"
    "$INSTALL_ROOT/webui/bin/supervisor.sh" </dev/null &
    progress="--progress"
    log "restore in progress: the WebUI shows its steps"
fi

case "$action" in
    local|merged|restored|reinitialized)
        [ -n "$source_pool" ] && log "configuration $action from $source_pool"
        printf '%s\n' "$state" | awk '$1 == "reason" { $1 = ""; print "reason:" $0 }' | while read -r line; do log "$line"; done
        log "reconciling the configuration (declarative)"
        python3 -m freedomnas reconcile --mode declarative $progress || \
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

if [ "$restoring" != yes ]; then
    "$INSTALL_ROOT/webui/bin/supervisor.sh" </dev/null &
fi
exit 0
