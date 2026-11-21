#!/usr/bin/env bash
# Second half of the soak: after the replug, snapshots t1 while playback still
# runs with the screen off and reports with the battery window. Leaves
# playback running so the user can listen.
# Usage: tool/device/soak_end.sh <outdir>
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -eq 1 ] || die "usage: soak_end.sh <outdir>"
out=$(outdir "$1")
a wait-for-device
"$DEVICE_DIR/snapshot.sh" "$out/t1" --battery-stats

status=0
dart "$DEVICE_DIR/report.dart" --t0 "$out/t0" --t1 "$out/t1" --expect-foreground --battery |
  tee "$out/report.txt" || status=$?
echo "LISTEN FOR 2 MINUTES, THEN STOP"
exit "$status"
