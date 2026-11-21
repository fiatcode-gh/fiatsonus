#!/usr/bin/env bash
# Plays through the app's own Play button, turns the screen off for
# <minutes>, measures, then stops from the app and checks the service and the
# notification are gone. Exits with report.dart's status.
# Usage: tool/device/screen_off_run.sh <minutes> <outdir>
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -eq 2 ] || die "usage: screen_off_run.sh <minutes> <outdir>"
minutes=$1
[[ $minutes =~ ^[0-9]+$ ]] && [ "$minutes" -gt 0 ] || die "minutes must be a positive integer"
out=$(outdir "$2")
require_device

a shell logcat -G 16M
a shell logcat -c
wake_unlock
start_app
"$DEVICE_DIR/ui_tap.sh" Play
wait_log 'FSTATE phase=playing' 15
sleep 20
"$DEVICE_DIR/snapshot.sh" "$out/t0"
a shell input keyevent KEYCODE_SLEEP
say "screen off for $minutes min"
sleep $((minutes * 60))
"$DEVICE_DIR/snapshot.sh" "$out/t1"

status=0
dart "$DEVICE_DIR/report.dart" --t0 "$out/t0" --t1 "$out/t1" --expect-foreground |
  tee "$out/report.txt" || status=$?

wake_unlock
"$DEVICE_DIR/ui_tap.sh" Stop
wait_log 'FSTATE phase=idle' 10
# Saved before the assertions so a failing run keeps its evidence.
sleep 5
services_dump >"$out/services_after_stop.txt"
notification_excerpt >"$out/notification_after_stop.txt"
assert_stopped_clean
exit "$status"
