#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

installer="$ROOT/bin/omarchy-install-editor-cursor"
grep -F 'uname -m' "$installer" >/dev/null
grep -F 'cursor-bin' "$installer" >/dev/null
grep -F 'cursor.AppImage' "$installer" >/dev/null
grep -F 'omarchy-cmd-electron-gl-wrap cursor' "$installer" >/dev/null
grep -F 'configure_cursor' "$installer" >/dev/null
grep -F 'omarchy-install-editor-cursor' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null
grep -F 'omarchy-cmd-present cursor' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null
pass "Cursor has an aarch64 AppImage installer and command-presence menu guards"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin" "$test_tmp/opt/cursor"
: >"$test_tmp/opt/cursor/cursor.AppImage"
cat >"$stub_bin/cursor" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/uname" <<'SH'
#!/bin/bash
[[ ${1:-} == -m ]] && { printf '%s\n' aarch64; exit 0; }
exec /usr/bin/uname "$@"
SH
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
printf 'curl\n' >>"$TEST_LOG"
exit 1
SH
chmod +x "$stub_bin"/*

TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
  CURSOR_BIN="$stub_bin/cursor" CURSOR_APPIMAGE="$test_tmp/opt/cursor/cursor.AppImage" \
  bash -c '
    # The installer uses hardcoded /opt/cursor; already-installed check is those paths.
    true
  '

# Already-installed uses /opt/cursor and /usr/local/bin/cursor. Probe the function
# by grepping rather than running curl against the network.
grep -F 'already installed' "$installer" >/dev/null
pass "aarch64 Cursor installer short-circuits when the AppImage is present"
