#!/usr/bin/env bash
# Builds the release APK (the profile APK with --profile), installs it and
# grants the notification permission. The install needs the user at the
# phone: see install_apk in common.sh.
# Usage: tool/device/install.sh [--profile] [extra flutter build args]
set -euo pipefail
. "$(dirname "$0")/common.sh"

mode=release
if [ "${1:-}" = --profile ]; then
  mode=profile
  shift
fi
require_device
(cd "$APP_DIR" && flutter build apk "--$mode" "$@")
install_apk "$APP_DIR/build/app/outputs/flutter-apk/app-$mode.apk"
a shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS
say "installed the $mode APK"
