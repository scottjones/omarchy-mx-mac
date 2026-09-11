#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

snapshot="$ROOT/bin/omarchy-snapshot"
restore="$ROOT/bin/omarchy-system-snapshot-restore"

grep -F 'omarchy-cmd-missing limine-snapper-restore' "$snapshot" >/dev/null ||
  fail "snapshot restore detects a missing Limine helper"
grep -F 'omarchy-system-snapshot-restore' "$snapshot" >/dev/null ||
  fail "snapshot restore falls back to the subvolume swap"
! grep -F 'omarchy-mac-snapshot-restore' "$snapshot" "$restore" >/dev/null ||
  fail "snapshot restore does not use a Mac-prefixed command"
grep -F 'subvol=/@' "$restore" >/dev/null ||
  fail "the fallback restore requires the @ subvolume layout"
grep -F 'btrfs subvolume snapshot' "$restore" >/dev/null ||
  fail "the fallback restore swaps a writable snapshot into @"
pass "snapshot restore uses Limine when present and the subvolume swap when not"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
[[ $1 == limine-snapper-restore && ${LIMINE_RESTORE:-0} != 1 ]]
SH
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
SH
cat >"$stub_bin/limine-snapper-restore" <<'SH'
#!/bin/bash
printf 'limine-restore\n' >>"$TEST_LOG"
SH
cat >"$stub_bin/omarchy-system-snapshot-restore" <<'SH'
#!/bin/bash
printf 'subvol-restore\n' >>"$TEST_LOG"
SH
chmod +x "$stub_bin"/*

run_restore() {
  : >"$calls"
  LIMINE_RESTORE="$1" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash "$snapshot" restore
}

run_restore 1
grep -Fx 'sudo limine-snapper-restore' "$calls" >/dev/null ||
  fail "Limine restore is used when the helper is present" "$(cat "$calls")"
! grep -q subvol-restore "$calls" || fail "the subvolume swap is not used when Limine is present"
pass "Limine restore is used when the helper is present"

run_restore 0
grep -Fx 'sudo omarchy-system-snapshot-restore' "$calls" >/dev/null ||
  fail "the subvolume swap is used when Limine is absent" "$(cat "$calls")"
! grep -q limine-restore "$calls" || fail "Limine restore is not used when the helper is absent"
pass "the subvolume swap is used when Limine is absent"
