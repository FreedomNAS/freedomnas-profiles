#!/bin/bash
# 92freedomnas-fallback — automatic rollback after a kernel update that does
# not boot.
#
# After zz-dracut-uki makes a new kernel the active UKI, boot.state on the
# ESP says "trial". From this initramfs:
#   - the emergency shell of a trial boot, or a fourth trial boot without
#     userspace calling zz-dracut-uki --boot-ok, puts the rollback UKI back
#     in place of the active one (and of BOOTX64.efi) and reboots;
#   - the restored UKI then clones the root dataset back from the snapshot
#     the rollback UKI is paired with, keeping the failed one beside it.
# One automatic rollback per update; freedomnas.autorollback=0 on the
# command line, or "autorollback: no" in boot.state, turns it off.
#
# With systemd in the initramfs (Debian) the check is freedomnas-fallback.service,
# ordered after the initqueue and before the pool import: dracut's pre-mount
# service is ordered after OpenZFS's zfs-env-bootfs, and binding the import
# to it made a cycle systemd broke by dropping the hook.
#
# Installed into the target's modules.d by freedomnas-installer and enabled
# by the profiles' uki.conf (add_dracutmodules).

check() {
    return 0
}

depends() {
    return 0
}

installkernel() {
    hostonly='' instmods vfat nls_cp437 nls_iso8859-1 nls_utf8
}

install() {
    inst_multiple mount umount cp cat mkdir sed grep sync date sleep
    inst_multiple -o blkid cmp
    [ -r /etc/freedomnas/uki.conf ] && inst_simple /etc/freedomnas/uki.conf
    inst_simple "$moddir/fallback-lib.sh" /lib/freedomnas-fallback-lib.sh
    inst_hook emergency 10 "$moddir/fallback-emergency.sh"
    if dracut_module_included "systemd"; then
        inst_simple "$moddir/fallback-pre-mount.sh" /lib/freedomnas-fallback-pre-mount.sh
        inst_simple "$moddir/freedomnas-fallback.service" "$systemdsystemunitdir/freedomnas-fallback.service"
        mkdir -p "$initdir$systemdsystemconfdir/initrd.target.wants"
        ln -sf "$systemdsystemunitdir/freedomnas-fallback.service" \
            "$initdir$systemdsystemconfdir/initrd.target.wants/freedomnas-fallback.service"
    else
        inst_hook pre-mount 10 "$moddir/fallback-pre-mount.sh"
    fi
}
