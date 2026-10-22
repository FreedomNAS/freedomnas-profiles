#!/bin/sh
# Runs init/init-runit.json's commands, formatted by the engine into
# /opt/tests/commands.sh, against a test service fnastest.
set -u
. /opt/tests/commands.sh
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'PASS profile %s\n' "$1"; }
ko() { FAIL=$((FAIL + 1)); printf 'FAIL profile %s\n     %s\n' "$1" "${2:-}"; }
run() { sh -c "$1" 2>&1; }
yes_is() { out=$(run "$2"); [ "$out" = "$3" ] && ok "$1" || ko "$1" "wanted '$3', got '$out'"; }
succeeds() { out=$(run "$2") && ok "$1" || ko "$1" "$out"; }

src=
for d in /etc/sv /etc/runit/sv; do [ -d "$d" ] && { src=$d; break; }; done
mkdir -p "$src/fnastest"
printf '#!/bin/sh\nexec sleep 100000\n' > "$src/fnastest/run"
chmod 755 "$src/fnastest/run"
trap 'run "$cmd_disable" >/dev/null; rm -f /etc/runit/runsvdir/default/fnastest; rm -rf "$src/fnastest"' EXIT

case "$(run "$cmd_list_all")" in *fnastest*) ok list_all ;; *) ko list_all ;; esac
yes_is "is_enabled before" "$cmd_is_enabled" ""
succeeds enable "$cmd_enable"
yes_is "is_enabled after" "$cmd_is_enabled" yes
case "$(run "$cmd_list_managed")" in *fnastest*) ok list_managed ;; *) ko list_managed ;; esac
succeeds "start right after enable" "$cmd_start"
yes_is "is_running" "$cmd_is_running" yes
succeeds status "$cmd_status"
succeeds reload "$cmd_reload"
succeeds restart "$cmd_restart"
yes_is "is_running after restart" "$cmd_is_running" yes
succeeds stop "$cmd_stop"
yes_is "is_running after stop" "$cmd_is_running" ""
succeeds disable "$cmd_disable"
yes_is "is_enabled after disable" "$cmd_is_enabled" ""
succeeds enable_offline "$cmd_enable_offline"
[ "$(readlink /etc/runit/runsvdir/default/fnastest)" = "$src/fnastest" ] && ok "offline link to $src" || ko "offline link to $src"
succeeds disable_offline "$cmd_disable_offline"
out=$(cmd=$(printf '%s' "$cmd_enable_offline" | sed 's/fnastest/fnastestmissing/g'); run "$cmd") && ko "enable_offline of a missing service fails" "$out" || ok "enable_offline of a missing service fails"
printf '== profile: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
