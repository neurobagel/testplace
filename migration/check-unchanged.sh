#!/usr/bin/env bash
# Fail unless every change in the imported packages since the import is on the allowlist.
#
# Usage: check-unchanged.sh [<rev>]   (default HEAD; run from anywhere in the repository)
#
# The packages are the folders imported with history (tools/<name>/, recipes/), found from
# the "chore: import <org>/<repo> history into <dir>" merges on the first-parent history.
# For each, the reference is the second parent of that merge: the upstream tree unchanged.
# Every added, modified, deleted or type-changed path in the package at <rev> must be listed
# in migration/allowed-changes.txt (one path per line, then a tab and the reason). Needs
# the full history.
set -euo pipefail

rev="${1:-HEAD}"
root="$(git rev-parse --show-toplevel)"
allow="${root}/migration/allowed-changes.txt"

mapfile -t allowed < <(grep -v '^\s*#' "${allow}" | grep -v '^\s*$' | cut -f1)
is_allowed() { local p; for p in "${allowed[@]}"; do [[ "$1" == "${p}" ]] && return 0; done; return 1; }

bad=0; changed=0; seen=(); n=0
while IFS=$'\t' read -r merge dir; do
  n=$((n + 1))
  while IFS=$'\t' read -r status path; do
    changed=$((changed + 1)); seen+=("${path}")
    if is_allowed "${path}"; then
      echo "allowed  ${status} ${path}"
    else
      echo "::error::${status} ${path} changed since import and is not in migration/allowed-changes.txt"
      bad=$((bad + 1))
    fi
  done < <(git diff --no-renames --name-status "${merge}^2" "${rev}" -- "${dir}")
done < <(git log --first-parent --format='%H%x09%s' -E --grep='^chore: import [^ ]+ history into [^ ]+$' "${rev}" \
           | sed -E 's/\tchore: import [^ ]+ history into /\t/')
if [[ ${n} -eq 0 ]]; then echo "::error::no import merges found"; exit 1; fi

for p in "${allowed[@]}"; do
  found=0; for s in "${seen[@]}"; do [[ "${s}" == "${p}" ]] && found=1; done
  [[ ${found} -eq 0 ]] && echo "::warning::allowlist entry not changed (stale?): ${p}"
done

echo "${changed} changed path(s) in ${n} imported packages, ${bad} not allowed."
[[ ${bad} -eq 0 ]]
