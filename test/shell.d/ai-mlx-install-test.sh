#!/bin/bash

# The entry's failure path runs the upstream installer's --uninstall, which
# deletes every artifact unconditionally. Without the guard, a failed install
# over a working one removes the working one.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

installer="$ROOT/bin/omarchy-install-ai-mlx"
[[ -x $installer ]] || fail "the MLX install entry is executable"
bash -n "$installer" || fail "the MLX install entry does not parse"
pass "the MLX install entry is present and parses"

work=$(mktemp -d)
trap 'chmod -R u+rwX -- "$work" 2>/dev/null; rm -rf -- "$work"' EXIT

stub_dir="$work/stubs"
mkdir -p "$stub_dir"
printf '#!/bin/bash\nexit 0\n' >"$stub_dir/omarchy-hw-apple-silicon"
printf '#!/bin/bash\n[[ ${OMARCHY_TEST_MLX:-1} == 1 ]]\n' >"$stub_dir/omarchy-hw-mlx-supported"
chmod +x "$stub_dir/omarchy-hw-apple-silicon" "$stub_dir/omarchy-hw-mlx-supported"
printf 'apple,j313\0apple,t8103\0' >"$work/compatible"

curl_log="$work/curl.log"

make_curl_stub() {
  cat >"$stub_dir/curl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CURL_LOG"
out=""
prev=""
for a in "$@"; do
  [[ $prev == -o ]] && out="$a"
  prev="$a"
done
[[ -n $out && -n ${INSTALLER_FIXTURE:-} ]] && cp -- "$INSTALLER_FIXTURE" "$out"
exit 0
SH
  chmod +x "$stub_dir/curl"
}
make_curl_stub

run_entry() {
  local home="$1" prefix="$2"
  local status=0
  : >"$curl_log"
  PATH="$stub_dir:$PATH" \
    HOME="$home" \
    MLX_OMARCHY_HOME="$prefix" \
    OMARCHY_APPLE_COMPATIBLE="$work/compatible" \
    CURL_LOG="$curl_log" \
    INSTALLER_FIXTURE="${INSTALLER_FIXTURE:-}" \
    bash "$installer" >"$work/out" 2>&1 || status=$?
  echo "$status"
}

i=0
for artifact in prefix bin-launcher bin-demo desktop-entry; do
  i=$((i + 1))
  home="$work/home$i"
  prefix="$home/.local/share/mlx-omarchy"
  mkdir -p "$home/.local/bin" "$home/.local/share/applications"
  case $artifact in
    prefix) mkdir -p "$prefix" && echo keep >"$prefix/marker" ;;
    bin-launcher) echo keep >"$home/.local/bin/mlx-omarchy" ;;
    bin-demo) echo keep >"$home/.local/bin/mlx-omarchy-demo" ;;
    desktop-entry) echo keep >"$home/.local/share/applications/mlx-omarchy-demo.desktop" ;;
  esac

  got=$(run_entry "$home" "$prefix")
  [[ $got != 0 ]] || fail "$artifact present: the entry should refuse, it exited 0"
  grep -q "already installed" "$work/out" ||
    fail "$artifact present: no explanation given: $(cat "$work/out")"
  grep -q "omarchy-remove-ai-mlx" "$work/out" ||
    fail "$artifact present: refusal should name how to remove it"
  [[ ! -s $curl_log ]] ||
    fail "$artifact present: refused only after fetching the installer: $(cat "$curl_log")"

  case $artifact in
    prefix) [[ -f $prefix/marker ]] || fail "the existing installation was deleted" ;;
    bin-launcher) [[ -f $home/.local/bin/mlx-omarchy ]] || fail "the existing launcher was deleted" ;;
    bin-demo) [[ -f $home/.local/bin/mlx-omarchy-demo ]] || fail "the existing demo launcher was deleted" ;;
    desktop-entry) [[ -f $home/.local/share/applications/mlx-omarchy-demo.desktop ]] || fail "the existing desktop entry was deleted" ;;
  esac
  pass "$artifact present: refuses before any change, and keeps it"
done

OMARCHY_TEST_MLX=0
export OMARCHY_TEST_MLX
home="$work/home-m2"
prefix="$home/.local/share/mlx-omarchy"
mkdir -p "$home/.local/bin"
got=$(run_entry "$home" "$prefix")
[[ $got == 0 ]] || fail "an unsupported Apple GPU should skip, not fail"
grep -q 'does not support this Apple GPU yet' "$work/out" || fail "the skip names the GPU gate: $(cat "$work/out")"
[[ ! -s $curl_log ]] || fail "the skip must not fetch the installer"
pass "unsupported Apple GPUs skip without installing"
unset OMARCHY_TEST_MLX

fixture="$work/install.sh"
ref=$(grep -m1 '^INSTALLER_REF=' "$installer" | cut -d'"' -f2)
repo=$(grep -m1 '^INSTALLER_REPO=' "$installer" | cut -d'"' -f2)

if command -v curl >/dev/null &&
  /usr/bin/env curl -fsSL --max-time 20 \
    "https://raw.githubusercontent.com/$repo/$ref/install.sh" -o "$fixture" 2>/dev/null; then
  pass "fetched the pinned installer (${ref:0:12}) as a fixture"
  export INSTALLER_FIXTURE="$fixture"
  printf 'apple,j313\0apple,t8103\0' >"$work/compatible"

  home="$work/home-fail"
  prefix="$home/.local/share/mlx-omarchy"
  mkdir -p "$home/.local/bin" "$home/.local/share/applications"

  got=$(run_entry "$home" "$prefix")
  [[ $got != 0 ]] || fail "a failing install should not exit 0"
  grep -q "installation failed (exit $got)" "$work/out" ||
    fail "the failure message should name the real status: $(cat "$work/out")"
  if grep -q "installation failed (exit 0)" "$work/out"; then
    fail "the old bug is back: a real failure reported as exit 0"
  fi
  pass "a failing install exits $got and names that status"

  grep -q "Nothing from mlx-omarchy is left installed" "$work/out" ||
    fail "a successful cleanup should say so: $(cat "$work/out")"
  [[ ! -e $prefix ]] || fail "cleanup left $prefix behind"
  pass "cleanup ran and reported a clean machine"

  home="$work/home-dirty"
  prefix="$home/.local/share/mlx-omarchy"
  mkdir -p "$home/.local/bin" "$home/.local/share/applications"
  chmod 000 "$home/.local/bin"

  got=$(run_entry "$home" "$prefix")
  chmod 755 "$home/.local/bin"

  if grep -q "Cleanup did not finish" "$work/out"; then
    [[ $got != 0 ]] || fail "a failed cleanup should still return the install's status"
    grep -q "omarchy-remove-ai-mlx" "$work/out" ||
      fail "a failed cleanup should say how to finish removing it"
    if grep -q "Nothing from mlx-omarchy is left installed" "$work/out"; then
      fail "it claimed a clean machine and a failed cleanup at once"
    fi
    pass "a failed cleanup is reported instead of claiming nothing remains"
  else
    if (( EUID == 0 )); then
      echo "- running as root, so an unwritable directory does not fail rm"
    else
      fail "the failed-cleanup path was not reached: $(cat "$work/out")"
    fi
  fi
else
  echo "- no network for the pinned installer, so the failure paths are not exercised"
fi
