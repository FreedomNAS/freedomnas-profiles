#!/bin/sh
# Usage: cases.sh RUNITCTL [EXPECTED_LIVE_DIR]
# Runs as root on a system where runit is PID 1's service supervisor (a real
# boot or a container running the distribution's own /etc/runit/2).
# It only creates and removes services named fnastest*, and puts back
# anything it touched.
set -u

RC=$1
EXPECT=${2:-}
PASS=0
FAIL=0
WAIT=${RUNITCTL_WAIT:-15}

ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
ko() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; }
check() { name=$1; shift; out=$("$@" 2>&1) && ok "$name" || ko "$name" "$out"; }
check_fails() { name=$1; shift; out=$("$@" 2>&1) && ko "$name" "unexpected success: $out" || ok "$name"; }
check_out() { name=$1; want=$2; shift 2; out=$("$@" 2>&1); case "$out" in *"$want"*) ok "$name" ;; *) ko "$name" "wanted '$want', got: $out" ;; esac; }

printf '== system\n'
grep -E '^(PRETTY_NAME|ID)=' /etc/os-release 2>/dev/null
ps -eo pid,ppid,args 2>/dev/null | awk '$3 ~ /runsvdir/ {print "runsvdir:", $0}' | cut -c1-120
printf '== runitctl %s\n' "$(sh "$RC" --version)"

live=$(sh "$RC" detect 2>&1 | sed -n 's/^service directory: //p')
[ -n "$live" ] && ok "detect live: $live" || ko "detect live" "$(sh "$RC" detect 2>&1)"
[ -z "$EXPECT" ] || { [ "$live" = "$EXPECT" ] && ok "live dir is $EXPECT" || ko "live dir is $EXPECT" "got $live"; }
persist=$(readlink -f "$live")
offline=$(sh "$RC" --root / detect 2>&1 | sed -n 's/^service directory: //p')
[ "$(readlink -f "/$offline")" = "$persist" ] && ok "offline detect on / reaches $persist ($offline)" \
  || ko "offline detect on / reaches $persist" "got '$offline'"
case "$persist" in /run/*|/var/run/*) ko "persistent dir is not under /run" "$persist" ;; *) ok "persistent dir $persist" ;; esac

srcroot=
for d in /etc/sv /etc/runit/sv; do [ -d "$d" ] && { srcroot=$d; break; }; done
[ -n "$srcroot" ] && ok "service sources in $srcroot" || { ko "service sources" "no /etc/sv nor /etc/runit/sv"; exit 1; }

for n in fnastest fnastest2 fnastestalias fnastestrel; do
  [ -e "$persist/$n" ] || [ -L "$persist/$n" ] && { ko "clean start" "$persist/$n exists already"; exit 1; }
done
cleanup() {
  for n in fnastest fnastest2 fnastestalias fnastestrel fnastestbad fnastestother; do
    rm -f "$persist/$n"
    rm -rf "$srcroot/$n"
  done
}
trap cleanup EXIT INT TERM

for n in fnastest fnastest2 fnastestother fnastestbad; do
  mkdir -p "$srcroot/$n"
  printf '#!/bin/sh\nexec sleep 100000\n' > "$srcroot/$n/run"
  chmod 755 "$srcroot/$n/run"
done
printf '#!/bin/sh\nexit 1\n' > "$srcroot/fnastestbad/run"

check_out "list-available has fnastest" fnastest sh "$RC" list-available
check_fails "is-enabled before enable" sh "$RC" is-enabled fnastest
check_out "enable" "enabled: fnastest" sh "$RC" enable fnastest
[ -L "$persist/fnastest" ] && ok "link written in $persist" || ko "link written in $persist"
check "is-enabled after enable" sh "$RC" is-enabled fnastest
check_out "enable again" "already enabled: fnastest" sh "$RC" enable fnastest
check_out "list-enabled has fnastest" fnastest sh "$RC" list-enabled
check "start right after enable" sh "$RC" start fnastest
check "is-running after start" sh "$RC" is-running fnastest
check_out "status" "run:" sh "$RC" status fnastest
check "stop" sh "$RC" stop fnastest
check_fails "is-running after stop" sh "$RC" is-running fnastest
check "start" sh "$RC" start fnastest
pid1=$(sv status "$live/fnastest" | sed -n 's/^run: [^ ]* (pid \([0-9]*\)).*/\1/p')
check "restart" sh "$RC" restart fnastest
pid2=$(sv status "$live/fnastest" | sed -n 's/^run: [^ ]* (pid \([0-9]*\)).*/\1/p')
[ -n "$pid2" ] && [ "$pid1" != "$pid2" ] && ok "restart gave a new pid ($pid1 -> $pid2)" || ko "restart gave a new pid" "$pid1 -> $pid2"
check "is-running after restart" sh "$RC" is-running fnastest

