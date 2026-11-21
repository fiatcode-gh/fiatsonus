#!/usr/bin/env bash
# Stops playback from the notification's Stop action and checks the service
# and the notification are gone.
# Usage: tool/device/notification_stop.sh <outdir> [--assert-only]
#   --assert-only: the Stop was tapped by hand; only check the result.
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: notification_stop.sh <outdir> [--assert-only]"
assert_only=false
if [ $# -eq 2 ]; then
  [ "$2" = --assert-only ] || die "unknown argument $2"
  assert_only=true
fi
out=$(outdir "$1")
require_device

if $assert_only; then
  # The tap happened before this run: the marker is the last playing line.
  LOG_MATCH_EPOCH=$(flutter_log | grep -F 'FSTATE phase=playing' | tail -n 1 | awk '{ print $1 }' || true)
  [ -n "$LOG_MATCH_EPOCH" ] || die "no FSTATE phase=playing line in the log"
  log_after_match
  wait_log 'FSTATE phase=idle' 10
else
  service_foreground || die "the service is not in the foreground"
  mark_log
  wake_unlock
  trap 'a shell cmd statusbar collapse' EXIT
  a shell cmd statusbar expand-notifications
  sleep 2
  if ! "$DEVICE_DIR/ui_tap.sh" Stop com.android.systemui; then
    echo "tap Stop in the notification, then rerun with --assert-only" >&2
    exit 2
  fi
  wait_log 'FSTATE phase=idle' 10
fi
# Saved before the assertions so a failing run keeps its evidence.
sleep 5
services_dump >"$out/services.txt"
notification_excerpt >"$out/notification.txt"
assert_stopped_clean
say "PASS"
