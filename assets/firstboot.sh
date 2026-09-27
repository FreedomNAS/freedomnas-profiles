#!/bin/sh
# Baked into every image at <install_root>/webui/bin/firstboot.sh and
# launched from cron's @reboot entry (replacing the old direct call to
# supervisor.sh — this script now does the ADR-002 boot-time decision
# and then hands off to supervisor.sh itself).
#
# ADR-002 (IMAGE-BASED-INSTALLATION.md): on every boot, decide between
# disaster-recovery reconciliation and the normal first-run wizard by
# checking whether a `.freedomnas` dataset already exists on any
# importable pool:
#
#   - present -> mount it, run `freedomnas reconcile --mode
#                disaster_recovery` (restores hostname/users/shares/etc
#                from the shadow-copy config.yaml already on disk)
#   - absent  -> do nothing extra; the WebUI's existing first-run guard
#                (config.is_initialized() == False) redirects to /setup/
#                exactly as it does today
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

# Where this edition keeps the configuration comes from its OS profile.
STATE_DIR=$(python3 -m freedomnas path state)

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
zpool import -a -N -o cachefile=none 2>/dev/null || true

# Encrypted-pool unlock (zero-touch USB key, TTY passphrase fallback).
# Delegates entirely to the Python engine/profile layer -- this script never
# touches `zfs load-key` or USB devices directly. The TTY prompt retries for
# up to 5 minutes and then fails open (see keymgmt.py) so boot never blocks
# indefinitely, matching the invariant documented above.
python3 -m freedomnas unlock-pools --tty /dev/console || \
    log "WARNING: one or more encrypted pools remain locked"

# The pool this system booted from comes first. A NAS can have several pools
# carrying a .freedomnas dataset -- an older install, another machine's disk --
# and restoring a foreign configuration would create that machine's users and
# start that machine's services here.
root_dataset=$(zfs list -H -o name / 2>/dev/null)
root_pool="${root_dataset%%/*}"
search_order=$(printf '%s\n%s\n' "$root_pool" "$(zpool list -H -o name 2>/dev/null)" \
               | awk 'NF && !seen[$0]++')

found_dataset=""
found_pool=""
for pool in $search_order; do
    if zfs list -H -o name "$pool/.freedomnas" >/dev/null 2>&1; then
        found_dataset="$pool/.freedomnas"
        found_pool="$pool"
        [ -n "$root_pool" ] && [ "$pool" != "$root_pool" ] && \
            log "NOTE: the configuration comes from $pool, not from the root pool $root_pool"
        # A pool made by another edition carries that edition's mountpoint
        # (Linux mounts the dataset at /etc/freedomnas/state, FreeBSD under
        # /usr/local/etc): bring it to this one's before mounting it.
        [ "$(zfs get -H -o value mountpoint "$found_dataset" 2>/dev/null)" = "$STATE_DIR" ] || \
            zfs set mountpoint="$STATE_DIR" "$found_dataset" 2>/dev/null || true
        zfs mount "$found_dataset" 2>/dev/null || true
        break
    fi
done

# Give back everything we imported and did not need. A NAS must not adopt the
# pools of whatever disk happens to be attached -- least of all another
# operating system's root pool.
for pool in $(zpool list -H -o name 2>/dev/null); do
    was_already_imported "$pool" && continue
    [ "$pool" = "$found_pool" ] && continue
    log "releasing $pool -- imported while looking for the FreedomNAS dataset"
    zpool export "$pool" 2>/dev/null || true
done

if [ -n "$found_dataset" ] && [ -f "$STATE_DIR/config.yaml" ]; then
    log "found existing config on $found_dataset -- reconciling (disaster_recovery)"
    python3 -m freedomnas reconcile --mode disaster_recovery || \
        log "WARNING: reconcile failed, continuing to boot the WebUI anyway"
else
    log "no existing FreedomNAS config found -- first-run wizard will handle setup"
fi

# The WebUI's certificate: created once, then left alone. A certificate that
# changed at every boot would train the admin to click through the warning.
python3 -m freedomnas ensure-tls || log "WARNING: no TLS certificate — the WebUI will serve plain HTTP"

exec "$INSTALL_ROOT/webui/bin/supervisor.sh"
