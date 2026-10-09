#!/bin/sh
# emergency hook: a trial boot that ends here falls back to the rollback UKI
# (see module-setup.sh).

. /lib/freedomnas-fallback-lib.sh

if fnas_load_conf && fnas_mount_esp; then
    case "$(fnas_get state)" in
        trial)
            if [ "$(fnas_get trial-kernel)" = "$(uname -r)" ] && fnas_enabled; then
                fnas_fall_back "the initramfs reached the emergency shell"
            fi
            ;;
        fallback-requested|rolled-back)
            fnas_log "an automatic rollback already ran for this update: not trying again"
            ;;
    esac
    fnas_umount_esp
fi
