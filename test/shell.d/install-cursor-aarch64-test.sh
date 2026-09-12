#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

installer="$ROOT/bin/omarchy-install-editor-cursor"
grep -Fq 'omarchy-pkg-add cursor-bin' "$installer" ||
  fail "Cursor installs cursor-bin on every architecture"
grep -Fq 'remove_aarch64_appimage_leftovers' "$installer" ||
  fail "Cursor removes the old aarch64 AppImage files before pkg-add"
grep -Fq 'wrap_cursor_for_agx' "$installer" ||
  fail "Cursor still wraps the packaged binary for software GL"
grep -Fq 'cursor' "$ROOT/install/hardware/apple/electron-gl.sh" ||
  fail "Apple Silicon still wraps Cursor for software GL"
! grep -Fq 'cursor.AppImage --appimage-extract' "$installer" ||
  fail "Cursor no longer extracts an AppImage"
grep -Fq 'omarchy-cmd-present cursor' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null
pass "Cursor installs from cursor-bin and still uses command-presence menu guards"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
mkdir -p "$stub_bin" "$test_tmp/opt/cursor" "$test_tmp/usr/local/bin" \
  "$test_tmp/usr/share/applications" "$test_tmp/usr/share/pixmaps" \
  "$test_tmp/usr/share/icons/hicolor/128x128/apps"
: >"$test_tmp/opt/cursor/cursor.AppImage"
: >"$test_tmp/usr/local/bin/cursor"
: >"$test_tmp/usr/share/applications/cursor.desktop"
: >"$test_tmp/usr/share/applications/cursor-url-handler.desktop"
: >"$test_tmp/usr/share/pixmaps/co.anysphere.cursor.png"
: >"$test_tmp/usr/share/icons/hicolor/128x128/apps/co.anysphere.cursor.png"

cat >"$stub_bin/uname" <<'SH'
#!/bin/bash
[[ ${1:-} == -m ]] && { printf '%s\n' aarch64; exit 0; }
exec /usr/bin/uname "$@"
SH
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
SH
cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$TEST_LOG"
SH
cat >"$stub_bin/gtk-launch" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ ${CURSOR_PKG:-0} == 1 ]]
SH
cat >"$stub_bin/omarchy-cmd-electron-gl-wrap" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-cmd-desktop-exec-repair" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin"/*

run_installer() {
  : >"$calls"
  TEST_LOG="$calls" PATH="$stub_bin:$PATH" bash "$installer" >/dev/null
}

run_installer
grep -Fq 'pkg-add cursor-bin' "$calls" ||
  fail "aarch64 Cursor installer pkg-adds cursor-bin" "$(cat "$calls")"
grep -Fq 'sudo rm -f /opt/cursor/cursor.AppImage' "$calls" ||
  fail "aarch64 Cursor installer removes the old AppImage" "$(cat "$calls")"
pass "aarch64 Cursor installer clears workaround files then pkg-adds cursor-bin"

CURSOR_PKG=1 run_installer
grep -Fq 'pkg-add cursor-bin' "$calls" ||
  fail "already-installed Cursor still pkg-adds cursor-bin" "$(cat "$calls")"
if grep -Fq 'sudo rm' "$calls"; then
  fail "already-installed Cursor must not delete package-owned files" "$(cat "$calls")"
fi
pass "already-installed Cursor leaves package files in place"
