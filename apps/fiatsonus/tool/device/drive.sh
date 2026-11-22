#!/usr/bin/env bash
# Runs one integration test on the phone in profile mode. install.sh builds
# and installs the profile APK with that target and grants the notification
# permission; `flutter drive` then installs once more on its own (it always
# runs `adb install`), so the user touches the phone at both prompts.
# --keep-app-running stops flutter drive from uninstalling the app afterwards.
# Usage: tool/device/drive.sh <integration test file>
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -eq 1 ] || die "usage: drive.sh <integration test file>"
target=$1
require_device
"$DEVICE_DIR/install.sh" --profile "--target=$target"
echo "TOUCH THE PHONE AGAIN NOW: flutter drive installs once more. Hands off when the app opens."
cd "$APP_DIR"
status=0
flutter drive --profile --keep-app-running -d "$SERIAL" \
  --driver=test_driver/integration_test.dart "--target=$target" || status=$?
exit "$status"
