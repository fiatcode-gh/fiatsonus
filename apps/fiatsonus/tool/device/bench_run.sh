#!/usr/bin/env bash
# Runs the installed bench target (install.sh --target=lib/bench_main.dart)
# until it logs FBENCH done and saves its lines (PLAN 5.5). With --profile,
# captures <seconds> of the bench isolate's CPU samples into <outdir>/profile
# once the bench began (needs a profile build).
# Exits 1 on an FBENCH error line, without FBENCH done within 900 s, in
# measure mode without 28 FDIGEST lines, or when the requested profile failed;
# the files are written first.
# Usage: tool/device/bench_run.sh <outdir> [--profile <seconds>]
set -euo pipefail
. "$(dirname "$0")/common.sh"

usage="usage: bench_run.sh <outdir> [--profile <seconds>]"
[ $# -eq 1 ] || [ $# -eq 3 ] || die "$usage"
profile=
if [ $# -eq 3 ]; then
  [ "$2" = --profile ] || die "$usage"
  profile=$3
  [[ $profile =~ ^[0-9]+$ ]] && [ "$profile" -gt 0 ] || die "profile seconds must be a positive integer"
fi
out=$(outdir "$1")
require_device

a shell logcat -G 16M
a shell logcat -c
a shell dumpsys battery | tr -d '\r' >"$out/battery_before.txt"
wake_unlock
start_app
pid=$(a shell pidof "$PKG" | tr -d '\r')
say "bench running in pid $pid"

bench_log() { a shell logcat -d --pid "$pid" -s flutter:I | tr -d '\r'; }

end=$((SECONDS + 900))
outcome=timeout
profile_status=
while :; do
  log=$(bench_log)
  if grep -q 'FBENCH error' <<<"$log"; then
    outcome=error
    break
  fi
  if grep -qE 'FBENCH done$' <<<"$log"; then
    outcome=done
    break
  fi
  if [ -n "$profile" ] && [ -z "$profile_status" ] && grep -q 'FBENCH begin' <<<"$log"; then
    profile_status=0
    "$DEVICE_DIR/cpu_profile.sh" "$out/profile" "$profile" bench || profile_status=$?
  fi
  [ "$SECONDS" -lt "$end" ] || break
  sleep 5
  a shell input keyevent KEYCODE_WAKEUP
done

log=$(bench_log)
printf '%s\n' "$log" >"$out/logcat.txt"
grep -o 'FDIGEST v=1 .*' <<<"$log" >"$out/digests.txt" || true
grep -o 'FBENCH .*' <<<"$log" >"$out/bench.txt" || true
a shell "for t in /proc/$pid/task/*; do echo \"tid=\${t##*/}\"; cat \$t/time_in_state 2>/dev/null; done; true" |
  tr -d '\r' >"$out/task_time_in_state.txt"
a shell dumpsys battery | tr -d '\r' >"$out/battery_after.txt"
begin=$(grep -o 'FBENCH begin .*' "$out/bench.txt" | head -n 1 || true)
mode=$(sed -nE 's/.* mode=([a-z]+).*/\1/p' <<<"$begin")
build=$(sed -nE 's/.* build=([a-z]+).*/\1/p' <<<"$begin")
apk_sha1="$APP_DIR/build/app/outputs/flutter-apk/app-${build:-release}.apk.sha1"
{
  echo "head=$(git -C "$APP_DIR" rev-parse --short HEAD)"
  echo "status_lines=$(git -C "$APP_DIR" status --short | wc -l)"
  echo "mode=$mode"
  echo "build=$build"
  echo "apk_sha1=$(cat "$apk_sha1" 2>/dev/null || echo unknown)"
} >"$out/build.txt"
digests=$(wc -l <"$out/digests.txt")
say "wrote $out: $digests digests, $(grep -c ' stage=' "$out/bench.txt" || true) stage lines"

case $outcome in
  error) die "$(grep -m 1 -o 'FBENCH error.*' "$out/bench.txt")" ;;
  timeout) die "no FBENCH done within 900s" ;;
esac
if [ "$mode" = measure ] && [ "$digests" -ne 28 ]; then
  die "measure mode logged $digests FDIGEST lines, not 28"
fi
if [ -n "$profile" ] && [ "${profile_status:-1}" != 0 ]; then
  die "the CPU profile failed (status ${profile_status:-not started})"
fi
say "bench $mode ($build) done"
