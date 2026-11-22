#!/usr/bin/env bash
# First half of the one-hour soak: the user taps Play, the script snapshots t0,
# turns the screen off and asks for the USB cable to be unplugged. Battery
# stats are not reset: the report takes the unplugged window after t0's local
# clock from the history.
# Usage: tool/device/soak_begin.sh <outdir>
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -eq 1 ] || die "usage: soak_begin.sh <outdir>"
out=$(outdir "$1")
require_device

level=$(a shell dumpsys battery | tr -d '\r' | awk '$1 == "level:" { print $2; exit }')
[[ $level =~ ^[0-9]+$ ]] || die "cannot read the battery level"
[ "$level" -ge 40 ] || die "battery at $level %, charge it to at least 40 %"
if keyguard_showing; then die "the keyguard is up; unlock the phone"; fi

a shell logcat -G 16M
a shell logcat -c
start_app
echo "TAP PLAY NOW"
wait_log 'FSTATE phase=playing' 120
sleep 20
"$DEVICE_DIR/snapshot.sh" "$out/t0"
a shell input keyevent KEYCODE_SLEEP
echo "UNPLUG USB NOW. Replug after at least 60 minutes."
