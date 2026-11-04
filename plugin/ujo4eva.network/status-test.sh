#!/bin/bash
# The stock status command pings 1.1.1.1. A hotspot that drops only that
# address used to leave internet_ping_ms empty, which the panel counts as
# 100% packet loss. status.sh must keep a real sample and fill a blank one
# from the next resolver that answers.

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT=$ROOT/status.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"

cat >"$WORK/bin/omarchy-network-status" <<'EOF'
#!/bin/bash
printf '%s' "$MOCK_STATUS"
exit "${MOCK_STATUS_CODE:-0}"
EOF
cat >"$WORK/bin/ping" <<'EOF'
#!/bin/bash
printf 'ping %s\n' "$*" >>"$MOCK_PING_LOG"
host=${!#}
case $host in
  8.8.8.8) printf '%s' "$MOCK_GOOGLE" ;;
  9.9.9.9) printf '%s' "$MOCK_QUAD9" ;;
  *) printf 'unexpected ping host %s\n' "$host" >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/omarchy-network-status" "$WORK/bin/ping"

run_status() {
  PATH="$WORK/bin:$PATH" \
    MOCK_STATUS="$1" \
    MOCK_STATUS_CODE="${2:-0}" \
    MOCK_PING_LOG="$WORK/pings" \
    MOCK_GOOGLE="${3-}" \
    MOCK_QUAD9="${4-}" \
    bash "$SCRIPT"
}

: >"$WORK/pings"
# The script prints a trailing newline, and this capture strips it. Compare
# the lines themselves.
stock=$'iface\twlo1\nrouter_ping_ms\t1.68\ninternet_ping_ms\t20.5'
got=$(run_status "$stock")
if [[ $got != "$stock" ]]; then
  printf 'FAIL: a real internet sample was rewritten\n[%s]\n' "$got" >&2
  exit 1
fi
if [[ -s $WORK/pings ]]; then
  printf 'FAIL: fallback probes ran when 1.1.1.1 already answered\n' >&2
  exit 1
fi

: >"$WORK/pings"
blank=$'iface\twlo1\nrouter_ping_ms\t1.68\ninternet_ping_ms\t'
google=$'PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.\n64 bytes from 8.8.8.8: icmp_seq=1 ttl=116 time=83.1 ms\n'
got=$(run_status "$blank" 0 "$google" "")
want=$'iface\twlo1\nrouter_ping_ms\t1.68\ninternet_ping_ms\t83.1'
if [[ $got != "$want" ]]; then
  printf 'FAIL: empty internet sample was not filled from 8.8.8.8\n[%s]\n' "$got" >&2
  exit 1
fi

: >"$WORK/pings"
quad9=$'64 bytes from 9.9.9.9: icmp_seq=1 ttl=55 time=158 ms\n'
got=$(run_status "$blank" 0 "" "$quad9")
want=$'iface\twlo1\nrouter_ping_ms\t1.68\ninternet_ping_ms\t158'
if [[ $got != "$want" ]]; then
  printf 'FAIL: empty internet sample did not fall through to 9.9.9.9\n[%s]\n' "$got" >&2
  exit 1
fi

: >"$WORK/pings"
got=$(run_status "$blank" 0 "" "")
if [[ $got != "$blank" ]]; then
  printf 'FAIL: a total probe failure invented a latency\n%s\n' "$got" >&2
  exit 1
fi

: >"$WORK/pings"
disconnected=$'disconnected\t\t\t'
got=$(run_status "$disconnected")
if [[ $got != "$disconnected" || -s $WORK/pings ]]; then
  printf 'FAIL: a disconnected status grew a ping\n%s\n' "$got" >&2
  exit 1
fi

printf 'PASS: internet ping keeps a stock sample and fills a blank one from the next resolver\n'
