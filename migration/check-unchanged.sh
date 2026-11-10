#!/usr/bin/env bash
# Fail unless every change under packages/ since the import is on the allowlist.
#
# Usage: check-unchanged.sh [<rev>]   (default HEAD; run from anywhere in the repository)
#
# For each packages/<dir>, the reference is the package as imported: the second parent of
# the "chore: import <org>/<repo> history into packages/<dir>" merge, which is the upstream
# tree unchanged. Every added, modified, deleted or type-changed path below packages/ in
# <rev> must be listed in migration/allowed-changes.txt (one path per line, then a tab and
# the reason). Needs the full history (CI: fetch-depth: 0).
set -euo pipefail

rev="${1:-HEAD}"
root="$(git rev-parse --show-toplevel)"
allow="${root}/migration/allowed-changes.txt"

mapfile -t allowed < <(grep -v '^\s*#' "${allow}" | grep -v '^\s*$' | cut -f1)
is_allowed() { local p; for p in "${allowed[@]}"; do [[ "$1" == "${p}" ]] && return 0; done; return 1; }

bad=0; changed=0; seen=()
for dir in $(git ls-tree --name-only "${rev}" packages/ | sed 's#^packages/##'); do
  merge="$(git log --first-parent --format=%H -n 1 -E \
    --grep="^chore: import [^ ]+ history into packages/${dir}\$" "${rev}")"
  if [[ -z "${merge}" ]]; then
    echo "::error::no import merge found for packages/${dir}"; bad=$((bad + 1)); continue
  fi
  while IFS=$'\t' read -r status path; do
    changed=$((changed + 1)); seen+=("${path}")
    if is_allowed "${path}"; then
      echo "allowed  ${status} ${path}"
    else
      echo "::error::${status} ${path} changed since import and is not in migration/allowed-changes.txt"
      bad=$((bad + 1))
    fi
  done < <(git diff --no-renames --name-status "${merge}^2" "${rev}" -- "packages/${dir}")
done

for p in "${allowed[@]}"; do
  found=0; for s in "${seen[@]}"; do [[ "${s}" == "${p}" ]] && found=1; done
  [[ ${found} -eq 0 ]] && echo "::warning::allowlist entry not changed (stale?): ${p}"
done

echo "${changed} changed path(s) under packages/, ${bad} not allowed."
[[ ${bad} -eq 0 ]]
