#!/usr/bin/env bash
# Watches that the notification of a foreground service keeps its foreground
# flag (PLAN 4.6): while <command> runs, samples the AudioService record and
# the app's notification back to back into <outdir>/samples.txt, one line
#   <HH:MM:SS.mmm> isForeground=<true|false|none> fgs_flag=<yes|no|absent>
# then judges the samples. Without a command, judges an existing samples.txt.
#
# A bad stretch is a run of consecutive samples with isForeground=true and
# fgs_flag other than yes. A miss is a sample of a bad stretch more than
# 1000 ms after the stretch's first sample: Android posts a fresh foreground
# notification a few hundred ms after the service starts, and a stop's
# boundary is one or two samples, while a lost notification stays missing.
# Misses go to <outdir>/misses.txt. The command's output goes to
# <outdir>/command.txt.
# Usage: tool/device/foreground_watch.sh <outdir> [<command> [args...]]
# Exits 0 on PASS, 1 on FAIL.
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -ge 1 ] || die "usage: foreground_watch.sh <outdir> [<command> [args...]]"
out=$(outdir "$1")
shift
samples=$out/samples.txt

# The notification's own flags= line (not originalFlags=): yes when it holds
# FOREGROUND_SERVICE, absent without a notification of $PKG.
fgs_flag() {
  local excerpt
  excerpt=$(notification_excerpt)
  if [ -z "$excerpt" ]; then
    echo absent
  elif grep -qE '^[[:space:]]*flags=[^[:space:]]*FOREGROUND_SERVICE' <<<"$excerpt"; then
    echo yes
  else
    echo no
  fi
}

sample_loop() {
  set +e +o pipefail
  local stop=$1 fg flag
  while [ ! -e "$stop" ]; do
    fg=$(service_foreground_value)
    flag=$(fgs_flag)
    echo "$(date +%H:%M:%S.%3N) ${fg:-isForeground=none} fgs_flag=${flag:-absent}" >>"$samples"
  done
}

status=
if [ $# -gt 0 ]; then
  require_device
  : >"$samples"
  stop=$(mktemp -u)
  sample_loop "$stop" &
  sampler=$!
  set +e
  "$@" 2>&1 | tee "$out/command.txt"
  status=${PIPESTATUS[0]}
  set -e
  touch "$stop"
  wait "$sampler" || true
  rm -f "$stop"
fi
[ -f "$samples" ] || die "no $samples to judge"

read -r total foreground flagged misses < <(awk -v misses="$out/misses.txt" '
  function ms(t, p) { split(t, p, /[:.]/); return ((p[1] * 60 + p[2]) * 60 + p[3]) * 1000 + p[4] }
  BEGIN { printf "" >misses }
  {
    bad = ($2 == "isForeground=true" && $3 != "fgs_flag=yes")
    if (bad && !prev_bad) stretch_start = ms($1)
    since = ms($1) - stretch_start
    if (since < 0) since += 86400000
  }
  $2 == "isForeground=true" { foreground++ }
  $2 == "isForeground=true" && $3 == "fgs_flag=yes" { flagged++ }
  bad && since > 1000 { missed++; print >misses }
  { prev_bad = bad }
  END { printf "%d %d %d %d\n", NR, foreground, flagged, missed }' "$samples")

echo "RESULT samples=$total foreground=$foreground flagged=$flagged misses=$misses"
reasons=
add_reason() { reasons+="${reasons:+; }$1"; }
if [ -n "$status" ] && [ "$status" -ne 0 ]; then add_reason "command exited $status"; fi
if [ "$misses" -gt 0 ]; then add_reason "$misses foreground samples without the notification's foreground flag"; fi
if [ "$flagged" -lt 20 ]; then add_reason "only $flagged flagged samples"; fi
if [ -z "$reasons" ]; then
  echo PASS
else
  echo "FAIL $reasons"
  exit 1
fi
