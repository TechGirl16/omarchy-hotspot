#!/bin/bash

# User-owned companion for the cloned network panel. omarchy-network-status
# probes the internet by pinging 1.1.1.1. Some mobile hotspots drop only that
# address, so every sample comes back empty and the panel fills to 100%
# packet loss while other sites still answer. Keep the stock sample when it
# exists. When it is blank, use the same one-shot ping against the next
# public resolver that replies. A miss from every probe stays blank, which
# the panel still counts as loss.

status=$(omarchy-network-status --verbose)
code=$?
if (( code != 0 )); then
  printf '%s\n' "$status"
  exit "$code"
fi

internet_line=$(grep -m1 $'^internet_ping_ms\t' <<<"$status" || true)
if [[ -z $internet_line ]]; then
  printf '%s\n' "$status"
  exit 0
fi

internet_value=${internet_line#internet_ping_ms$'\t'}
if [[ -n $internet_value ]]; then
  printf '%s\n' "$status"
  exit 0
fi

ping_latency_ms() {
  LC_ALL=C ping -n -c 1 -W 1 "$1" 2>/dev/null | awk -F'time[=<]' '/time[=<]/ { split($2, parts, " "); print parts[1]; exit }'
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
ping_latency_ms 8.8.8.8 >"$tmpdir/google" &
ping_latency_ms 9.9.9.9 >"$tmpdir/quad9" &
wait

latency=$(<"$tmpdir/google")
if [[ -z $latency ]]; then
  latency=$(<"$tmpdir/quad9")
fi

if [[ -z $latency ]]; then
  printf '%s\n' "$status"
  exit 0
fi

awk -F '\t' -v latency="$latency" 'BEGIN { OFS = "\t" } $1 == "internet_ping_ms" { $2 = latency } { print }' <<<"$status"
