#!/bin/bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/home"
export HOME="$test_tmp/home" OMARCHY_PATH="$ROOT" CALLS="$test_tmp/calls"
export PATH="$test_tmp/bin:$PATH" ARCH=aarch64

cat >"$test_tmp/bin/uname" <<'SH'
#!/bin/bash
echo "$ARCH"
SH
cat >"$test_tmp/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
echo "add:$*" >>"$CALLS"
exit "${PACKAGE_STATUS:-0}"
SH
cat >"$test_tmp/bin/omarchy-launch-steam" <<'SH'
#!/bin/bash
echo "prepare:$*:$HOME" >>"$CALLS"
exit "${PREPARE_STATUS:-0}"
SH
cat >"$test_tmp/bin/omarchy-install-gaming-gpu-lib32" <<'SH'
#!/bin/bash
echo gpu >>"$CALLS"
SH
cat >"$test_tmp/bin/setsid" <<'SH'
#!/bin/bash
echo "launch:$*" >>"$CALLS"
SH
cat >"$test_tmp/bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
echo "drop:$*" >>"$CALLS"
exit "${PACKAGE_STATUS:-0}"
SH
cat >"$test_tmp/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == steam && ${HAS_STEAM:-1} == 1 ]]
SH
cat >"$test_tmp/bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
case $1 in
  steam) [[ ${HAS_STEAM:-1} == 1 ]] ;;
  omarchy-steam-fex) [[ ${HAS_FEX:-0} == 1 ]] ;;
  *) exit 1 ;;
esac
SH
chmod +x "$test_tmp/bin/"*

for arch in x86_64 aarch64; do
  export ARCH=$arch
  : >"$CALLS"
  bash "$ROOT/bin/omarchy-install-gaming-steam" >/dev/null
  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -q '^launch:' "$CALLS" && break
    sleep 0.01
  done
  expected="add:steam"
  if [[ $arch == aarch64 ]]; then expected+=" omarchy-steam-fex"; fi
  expected+=$'\ngpu'
  if [[ $arch == aarch64 ]]; then expected+=$'\n'"prepare:--prepare:$HOME"; fi
  expected+=$'\nlaunch:uwsm-app -- gtk-launch steam'
  [[ $(<"$CALLS") == "$expected" ]] || fail "$arch installs and prepares before desktop launch" "$(<"$CALLS")"

  targets=$(bash -c 'source "$OMARCHY_PATH/install/helpers/optional-packages.sh"; __omarchy_optional_targets install.gaming.steam; echo "${__omarchy_requested_packages[*]}"')
  [[ $(head -1 "$CALLS") == "add:$targets" ]] || fail "$arch menu targets match the actual install transaction"
done
pass "each architecture installs the menu's targets; ARM prepares as the desktop user before launch"

export ARCH=aarch64
for failure in PACKAGE_STATUS=23 PREPARE_STATUS=24; do
  : >"$CALLS"
  status=0
  env "$failure" bash "$ROOT/bin/omarchy-install-gaming-steam" >/dev/null || status=$?
  [[ $status == "${failure#*=}" ]] || fail "installer preserves $failure"
  ! grep -q '^launch:' "$CALLS" || fail "failed setup must not launch Steam"
  if [[ $failure == PACKAGE_STATUS=* ]]; then
    ! grep -q '^prepare:' "$CALLS" || fail "failed installation must not prepare Steam"
  fi
done
pass "installation and preparation failures stop before desktop launch"

for migration in 1789140970 1789347444; do
  for state in x86 absent installed data-only; do
    : >"$CALLS"
    export ARCH=aarch64 HAS_STEAM=1
    rm -rf "$HOME/.local/share/Steam"
    case $state in
      x86) export ARCH=x86_64 ;;
      absent) export HAS_STEAM=0 ;;
      data-only) export HAS_STEAM=0; mkdir -p "$HOME/.local/share/Steam" ;;
    esac
    bash -euo pipefail "$ROOT/migrations/$migration.sh" >/dev/null
    if [[ $state == installed || $state == data-only ]]; then
      [[ $(<"$CALLS") == "add:omarchy-steam-fex"$'\n'"prepare:--prepare:$HOME" ]] || fail "$migration prepares existing ARM Steam users"
    else
      [[ ! -s $CALLS ]] || fail "$migration skips $state"
    fi
  done
  : >"$CALLS"
  status=0
  PACKAGE_STATUS=23 bash -euo pipefail "$ROOT/migrations/$migration.sh" >/dev/null || status=$?
  [[ $status == 23 && $(<"$CALLS") == add:omarchy-steam-fex ]] || fail "$migration propagates install failure before preparation"
done
pass "both migration paths prepare existing ARM users and leave failed installs retryable"

disabled=$(node -e 'const fs=require("fs"); const model=require(process.argv[1]+"/shell/plugins/menu/MenuModel.js"); console.log(model.parseMenuJsonc(fs.readFileSync(process.argv[1]+"/default/omarchy/omarchy-menu.jsonc", "utf8")).find(x=>x.id==="install.gaming.steam").disabled)' "$ROOT")
ARCH=aarch64 HAS_STEAM=1 HAS_FEX=0 bash -c "$disabled" && fail "ARM Steam without its launcher package must remain installable"
ARCH=aarch64 HAS_STEAM=1 HAS_FEX=1 bash -c "$disabled" || fail "complete ARM Steam install disables the row"
ARCH=x86_64 HAS_STEAM=1 HAS_FEX=0 bash -c "$disabled" || fail "x86 Steam does not require the FEX package"
ARCH=x86_64 HAS_STEAM=0 HAS_FEX=0 bash -c "$disabled" && fail "missing x86 Steam must remain installable"
pass "the Install row permits repairing a missing ARM launcher package"

desktop="$HOME/.local/share/applications/steam.desktop"
mkdir -p "$(dirname "$desktop")" "$HOME/.local/share/fex-steam"
printf 'Exec=omarchy-launch-steam %%U\n' >"$desktop"
touch "$HOME/.local/share/fex-steam/fixture"
: >"$CALLS"
if PACKAGE_STATUS=23 bash "$ROOT/bin/omarchy-remove-gaming-steam" >/dev/null; then
  fail "failed package removal must fail the remover"
fi
[[ -f $desktop && -f $HOME/.local/share/fex-steam/fixture ]] || fail "failed removal preserves user data"
: >"$CALLS"
bash "$ROOT/bin/omarchy-remove-gaming-steam" >/dev/null
[[ $(<"$CALLS") == 'drop:steam omarchy-steam-fex' ]] || fail "removal includes both packages"
[[ ! -e $desktop && ! -e $HOME/.local/share/fex-steam ]] || fail "successful removal cleans the owned desktop override and FEX data"
printf 'Exec=custom-steam %%U\n' >"$desktop"
bash "$ROOT/bin/omarchy-remove-gaming-steam" >/dev/null
[[ -f $desktop ]] || fail "removal preserves a custom desktop launcher"
pass "removal handles the package pair and preserves user data on failure"

[[ ! -e $ROOT/bin/omarchy-launch-steam ]] || fail "Omarchy must no longer ship the packaged launcher"
pass "the launcher belongs to omarchy-steam-fex"
