#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# xpadneo is a DKMS module, so it builds against the headers of the running
# kernel. The installer adds them itself; availability has to ask for exactly
# the same names, or the row shows for a machine that cannot build the module.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
calls="$test_tmp/calls"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'omarchy-pkg-add %s\n' "$*" >>"$CALLS"
STUB

# The rest of the script writes under /etc and pokes the kernel; keep every
# such side effect inside the stubs. The user is already in the input group
# and xpad is not loaded, so no reboot prompt is reached.
cat >"$stub_bin/tee" <<'STUB'
#!/bin/bash
cat >/dev/null
STUB

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
echo "wheel input"
STUB

for tool in lsmod modprobe usermod gum reboot; do
  cat >"$stub_bin/$tool" <<STUB
#!/bin/bash
printf '$tool %s\\n' "\$*" >>"\$CALLS"
STUB
done

chmod +x "$stub_bin"/*

run_install() {
  : >"$calls"
  CALLS="$calls" \
    USER="${USER:-tester}" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-install-gaming-xbox-controllers"
}

run_install >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "installing Xbox controller support fails" "$(<"$test_tmp/err")"
grep -qx 'omarchy-pkg-add linux-headers xpadneo-dkms' "$calls" ||
  fail "stock Arch does not build xpadneo against linux-headers" "$(<"$calls")"
grep -q 'reboot' "$calls" &&
  fail "a stubbed run reaches the reboot path"
pass "xpadneo builds against linux-headers on stock Arch"


# Compare actual installer requests with the independently maintained resolver.
# Both exact lists must change together; a missing or wrong header cannot pass.
run_install >/dev/null
selected=$(OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" bash -c '
  source "$OMARCHY_PATH/install/helpers/optional-packages.sh"
  __omarchy_optional_targets install.gaming.xbox-controllers
  printf "%s\n" "${__omarchy_requested_packages[*]}"
')
grep -Fx "omarchy-pkg-add $selected" "$calls" >/dev/null ||
  fail "availability matches the installer selected targets" "$selected; $(cat "$calls")"
pass "availability includes exactly the headers selected by the installer"
