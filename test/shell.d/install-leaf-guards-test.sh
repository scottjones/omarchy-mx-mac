#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# run_logged sources every leaf under bash -eE, where an assignment from a
# failing command substitution aborts the leaf, and the abort takes every later
# stage down with it. Hardware probes read sysfs and procfs paths that simply
# do not exist on other machines (Apple Silicon has no DMI), so each probe has
# to tolerate a missing file: either "|| true" inside the substitution, or the
# assignment itself as an if condition.
unguarded=()
while read -r leaf; do
  while IFS= read -r line; do
    [[ $line == *'|| true'* ]] && continue
    [[ $line =~ ^[[:space:]]*(el)?if[[:space:]] ]] && continue
    unguarded+=("${leaf#"$ROOT/"}: ${line#"${line%%[![:space:]]*}"}")
  done < <(grep -E '\$\(cat /(sys|proc)/' "$leaf" || true)
done < <(find "$ROOT/install" -name '*.sh' -type f | sort)

if (( ${#unguarded[@]} )); then
  fail "install leaves tolerate a missing sysfs probe" \
    "unguarded probes:$(printf '\n  %s' "${unguarded[@]}")"
fi
pass "install leaves tolerate a missing sysfs probe"
