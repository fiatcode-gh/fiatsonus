#!/usr/bin/env bash
# Taps the centre of the on-screen node whose text or content-desc is <label>.
# Usage: tool/device/ui_tap.sh <label> [package]
# Exits 2 when no such node is on screen after three dumps.
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: ui_tap.sh <label> [package]"
label=$1
package=${2:-}
require_device

for attempt in 1 2 3; do
  xml=$(a shell 'uiautomator dump /sdcard/fiatsonus_ui.xml >/dev/null 2>&1 && cat /sdcard/fiatsonus_ui.xml' | tr -d '\r' || true)
  bounds=$(grep -o '<node [^>]*>' <<<"$xml" | awk -v label="$label" -v pkg="$package" '
    function attr(name,   m) {
      if (match($0, " " name "=\"[^\"]*\"")) {
        m = substr($0, RSTART + length(name) + 3, RLENGTH - length(name) - 4)
        return m
      }
      return ""
    }
    (attr("text") == label || attr("content-desc") == label) &&
      (pkg == "" || attr("package") == pkg) { print attr("bounds"); exit }' || true)
  if [ -n "$bounds" ]; then
    read -r x y < <(sed -E 's/\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]/\1 \2 \3 \4/' <<<"$bounds" |
      awk '{ printf "%d %d\n", ($1 + $3) / 2, ($2 + $4) / 2 }')
    a shell input tap "$x" "$y"
    say "tapped '$label' at $x,$y"
    exit 0
  fi
  if [ "$attempt" -lt 3 ]; then sleep 1; fi
done
echo "ui_tap.sh: no node labelled '$label'${package:+ in $package}" >&2
exit 2
