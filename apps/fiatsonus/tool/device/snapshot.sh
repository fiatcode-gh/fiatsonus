#!/usr/bin/env bash
# Writes one device snapshot in the layout report.dart reads.
# Usage: tool/device/snapshot.sh <dir> [--battery-stats]
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: snapshot.sh <dir> [--battery-stats]"
battery_stats=false
if [ $# -eq 2 ]; then
  [ "$2" = --battery-stats ] || die "unknown argument $2"
  battery_stats=true
fi
require_device
dir=$(outdir "$1")

# Clock and CPU counters in one shell call, so they describe the same instant.
raw=$(a shell "
  pid=\$(pidof $PKG)
  echo \"epoch_ms=\$(date +%s%3N)\"
  echo \"uptime_s=\$(cut -d' ' -f1 /proc/uptime)\"
  echo '@@pid'
  echo \"\$pid\"
  echo '@@proc'
  [ -n \"\$pid\" ] && cat /proc/\$pid/stat
  echo '@@task'
  [ -n \"\$pid\" ] && cat /proc/\$pid/task/*/stat
  echo '@@cpufreq'
  for c in /sys/devices/system/cpu/cpu[0-9]*; do
    echo \"\${c##*/} cur_khz=\$(cat \$c/cpufreq/scaling_cur_freq 2>/dev/null) max_khz=\$(cat \$c/cpufreq/cpuinfo_max_freq 2>/dev/null)\"
  done
  true
" | tr -d '\r')
for f in time.txt pid.txt proc_stat.txt task_stat.txt cpufreq.txt; do : >"$dir/$f"; done
awk -v dir="$dir" '
  /^@@pid$/ { file = "pid.txt"; next }
  /^@@proc$/ { file = "proc_stat.txt"; next }
  /^@@task$/ { file = "task_stat.txt"; next }
  /^@@cpufreq$/ { file = "cpufreq.txt"; next }
  { print >> (dir "/" (file == "" ? "time.txt" : file)) }' <<<"$raw"
sed -i '/^$/d' "$dir/pid.txt"

a shell dumpsys media.audio_flinger | tr -d '\r' >"$dir/audio_flinger.txt"
a shell dumpsys battery | tr -d '\r' >"$dir/battery.txt"
a shell logcat -d -v epoch -s flutter:I | tr -d '\r' | grep -F 'FSTAT ' | tail -n 1 >"$dir/fstat.txt" || true
services_dump >"$dir/services.txt"
if $battery_stats; then
  a shell dumpsys batterystats --history | tr -d '\r' >"$dir/batterystats_history.txt"
  a shell dumpsys batterystats --charged "$PKG" | tr -d '\r' >"$dir/batterystats_app.txt"
fi
say "snapshot $dir (pid $(cat "$dir/pid.txt"))"
