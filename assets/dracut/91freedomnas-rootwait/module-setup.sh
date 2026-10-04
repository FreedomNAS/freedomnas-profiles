#!/bin/bash
# 91freedomnas-rootwait — dracut waits for the root pool before importing it.
#
# dracut's zfs module waits only for /dev/zfs and for udev to settle, then
# imports once and gives up. A USB disk is announced later than that
# (usb-storage's delay_use), so a FreedomNAS booted from a USB stick found no
# pool and dropped to the emergency shell, with the disk appearing a moment
# after. This module adds an initqueue "finished" condition: dracut keeps
# looping until the root pool is importable, up to rd.retry (180 s).
#
# Installed into the target's modules.d by freedomnas-installer and enabled
# by the profiles' uki.conf (add_dracutmodules).

check() {
    return 0
}

depends() {
    echo zfs
    return 0
}

install() {
    # After the zfs module's parse-zfs.sh (cmdline 95).
    inst_hook cmdline 96 "$moddir/rootwait.sh"
    # With systemd in the initramfs (Debian), dracut-initqueue.service runs
    # only when /lib/dracut/need-initqueue exists — /lib is read-only by the
    # time the cmdline hook runs, so it is made here — and the pool is
    # imported by zfs-import-{cache,scan}.service, which must not try before
    # the wait is over.
    mkdir -p "$initdir/lib/dracut"
    : > "$initdir/lib/dracut/need-initqueue"
    if dracut_module_included "systemd"; then
        for unit in zfs-import-cache.service zfs-import-scan.service; do
            mkdir -p "$initdir$systemdsystemunitdir/$unit.d"
            printf '[Unit]\nAfter=dracut-initqueue.service\n' \
                > "$initdir$systemdsystemunitdir/$unit.d/freedomnas-rootwait.conf"
        done
    fi
}
