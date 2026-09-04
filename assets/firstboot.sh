#!/bin/sh
# Baked into every image at /usr/lib/freedomnas/webui/bin/firstboot.sh and
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

log() { echo "firstboot: $*"; }

zpool import -a -N 2>/dev/null || true

# Encrypted-pool unlock (zero-touch USB key, TTY passphrase fallback).
# Delegates entirely to the Python engine/profile layer -- this script never
# touches `zfs load-key` or USB devices directly. The TTY prompt retries for
# up to 5 minutes and then fails open (see keymgmt.py) so boot never blocks
# indefinitely, matching the invariant documented above.
python3 -m freedomnas unlock-pools --tty /dev/console || \
    log "WARNING: one or more encrypted pools remain locked"

found_dataset=""
for pool in $(zpool list -H -o name 2>/dev/null); do
    if zfs list -H -o name "$pool/.freedomnas" >/dev/null 2>&1; then
        found_dataset="$pool/.freedomnas"
        zfs mount "$found_dataset" 2>/dev/null || true
        break
    fi
done

if [ -n "$found_dataset" ] && [ -f /etc/freedomnas/state/config.yaml ]; then
    log "found existing config on $found_dataset -- reconciling (disaster_recovery)"
    python3 -m freedomnas reconcile --mode disaster_recovery || \
        log "WARNING: reconcile failed, continuing to boot the WebUI anyway"
else
    log "no existing FreedomNAS config found -- first-run wizard will handle setup"
fi

exec /usr/lib/freedomnas/webui/bin/supervisor.sh
