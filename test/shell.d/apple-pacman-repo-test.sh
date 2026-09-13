#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/pacman.sh"
hardware_pacman="$ROOT/install/hardware/pacman.sh"
migration="$ROOT/migrations/1789336732.sh"

grep -Fq 'hardware/apple/pacman.sh' "$hardware_pacman" ||
  fail "the Apple Silicon repository leaf runs with the hardware pacman extensions"
grep -Fq 'hardware/pacman.sh' "$ROOT/install/post-install/pacman.sh" ||
  fail "hardware pacman extensions still run after the pacman.conf restore"
pass "the [omarchy-aarch64] leaf is wired into system setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
conf="$test_tmp/pacman.conf"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
[[ ${APPLE_SILICON:-0} == "1" ]]
SH
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
exec "$@"
SH
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$TEST_LOG"
SH
chmod +x "$stub_bin"/*

stock_conf() {
  printf '%s\n' '[options]' 'Architecture = auto' '' '[core]' 'Include = /etc/pacman.d/mirrorlist' >"$conf"
}

run_leaf() {
  : >"$calls"
  APPLE_SILICON="${1:-0}" OMARCHY_PACMAN_CONF="$conf" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash -euo pipefail -c 'source "$1"' _ "$leaf"
}

run_migration() {
  : >"$calls"
  APPLE_SILICON="${1:-0}" OMARCHY_PACMAN_CONF="$conf" OMARCHY_PATH="$ROOT" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash -euo pipefail "$migration"
}

stock_conf
before=$(cat "$conf")
run_leaf 0
[[ $(cat "$conf") == "$before" ]] || fail "the leaf leaves pacman.conf alone off Apple Silicon"
pass "the leaf is a no-op off Apple Silicon"

run_leaf 1
grep -Fxq '[omarchy-aarch64]' "$conf" || fail "Apple Silicon gets the [omarchy-aarch64] stanza" "$(cat "$conf")"
grep -Fxq 'Server = https://github.com/omarchy-mac/omarchy-pkgs-aarch64/releases/download/edge' "$conf" ||
  fail "the stanza points at the omarchy-pkgs-aarch64 releases"
grep -Fxq 'SigLevel = Optional TrustAll' "$conf" || fail "the stanza declares the unsigned repository"
grep -Fxq '[core]' "$conf" || fail "the existing repositories are kept"
pass "Apple Silicon gets the [omarchy-aarch64] repository"

after=$(cat "$conf")
run_leaf 1
[[ $(cat "$conf") == "$after" ]] || fail "the leaf does not append a second stanza"
(( $(grep -c '^\[omarchy-aarch64\]' "$conf") == 1 )) || fail "exactly one stanza is present"
pass "the leaf is idempotent"

stock_conf
run_migration 0
! grep -q 'omarchy-aarch64' "$conf" || fail "the migration does not write on x86"
[[ ! -s $calls ]] || fail "the migration runs nothing on x86" "$(cat "$calls")"
pass "the migration is a no-op off Apple Silicon"

run_migration 1
grep -Fxq '[omarchy-aarch64]' "$conf" || fail "the migration adds the stanza on Apple Silicon"
grep -Fxq 'pacman -Sy' "$calls" || fail "the migration fetches the new database" "$(cat "$calls")"
pass "the migration adds the repository and syncs its database"

run_migration 1
! grep -q 'pacman -Sy' "$calls" || fail "a rerun does not resync when nothing was added" "$(cat "$calls")"
(( $(grep -c '^\[omarchy-aarch64\]' "$conf") == 1 )) || fail "a rerun does not duplicate the stanza"
pass "the migration is idempotent"
