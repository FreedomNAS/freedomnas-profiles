#!/bin/sh
# Shared by the pre-mount and emergency hooks of 92freedomnas-fallback.

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

fnas_esp=/run/freedomnas-esp

fnas_log() {
    warn "FreedomNAS: $*"
}

fnas_load_conf() {
    UKI_NAME=""
    ROOT_DATASET=""
    [ -r /etc/freedomnas/uki.conf ] && . /etc/freedomnas/uki.conf
    [ -n "$UKI_NAME" ] && [ -n "$ROOT_DATASET" ] || return 1
    fnas_base="${UKI_NAME%.efi}"
    fnas_dir="$fnas_esp/EFI/Linux"
    fnas_current="$fnas_dir/$UKI_NAME"
    fnas_current_kernel="$fnas_dir/$fnas_base.kernel"
    fnas_previous="$fnas_dir/$fnas_base-previous.efi"
    fnas_previous_kernel="$fnas_dir/$fnas_base-previous.kernel"
    fnas_previous_snap="$fnas_dir/$fnas_base-previous.snapshot"
    fnas_failed="$fnas_dir/$fnas_base-failed.efi"
    fnas_failed_kernel="$fnas_dir/$fnas_base-failed.kernel"
    fnas_fallback="$fnas_esp/EFI/BOOT/BOOTX64.efi"
    fnas_state="$fnas_esp/EFI/FreedomNAS/boot.state"
}

fnas_mount_esp() {
    grep -q " $fnas_esp " /proc/mounts && return 0
    mkdir -p "$fnas_esp"
    for mod in vfat nls_cp437 nls_iso8859-1; do modprobe -q "$mod" 2>/dev/null; done
    for dev in $(blkid -t TYPE=vfat -o device 2>/dev/null); do
        mount -t vfat "$dev" "$fnas_esp" 2>/dev/null || continue
        [ -f "$fnas_current" ] && return 0
        umount "$fnas_esp"
    done
    return 1
}

fnas_umount_esp() {
    sync
    umount "$fnas_esp" 2>/dev/null
}

fnas_get() {
    sed -n "s/^$1: //p" "$fnas_state" 2>/dev/null | head -n 1
}

fnas_set() {
    mkdir -p "${fnas_state%/*}"
    if grep -q "^$1:" "$fnas_state" 2>/dev/null; then
        sed -i "s|^$1: .*|$1: $2|" "$fnas_state"
    else
        echo "$1: $2" >> "$fnas_state"
    fi
}

fnas_enabled() {
    getargbool 1 freedomnas.autorollback || return 1
    [ "$(fnas_get autorollback)" != no ]
}

fnas_kernel_of() {
    cat "$1" 2>/dev/null
}

fnas_fall_back() {
    running=$(uname -r)
    restored=$(fnas_kernel_of "$fnas_previous_kernel")
    if [ ! -f "$fnas_previous" ]; then
        fnas_log "no rollback UKI on the ESP: nothing to fall back to"
        return 1
    fi
    if [ "$restored" = "$running" ] || cmp -s "$fnas_previous" "$fnas_current"; then
        fnas_log "the rollback UKI is the one that just failed: not falling back"
        return 1
    fi
    fnas_log "kernel $running failed to boot ($1): restoring the UKI of kernel ${restored:-unknown}"
    cp -f "$fnas_current" "$fnas_failed" || return 1
    echo "$running" > "$fnas_failed_kernel"
    if ! cp -f "$fnas_previous" "$fnas_current"; then
        cp -f "$fnas_failed" "$fnas_current"
        fnas_log "could not copy the rollback UKI into place: nothing changed"
        return 1
    fi
    if [ -n "$restored" ]; then
        echo "$restored" > "$fnas_current_kernel"
    else
        rm -f "$fnas_current_kernel"
    fi
    mkdir -p "${fnas_fallback%/*}"
    cp -f "$fnas_previous" "$fnas_fallback"
    fnas_set state fallback-requested
    fnas_set failed-kernel "$running"
    fnas_set restored-kernel "${restored:-unknown}"
    fnas_set reason "$1"
    fnas_set date "$(date +%Y%m%d-%H%M%S)"
    fnas_set snapshot "$(cat "$fnas_previous_snap" 2>/dev/null)"
    fnas_umount_esp
    fnas_log "rebooting into the restored UKI"
    sleep 5
    echo b > /proc/sysrq-trigger
    return 0
}

fnas_finish_rollback() {
    snapshot=$(fnas_get snapshot)
    stamp=$(fnas_get date)
    pool="${ROOT_DATASET%%/*}"
    fs=no
    failed_ds=""
    case "$snapshot" in
        "$ROOT_DATASET@pre-update-"*) ;;
        *) snapshot="" ;;
    esac
    if [ -z "$snapshot" ]; then
        fnas_log "the rollback UKI has no paired snapshot: kernel restored, system files left as they are"
    else
        modprobe zfs 2>/dev/null
        imported_here=0
        if ! zpool list -H -o name "$pool" >/dev/null 2>&1; then
            zpool import -N "$pool" && imported_here=1
        fi
        if zfs list -H -o name "$snapshot" >/dev/null 2>&1; then
            failed_ds="$ROOT_DATASET-failed-$stamp"
            if zfs rename "$ROOT_DATASET" "$failed_ds"; then
                if zfs clone -o canmount=noauto -o mountpoint=/ "$failed_ds@${snapshot#*@}" "$ROOT_DATASET" \
                        && zfs promote "$ROOT_DATASET"; then
                    zpool set bootfs="$ROOT_DATASET" "$pool" 2>/dev/null
                    fs=yes
                    fnas_log "$ROOT_DATASET restored from ${snapshot#*@}; the failed system is kept as $failed_ds"
                else
                    zfs destroy "$ROOT_DATASET" 2>/dev/null
                    zfs rename "$failed_ds" "$ROOT_DATASET"
                    failed_ds=""
                    fs=failed
                    fnas_log "could not clone $snapshot: system files left as they are"
                fi
            else
                fs=failed
                fnas_log "could not rename $ROOT_DATASET: system files left as they are"
            fi
        else
            fs=failed
            fnas_log "snapshot $snapshot not found: system files left as they are"
        fi
        [ "$imported_here" = 1 ] && zpool export "$pool"
    fi
    fnas_set state rolled-back
    fnas_set fs-rollback "$fs"
    fnas_set failed-dataset "$failed_ds"
}