check "enable failing service" sh "$RC" enable fnastestbad
check_fails "start of a service that cannot run fails" env RUNITCTL_WAIT=8 sh "$RC" start fnastestbad
check "disable failing service" sh "$RC" disable fnastestbad

check_out "disable" "disabled: fnastest" sh "$RC" disable fnastest
check_fails "is-enabled after disable" sh "$RC" is-enabled fnastest
check_out "disable again" "already disabled" sh "$RC" disable fnastest
i=0
while [ -n "$(sv status "$srcroot/fnastest" 2>/dev/null | grep '^run:')" ] && [ $i -lt 12 ]; do sleep 1; i=$((i + 1)); done
sv status "$srcroot/fnastest" 2>/dev/null | grep -q '^run:' && ko "service stops after disable" || ok "service stops after disable (${i}s)"
check_fails "start of a disabled service fails" sh "$RC" start fnastest

ln -s /nonexistent/fnastest "$persist/fnastest"
check_out "stale link replaced" "replaced stale link" sh "$RC" enable fnastest
sh "$RC" disable fnastest >/dev/null 2>&1

ln -s "$srcroot/fnastestother" "$persist/fnastest"
check_fails "foreign valid link refused" sh "$RC" enable fnastest
[ "$(readlink "$persist/fnastest")" = "$srcroot/fnastestother" ] && ok "foreign link left alone" || ko "foreign link left alone"
rm -f "$persist/fnastest"

ln -s "$srcroot/fnastest2" "$persist/fnastestalias"
check_out "same service under another name" "already enabled as fnastestalias" sh "$RC" enable fnastest2
rm -f "$persist/fnastestalias"
sleep 6

rel=$(realpath --relative-to="$persist" "$srcroot/fnastest2" 2>/dev/null || python3 -c "import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))" "$srcroot/fnastest2" "$persist")
ln -s "$rel" "$persist/fnastest2"
check_out "relative link ($rel) seen as enabled" "already enabled: fnastest2" sh "$RC" enable fnastest2
check "start through a relative link" sh "$RC" start fnastest2
check "disable relative link" sh "$RC" disable fnastest2

check_out "offline enable with --root /" "enabled: fnastest" sh "$RC" --root / enable fnastest
[ -L "$persist/fnastest" ] && ok "offline link in $persist" || ko "offline link in $persist"
check_fails "--root refuses start" sh "$RC" --root / start fnastest
check "offline disable with --root /" sh "$RC" --root / disable fnastest

check_fails "invalid name refused" sh "$RC" enable ../fnastest
check_fails "unknown service refused" sh "$RC" enable fnastestmissing
as_nobody() {
  if command -v setpriv >/dev/null 2>&1; then
    setpriv --reuid=65534 --regid=65534 --clear-groups sh -c "$1"
  else
    su -s /bin/sh nobody -c "$1"
  fi
}
if as_nobody true >/dev/null 2>&1; then
  check_fails "enable as non-root refused" as_nobody "sh $RC enable fnastest"
  check "list-enabled works as non-root" as_nobody "sh $RC list-enabled >/dev/null"
  sh "$RC" enable fnastest >/dev/null 2>&1 && sh "$RC" start fnastest >/dev/null 2>&1
  check_out "status as non-root says root is needed" "needs root" as_nobody "sh $RC status fnastest"
  sh "$RC" disable fnastest >/dev/null 2>&1
fi

printf '== %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
