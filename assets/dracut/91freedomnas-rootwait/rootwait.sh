#!/bin/sh
# cmdline hook: hold dracut's main loop until the pool named by root= can be
# imported (see module-setup.sh). root=ZFS=<pool>/<dataset> or zfs:...;
# zfs:AUTO and non-ZFS roots are left to the zfs module.

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

fnas_root=$(getarg root=)
case "$fnas_root" in
    ZFS=*|zfs:*)
        fnas_pool=${fnas_root#ZFS=}
        fnas_pool=${fnas_pool#zfs:}
        fnas_pool=${fnas_pool%%/*}
        ;;
    *)
        fnas_pool=
        ;;
esac

if [ -n "$fnas_pool" ] && [ "$fnas_pool" != AUTO ]; then
    info "FreedomNAS: waiting for pool $fnas_pool"
    cat > "$hookdir/initqueue/finished/freedomnas-rootpool.sh" <<EOF
[ -e /dev/zfs ] || modprobe zfs 2>/dev/null
zpool list -H -o name "$fnas_pool" >/dev/null 2>&1 && exit 0
zpool import 2>/dev/null | grep -qx "[[:space:]]*pool: $fnas_pool"
EOF
fi
unset fnas_root fnas_pool
