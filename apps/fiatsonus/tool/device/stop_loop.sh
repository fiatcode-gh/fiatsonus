#!/usr/bin/env bash
# Repeats play -> stop and checks after each stop that notification 1124, the
# started service and audio_service's wake lock are gone. The leftover
# notification was a race (PLAN 4.6), so one stop cannot show it; the loop
# counts failures and carries on. A stop counts as repaired when the app
# logged that it cancelled the notification left after its service stopped.
# Saves per stop n: events_<n>.txt and system_<n>.txt (what the phone logged
# since the stop), plus leftover_<n>.txt, service_<n>.txt or power_<n>.txt
# for a failed check.
# Usage: tool/device/stop_loop.sh <outdir> <count> <inapp|notif> [play_seconds]
#   inapp stops through the app's Stop button, notif through the
#   notification's. play_seconds defaults to 4.
# Exits 0 on PASS, 1 on FAIL, 2 when the notification shade has no Stop node.
set -euo pipefail
. "$(dirname "$0")/common.sh"

usage="usage: stop_loop.sh <outdir> <count> <inapp|notif> [play_seconds]"
[ $# -ge 3 ] && [ $# -le 4 ] || die "$usage"
count=$2
mode=$3
play_s=${4:-4}
[[ $count =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ] || die "count must be a positive integer"
[[ $play_s =~ ^[0-9]+$ ]] && [ "$play_s" -gt 0 ] || die "play_seconds must be a positive integer"
[ "$mode" = inapp ] || [ "$mode" = notif ] || die "$usage"
out=$(outdir "$1")
require_device

if [ "$mode" = notif ]; then
  trap 'a shell cmd statusbar collapse || true' EXIT
fi

a shell logcat -G 16M
: >"$out/summary.txt"
leftovers=0
services=0
wake_locks=0
repaired=0
need_start=true
for ((n = 1; n <= count; n++)); do
  if $need_start; then
    wake_unlock
    start_app
    need_start=false
  fi
  mark_log
  "$DEVICE_DIR/ui_tap.sh" Play >/dev/null
  wait_log 'FSTATE phase=playing' 15 >/dev/null
  sleep "$play_s"
  t_stop=$(device_epoch)
  mark_log
  if [ "$mode" = notif ]; then
    a shell cmd statusbar expand-notifications
    sleep 2
    tap_status=0
    "$DEVICE_DIR/ui_tap.sh" Stop com.android.systemui >/dev/null 2>&1 || tap_status=$?
    if [ "$tap_status" -eq 2 ]; then
      a shell cmd statusbar collapse
      echo "no Stop node in the notification shade" >&2
      exit 2
    fi
    [ "$tap_status" -eq 0 ] || die "ui_tap.sh exited $tap_status"
  else
    "$DEVICE_DIR/ui_tap.sh" Stop >/dev/null
  fi
  wait_log 'FSTATE phase=idle' 10 >/dev/null
  if [ "$mode" = notif ]; then a shell cmd statusbar collapse; fi
  sleep 5

  a shell logcat -d -b events -v epoch -T "$t_stop" | tr -d '\r' |
    grep -E 'notification_|fiatsonus' >"$out/events_$n.txt" || true
  a shell logcat -d -b system,main -v epoch -T "$t_stop" | tr -d '\r' |
    grep -iE 'NotificationService|1124|ActiveServices|fiatsonus' >"$out/system_$n.txt" || true

  failed=
  if ! wait_gone notification_present 5; then
    notification_excerpt >"$out/leftover_$n.txt"
    leftovers=$((leftovers + 1))
    failed+=" LEFTOVER"
  fi
  if ! wait_gone service_present 5; then
    services_dump >"$out/service_$n.txt"
    services=$((services + 1))
    failed+=" SERVICE REMAINS"
  fi
  if ! wait_gone audio_wake_lock_held 5; then
    a shell dumpsys power | tr -d '\r' >"$out/power_$n.txt"
    wake_locks=$((wake_locks + 1))
    failed+=" WAKE LOCK HELD"
  fi
  line="stop $n:${failed:- clean}"
  if grep -qF 'cancelling notification 1124 left after its service stopped' "$out/system_$n.txt"; then
    repaired=$((repaired + 1))
    line+=" repaired"
  fi
  echo "$line" | tee -a "$out/summary.txt"
  [ -z "$failed" ] || need_start=true
done

counts="mode=$mode stops=$count leftovers=$leftovers services=$services wake_locks=$wake_locks repaired=$repaired"
if [ $((leftovers + services + wake_locks)) -eq 0 ]; then
  echo "PASS $counts" | tee -a "$out/summary.txt"
else
  echo "FAIL $counts" | tee -a "$out/summary.txt"
  exit 1
fi
