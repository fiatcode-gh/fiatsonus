#!/usr/bin/env bash
# Watches a phone call interrupt playback and playback resume after it, with
# the service in the foreground throughout.
# Usage: tool/device/call_watch.sh <outdir>
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -eq 1 ] || die "usage: call_watch.sh <outdir>"
out=$(outdir "$1")
require_device

service_foreground || die "the service is not in the foreground"
mark_log
echo "PLACE THE CALL NOW"
wait_log 'FSTATE phase=interrupted' 180
service_foreground || die "the service left the foreground during the call"
a shell dumpsys audio | tr -d '\r' >"$out/dumpsys_audio.txt"
awk '/Audio Focus stack entries/ { show = 1 } show { print; n++ } show && (/Notify on duck/ || n >= 60) { exit }' \
  "$out/dumpsys_audio.txt" >"$out/audio_focus.txt"
rm "$out/dumpsys_audio.txt"
[ -s "$out/audio_focus.txt" ] || die "no audio focus section in dumpsys audio"
log_after_match
wait_log 'FSTATE phase=playing' 180
"$DEVICE_DIR/snapshot.sh" "$out/snapshot"
echo "PASS"
