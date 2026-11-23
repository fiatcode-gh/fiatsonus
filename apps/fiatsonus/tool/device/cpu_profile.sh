#!/usr/bin/env bash
# Captures the Dart VM's CPU samples of one isolate of the running profile
# build (PLAN D7): finds the VM service address the current process logged,
# forwards it, runs cpu_profile.dart and removes the forward on exit.
# Usage: tool/device/cpu_profile.sh <outdir> <seconds> <isolate-name-part>
set -euo pipefail
. "$(dirname "$0")/common.sh"

[ $# -eq 3 ] || die "usage: cpu_profile.sh <outdir> <seconds> <isolate-name-part>"
seconds=$2
part=$3
[[ $seconds =~ ^[0-9]+$ ]] && [ "$seconds" -gt 0 ] || die "seconds must be a positive integer"
out=$(outdir "$1")
require_device

pid=$(a shell pidof "$PKG" | tr -d '\r')
[ -n "$pid" ] || die "$PKG is not running"
service=
for ((i = 0; i < 30; i++)); do
  service=$(a shell logcat -d --pid "$pid" -s flutter:I | tr -d '\r' |
    grep -oE 'The Dart VM service is listening on http://127\.0\.0\.1:[0-9]+/[^ ]*' |
    tail -n 1 | awk '{ print $NF }' || true)
  [ -n "$service" ] && break
  sleep 1
done
[ -n "$service" ] || die "pid $pid logged no VM service address (is it a profile build?)"
device_port=$(sed -E 's|^http://127\.0\.0\.1:([0-9]+)/.*$|\1|' <<<"$service")
path=$(sed -E 's|^http://127\.0\.0\.1:[0-9]+(/.*)$|\1|' <<<"$service")

host_port=$(a forward tcp:0 "tcp:$device_port" | tr -d '\r')
trap 'a forward --remove "tcp:$host_port" >/dev/null 2>&1 || true' EXIT
say "VM service of pid $pid forwarded to localhost:$host_port; sampling '$part' for ${seconds}s"
cd "$APP_DIR"
dart tool/device/cpu_profile.dart --uri "http://127.0.0.1:$host_port$path" \
  --seconds "$seconds" --isolate "$part" --out "$out"
