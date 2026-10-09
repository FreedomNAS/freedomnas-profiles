#!/bin/sh
# pre-mount hook: count trial boots, and finish a rollback the failed UKI
# started (see module-setup.sh).

. /lib/freedomnas-fallback-lib.sh

if fnas_load_conf && fnas_mount_esp; then
    running=$(uname -r)
    case "$(fnas_get state)" in
        trial)
            if [ "$(fnas_get trial-kernel)" = "$running" ] && fnas_enabled; then
                tries=$(fnas_get tries-left)
                case "$tries" in ''|*[!0-9]*) tries=3 ;; esac
                if [ "$tries" -le 0 ]; then
                    fnas_fall_back "it did not finish booting three times"
                else
                    fnas_set tries-left "$((tries - 1))"
                fi
            fi
            ;;
        fallback-requested)
            if [ "$(fnas_get failed-kernel)" = "$running" ]; then
                fnas_log "the failed kernel $running started again after the rollback: leaving it to the administrator"
            else
                fnas_finish_rollback
            fi
            ;;
    esac
    fnas_umount_esp
fi
