#!/usr/bin/env bash
# Plays, turns the screen off, causes real transient audio-focus losses with a
# shell notification (SystemUI's NotificationPlayer requests
# AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK; the app pauses on duck) and checks the
# service stays in the foreground without a restart, playback resumes with
# the screen off, a report over the resumed playback passes, and stop
# afterwards ends cleanly.
#
# Needs notification sound: ringer on (mode_ringer 2) and Do Not Disturb off
# (zen_mode 0). The script changes neither. It leaves one shell notification
# (tag fiatsonus_transient) behind for the user to swipe away.
# Usage: tool/device/transient_check.sh <outdir> [losses]   (default 3 losses)
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: transient_check.sh <outdir> [losses]"
losses=${2:-3}
[[ $losses =~ ^[0-9]+$ ]] && [ "$losses" -gt 0 ] || die "losses must be a positive integer"
out=$(outdir "$1")
require_device

zen=$(a shell settings get global zen_mode | tr -d '\r')
ringer=$(a shell settings get global mode_ringer | tr -d '\r')
if [ "$zen" != 0 ] || [ "$ringer" != 2 ]; then
  echo "transient_check.sh: notification sound is off; a posted notification cannot take audio focus (zen_mode=$zen mode_ringer=$ringer)" >&2
  exit 2
fi

# The isForeground= value of the AudioService record ("none" without one).
service_foreground_value() {
  services_dump | awk '
    /^[[:space:]]*\* ServiceRecord\{/ { in_svc = ($0 ~ /AudioService[[:space:]}]/); next }
    /^ {0,2}[^ ]/ { in_svc = 0 }
    in_svc && match($0, /(^|[[:space:]])isForeground=[a-z]+/) {
      value = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", value)
    }
    END { print (value == "" ? "isForeground=none" : value) }'
}

session_state() {
  a shell dumpsys media_session | tr -d '\r' |
    awk '/state=PlaybackState \{state=/ && !seen {
      sub(/.*state=PlaybackState \{state=/, ""); sub(/,.*/, ""); print; seen = 1 }'
}

wakefulness() {
  a shell dumpsys power | tr -d '\r' | awk '/mWakefulness=/ && !seen { print $1; seen = 1 }'
}

a shell logcat -G 16M
a shell logcat -c
wake_unlock
start_app
"$DEVICE_DIR/ui_tap.sh" Play
wait_log 'FSTATE phase=playing' 15
log_after_match
sleep 5
a shell input keyevent KEYCODE_SLEEP
say "screen off; $(wakefulness)"

for ((n = 1; n <= losses; n++)); do
  (
    for _ in $(seq 1 30); do
      echo "$(date +%T.%N | cut -c1-12) $(service_foreground_value) session=$(session_state)"
    done
  ) >"$out/poll_$n.txt" &
  poller=$!
  a shell cmd notification post -t "'fiatsonus transient'" fiatsonus_transient "'loss $n'" >/dev/null
  wait_log 'FSTATE phase=interrupted' 10
  log_after_match
  wait_log 'FSTATE phase=playing' 15
  log_after_match
  wait "$poller"
  say "loss $n: interrupted, then playing again"
  sleep 12
done

wakefulness >"$out/wakefulness.txt"
services_dump >"$out/services_after_losses.txt"
a shell logcat -d | tr -d '\r' |
  grep -E 'ForegroundServiceStartNotAllowed|FATAL EXCEPTION|AudioHardening' >"$out/errors.txt" || true

if grep -v -h -F 'isForeground=true' "$out"/poll_*.txt >"$out/poll_misses.txt"; then
  die "a poll sample shows the service out of the foreground (see poll_misses.txt)"
fi
service_foreground || die "the service left the foreground during the interruptions"
starts=$(awk '/AudioService[[:space:]}]/ { in_svc = 1 } in_svc && match($0, /startForegroundCount=[0-9]+/) {
  print substr($0, RSTART + 21, RLENGTH - 21); exit }' "$out/services_after_losses.txt")
if [ -n "$starts" ] && [ "$starts" != 1 ]; then
  die "startForegroundCount=$starts: the service was started in the foreground again"
fi
grep -qE '^mWakefulness=(Asleep|Dozing)$' "$out/wakefulness.txt" || die "the screen came on during the run ($(cat "$out/wakefulness.txt"))"
[ ! -s "$out/errors.txt" ] || die "logcat holds errors (see errors.txt)"
say "foreground kept (startForegroundCount=${starts:-n/a}), screen $(cat "$out/wakefulness.txt"), no errors"

"$DEVICE_DIR/snapshot.sh" "$out/t0"
sleep 25
"$DEVICE_DIR/snapshot.sh" "$out/t1"
report_status=0
dart "$DEVICE_DIR/report.dart" --t0 "$out/t0" --t1 "$out/t1" --expect-foreground |
  tee "$out/report.txt" || report_status=$?

wake_unlock
"$DEVICE_DIR/ui_tap.sh" Stop
wait_log 'FSTATE phase=idle' 10
# Saved before the assertions so a failing run keeps its evidence.
sleep 5
services_dump >"$out/services_after_stop.txt"
notification_excerpt >"$out/notification_after_stop.txt"
a shell dumpsys power | tr -d '\r' >"$out/power_after_stop.txt"
assert_stopped_clean
[ "$report_status" -eq 0 ] || die "the report over the resumed playback failed (see report.txt)"
say "PASS"
