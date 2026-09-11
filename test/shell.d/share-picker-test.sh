#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/user/hardware/apple/share-picker.sh"
all="$ROOT/install/user/all.sh"
migration="$ROOT/migrations/1789140928.sh"
flags="$ROOT/config/chromium-flags.conf"

grep -Fq 'hardware/apple/share-picker.sh' "$all" ||
  fail "the share-picker leaf runs during user setup"
[[ -f $migration ]] || fail "existing installs get the share-picker migration"
! grep -Fq 'WebRTCPipeWireCapturer' "$flags" ||
  fail "shipped Chromium flags must not force the PipeWire capturer on x86"
pass "fresh and existing installs are wired to the screen-share picker"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/uname" <<'SH'
#!/bin/bash
[[ ${1:-} == -m ]] && { printf '%s\n' "${TEST_ARCH:-x86_64}"; exit 0; }
exec /usr/bin/uname "$@"
SH
cat >"$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
[[ ${PICKER_PRESENT:-0} != 1 ]]
SH
cat >"$stub_bin/omarchy-pkg-aur-add" <<'SH'
#!/bin/bash
printf 'aur-add %s\n' "$*" >>"$TEST_LOG"
SH
chmod +x "$stub_bin"/*

run_leaf() {
  : >"$calls"
  TEST_ARCH="${1:-x86_64}" PICKER_PRESENT="${2:-0}" TEST_LOG="$calls" \
    PATH="$stub_bin:$PATH" bash -c 'source "$1"' _ "$leaf"
}

run_leaf x86_64 0
[[ ! -s $calls ]] || fail "x86 does not build the -git picker" "$(cat "$calls")"
pass "x86 leaves the packaged picker alone"

run_leaf aarch64 1
[[ ! -s $calls ]] || fail "aarch64 does not rebuild a present picker" "$(cat "$calls")"
pass "aarch64 skips the AUR build when the picker is already present"

run_leaf aarch64 0
grep -Fxq 'aur-add hyprland-preview-share-picker-git' "$calls" ||
  fail "aarch64 builds the -git picker when missing" "$(cat "$calls")"
pass "aarch64 builds the -git picker when missing"

conf="$test_tmp/home/.config/chromium-flags.conf"
mkdir -p "$(dirname "$conf")"
printf '%s\n' '--enable-features=TouchpadOverscrollHistoryNavigation' >"$conf"
HOME="$test_tmp/home" TEST_ARCH=x86_64 TEST_LOG="$calls" PATH="$stub_bin:$PATH" bash "$migration"
! grep -Fq 'WebRTCPipeWireCapturer' "$conf" ||
  fail "the migration must not rewrite x86 Chromium flags"
pass "the migration leaves x86 Chromium flags alone"

printf '%s\n' '--enable-features=TouchpadOverscrollHistoryNavigation' >"$conf"
HOME="$test_tmp/home" TEST_ARCH=aarch64 TEST_LOG="$calls" PATH="$stub_bin:$PATH" bash "$migration"
grep -Fq 'WebRTCPipeWireCapturer' "$conf" ||
  fail "the migration enables PipeWire capture on existing aarch64 Chromium flags"
pass "the migration enables PipeWire capture on existing aarch64 Chromium flags"
