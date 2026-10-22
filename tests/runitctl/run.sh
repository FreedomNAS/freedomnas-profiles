#!/bin/sh
# Usage: run.sh [void|artix|debian|devuan ...]
# Builds a container per distribution with its own runit packages, starts the
# distribution's /etc/runit/2 under docker --init (so runsvdir's parent is
# PID 1, as on a real boot) and runs cases.sh and profile.sh inside it.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
PROFILES=$(cd "$HERE/../.." && pwd)
CORE=${FREEDOMNAS_CORE:-$PROFILES/../freedomnas-core}
DISTROS=${*:-void artix debian devuan}
STATUS=0

image() {
  case "$1" in
    void) from=ghcr.io/void-linux/void-glibc:latest
          setup='xbps-install -Syu xbps && xbps-install -Syu && xbps-install -y runit-void procps-ng coreutils shadow' ;;
    artix) from=artixlinux/artixlinux:latest
           setup='pacman -Qq | grep dinit | xargs -r pacman -Rdd --noconfirm && pacman -Syu --noconfirm --needed runit runit-rc procps-ng coreutils' ;;
    debian) from=debian:trixie
            setup='apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends runit procps' ;;
    devuan) from=devuan/devuan:daedalus
            setup='apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends runit procps' ;;
    *) echo "unknown distribution: $1" >&2; exit 2 ;;
  esac
  printf 'FROM %s\nRUN %s\n' "$from" "$setup" | docker build -q -t "freedomnas-runitctl-$1" - >/dev/null || { printf 'FROM %s\nRUN %s\n' "$from" "$setup" | docker build --progress=plain -t "freedomnas-runitctl-$1" - 2>&1 | tail -20; return 1; }
}

expected() {
  case "$1" in
    void) echo /run/runit/runsvdir/current ;;
    artix) echo /run/runit/service ;;
    debian|devuan) echo /etc/service ;;
  esac
}

for d in $DISTROS; do
  printf '\n######## %s\n' "$d"
  image "$d" || { echo "FAIL could not build the $d image"; STATUS=1; continue; }
  name=freedomnas-runitctl-test-$d
  docker rm -f "$name" >/dev/null 2>&1 || true
  python3 -I "$HERE/commands.py" "$CORE" "$PROFILES" "$([ "$d" = artix ] && echo artix || echo void)" > "$HERE/commands.sh"
  docker run -d --init --name "$name" \
    -v "$PROFILES/assets/runitctl:/opt/runitctl:ro" \
    -v "$PROFILES/assets/runitctl:/usr/lib/freedomnas/profiles/assets/runitctl:ro" \
    -v "$HERE:/opt/tests:ro" \
    "freedomnas-runitctl-$d" /etc/runit/2 >/dev/null
  sleep 3
  docker exec "$name" sh /opt/tests/cases.sh /opt/runitctl "$(expected "$d")" || STATUS=1
  docker exec "$name" sh /opt/tests/profile.sh || STATUS=1
  docker rm -f "$name" >/dev/null
done
exit $STATUS
