#!/usr/bin/env bash
# Starts the app and plays through its own Play button.
# Usage: tool/device/play.sh
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -eq 0 ] || die "usage: play.sh"
require_device
mark_log
wake_unlock
start_app
"$DEVICE_DIR/ui_tap.sh" Play
wait_log 'FSTATE phase=playing' 15
