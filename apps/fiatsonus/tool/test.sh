#!/usr/bin/env bash
# Runs the app's host tests. flutter_soloud's build hook needs a clang; when
# none is on PATH, the newest NDK's clang is used.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v clang >/dev/null 2>&1; then
  ndk_bin=$(ls -d "${ANDROID_HOME:-$HOME/.local/share/sdks/android}"/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -z "$ndk_bin" ]; then
    echo "test.sh: no clang on PATH and no Android NDK clang found" >&2
    exit 1
  fi
  PATH="$ndk_bin:$PATH"
  export PATH
fi
exec flutter test "$@"
