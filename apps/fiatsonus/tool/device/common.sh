# Sourced by the device scripts: the phone, the package and shared helpers.
# shellcheck shell=bash

SERIAL=${FIATSONUS_SERIAL:-10DF1Q03JJ000HK}
PKG=dev.fiatcode.fiatsonus
DEVICE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_DIR=$(cd "$DEVICE_DIR/../.." && pwd)

a() { adb -s "$SERIAL" "$@"; }

die() {
  echo "$(basename "$0"): $*" >&2
  exit 1
}

say() { echo "[$(date +%H:%M:%S)] $*"; }

require_device() {
  [ "$(adb -s "$SERIAL" get-state 2>/dev/null || true)" = device ] ||
    die "device $SERIAL is not connected"
}

# Pipelines below capture the dump first: `grep -q` quitting early would
# SIGPIPE adb and, under pipefail, turn a match into a failure.
keyguard_showing() {
  local dump
  dump=$(a shell dumpsys window)
  grep -q 'isKeyguardShowing=true' <<<"$dump"
}

wake_unlock() {
  a shell input keyevent KEYCODE_WAKEUP
  a shell wm dismiss-keyguard
  sleep 1
  if keyguard_showing; then die "unlock the phone"; fi
}

# Device wall clock in seconds with a fraction, the format of `logcat -v epoch`.
device_epoch() { a shell 'echo $EPOCHREALTIME' | tr -d '\r'; }

# wait_log only sees lines at or after LOG_SINCE. mark_log moves it to now;
# a script's own `logcat -c` also counts as its start.
LOG_SINCE=
mark_log() { LOG_SINCE=$(device_epoch); }

# Prints the flutter log lines since LOG_SINCE.
flutter_log() {
  if [ -n "$LOG_SINCE" ]; then
    a shell logcat -d -v epoch -T "$LOG_SINCE" -s flutter:I | tr -d '\r'
  else
    a shell logcat -d -v epoch -s flutter:I | tr -d '\r'
  fi
}

# wait_log <pattern> <seconds>: polls once a second for a flutter line matching
# the extended regex <pattern>; prints the first match. The matched line's
# epoch is left in LOG_MATCH_EPOCH so a caller can wait for what follows it.
LOG_MATCH_EPOCH=
wait_log() {
  local pattern=$1 seconds=$2 line i
  for ((i = 0; i <= seconds; i++)); do
    line=$(flutter_log | grep -E -m 1 -- "$pattern" || true)
    if [ -n "$line" ]; then
      LOG_MATCH_EPOCH=$(awk '{print $1}' <<<"$line")
      echo "$line"
      return 0
    fi
    sleep 1
  done
  die "no log line matching '$pattern' within ${seconds}s"
}

# Force-stops and starts the app, then checks its process reaches logcat.
# This vivo sometimes drops every main-buffer line of a freshly started app
# process (its events-buffer lines still appear); the scripts read FSTAT and
# FSTATE from logcat, so such a process is restarted, up to three times.
start_app() {
  local attempt pid i
  for attempt in 1 2 3; do
    a shell am force-stop "$PKG"
    a shell am start -W -n "$PKG/.MainActivity" >/dev/null
    pid=$(a shell pidof "$PKG" | tr -d '\r')
    for ((i = 0; i < 10; i++)); do
      if [ -n "$(a shell logcat -d --pid "$pid" -s flutter:I | tr -d '\r' | grep -F ' flutter ' || true)" ]; then
        sleep 2
        return 0
      fi
      sleep 1
    done
    say "pid $pid wrote nothing to logcat; restarting ($attempt/3)"
  done
  die "logcat shows no lines from the app; FSTAT cannot be read"
}

# Moves LOG_SINCE just past the last wait_log match.
log_after_match() {
  LOG_SINCE=$(awk -v t="$LOG_MATCH_EPOCH" 'BEGIN { printf "%.3f", t + 0.001 }')
}

services_dump() { a shell dumpsys activity services "$PKG" | tr -d '\r'; }

# Whether the app's AudioService is a started foreground service.
service_foreground() {
  services_dump | awk '
    /^[[:space:]]*\* ServiceRecord\{/ { in_svc = ($0 ~ /AudioService[[:space:]}]/); next }
    /^ {0,2}[^ ]/ { in_svc = 0 }
    in_svc && /(^|[[:space:]])isForeground=true([[:space:]]|$)/ { found = 1 }
    END { exit !found }'
}

# Whether the app's AudioService is still started or in the foreground.
# A bound-only record does not count: the activity's MediaBrowser binds the
# service from launch, before any play, so the record outlives every stop.
service_present() {
  services_dump | awk '
    /^[[:space:]]*\* ServiceRecord\{/ { in_svc = ($0 ~ /AudioService[[:space:]}]/); next }
    /^ {0,2}[^ ]/ { in_svc = 0 }
    in_svc && /(^|[[:space:]])(isForeground|startRequested)=true([[:space:]]|$)/ { found = 1 }
    END { exit !found }'
}

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

notification_dump() { a shell dumpsys notification --noredact | tr -d '\r'; }

# The NotificationRecord blocks of $PKG in the posted "Notification List"
# (records start at four spaces; their details are indented deeper).
notification_excerpt() {
  notification_dump | awk -v pkg="pkg=$PKG " '
    /^  Notification List:/ { in_list = 1; next }
    in_list && /^ {0,2}[^ ]/ { in_list = 0 }
    !in_list { show = 0; next }
    /^    [^ ]/ { show = (/NotificationRecord\(/ && index($0, pkg) > 0) }
    show'
}

# Whether a posted notification of $PKG exists.
notification_present() {
  [ -n "$(notification_excerpt)" ]
}

# Waits up to <seconds> for a predicate to become false.
wait_gone() {
  local what=$1 seconds=$2 i
  for ((i = 0; i < seconds; i++)); do
    "$what" || return 0
    sleep 1
  done
  ! "$what"
}

# Whether the "Wake Locks:" section of `dumpsys power` (the locks held now,
# not the wake lock logs further down) holds audio_service's lock.
audio_wake_lock_held() {
  a shell dumpsys power | tr -d '\r' |
    awk -v tag="'com.ryanheise.audioservice.AudioService'" '
      /^Wake Locks: size=/ { in_locks = 1; next }
      in_locks && /^$/ { in_locks = 0 }
      in_locks && index($0, tag) { found = 1 }
      END { exit !found }'
}

# Asserts the service, the notification of $PKG and audio_service's wake lock
# are all gone.
assert_stopped_clean() {
  wait_gone service_present 5 || die "the service is still started or in the foreground after stop"
  wait_gone notification_present 5 || die "a notification of $PKG remains after stop"
  wait_gone audio_wake_lock_held 5 || die "audio_service's wake lock is still held after stop"
  say "service and notification gone; wake lock released"
}

# install_apk <apk>: Play's developer verification rejects adb installs
# (INSTALL_FAILED_VERIFICATION_FAILURE) unless someone touched the phone
# recently. Retries once a minute for up to 30 minutes so the user can.
install_apk() {
  local apk=$1 attempt
  echo "TOUCH THE PHONE NOW: installing $(basename "$apk")"
  for attempt in $(seq 1 30); do
    wake_unlock
    if a install -r "$apk"; then return 0; fi
    [ "$attempt" -lt 30 ] || die "install failed $attempt times"
    say "install failed; touch the phone. Retrying in 60s"
    sleep 60
  done
}

# Resolves <dir> to an absolute path and creates it.
outdir() {
  mkdir -p "$1"
  (cd "$1" && pwd)
}
