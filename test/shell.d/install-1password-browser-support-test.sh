#!/bin/bash

# The official 1password package's .install hooks setgid 1Password-BrowserSupport.
# Apple Silicon used to unpack a tarball that had none of those hooks; both
# arches now pkg-add the same packages. The AGX software-GL wrap stays in the
# hardware leaf, not in this installer.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

installer="$ROOT/bin/omarchy-install-service-1password"
grep -Fq 'omarchy-pkg-add 1password 1password-cli' "$installer" ||
  fail "1Password installs from the repos on every architecture"
grep -Fq 'remove_aarch64_tarball_leftovers' "$installer" ||
  fail "1Password removes tarball leftovers before pkg-add"
! grep -Fq 'downloads.1password.com/linux/tar' "$installer" ||
  fail "1Password no longer unpacks the aarch64 tarball"
grep -Fq 'install_chromium_extension' "$installer" ||
  fail "1Password still installs the Chromium extension"
grep -Fq 'wrap_1password_for_agx' "$installer" ||
  fail "1Password still wraps the packaged binary for software GL"
grep -Fq '1password' "$ROOT/install/hardware/apple/electron-gl.sh" ||
  fail "Apple Silicon still wraps 1Password for software GL"
pass "1Password uses pkg-add and keeps the Chromium extension and AGX wrap"
