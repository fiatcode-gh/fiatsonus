#!/usr/bin/env bash
# Builds the release APK, installs it and grants the notification permission.
# Usage: tool/device/install.sh [extra flutter build args]
set -euo pipefail
. "$(dirname "$0")/common.sh"

require_device
(cd "$APP_DIR" && flutter build apk --release "$@")
apk=$APP_DIR/build/app/outputs/flutter-apk/app-release.apk

# Play's developer verification rejects adb installs
# (INSTALL_FAILED_VERIFICATION_FAILURE) unless someone touched the phone
# recently. Retry once a minute for up to 30 minutes so the user can.
for attempt in $(seq 1 30); do
  wake_unlock
  if a install -r "$apk"; then break; fi
  [ "$attempt" -lt 30 ] || die "install failed $attempt times"
  say "install failed; touch the phone. Retrying in 60s"
  sleep 60
done
a shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS
say "installed $apk"
