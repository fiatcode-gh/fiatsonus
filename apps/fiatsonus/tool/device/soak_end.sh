#!/usr/bin/env bash
# Second half of the soak: after the replug, snapshots t1 while playback still
# runs with the screen off and reports with the battery window. Leaves
# playback running so the user can listen.
# Usage: tool/device/soak_end.sh <outdir> [--min-window <seconds>]
#   --min-window: the shortest unplugged window that counts (default 3600).
set -euo pipefail
. "$(dirname "$0")/common.sh"

usage="usage: soak_end.sh <outdir> [--min-window <seconds>]"
min_window=3600
case $# in
  1) ;;
  3) [ "$2" = --min-window ] || die "$usage"; min_window=$3 ;;
  *) die "$usage" ;;
esac
out=$(outdir "$1")
a wait-for-device
"$DEVICE_DIR/snapshot.sh" "$out/t1" --battery-stats

status=0
dart "$DEVICE_DIR/report.dart" --t0 "$out/t0" --t1 "$out/t1" --expect-foreground --battery \
  --min-battery-window "$min_window" | tee "$out/report.txt" || status=$?
echo "LISTEN FOR 2 MINUTES, THEN STOP"
exit "$status"
