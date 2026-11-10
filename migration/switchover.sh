#!/usr/bin/env bash
# Lock the old repositories for the monorepo trial (Phase 5), or unlock them (switch-back).
#
# Usage: switchover.sh <owner> <bot-app-id> [--undo] [--apply]
#   without --apply: print the gh commands (dry run)
#
# For each old repository (names.yaml: the tool repos and the data repos):
#   - ruleset "monorepo-mirror" on all branches and one on all tags: no creation, update,
#     deletion or force-push, except by the bot app (the mirror, tools/mirror.py)
#   - disable the workflows in old-repos-disabled.txt (files unchanged)
#   - Dependabot security updates off (the monorepo covers the same dependencies)
# --undo reverses all three.
#
# By hand: remove the old repositories from pre-commit.ci (add them back when switching back).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
owner="${1:?usage: switchover.sh <owner> <bot-app-id> [--undo] [--apply]}"
app_id="${2:?usage: switchover.sh <owner> <bot-app-id> [--undo] [--apply]}"
shift 2
apply=0; undo=0
for a in "$@"; do
  case "${a}" in
    --apply) apply=1 ;;
    --undo) undo=1 ;;
    *) echo "unknown option ${a}" >&2; exit 2 ;;
  esac
done

run() {
  printf '+'; printf ' %q' "$@"; printf '\n'
  if [[ ${apply} -eq 1 ]]; then "$@"; fi
}

mapfile -t repos < <(uv run --no-project --quiet --with pyyaml==6.0.3 python - "${here}/names.yaml" <<'PY'
import sys, yaml
n = yaml.safe_load(open(sys.argv[1]))
for d in n["data"].values(): print(d["repo"])
for p in n["packages"]: print(p["repo"])
PY
)

ruleset_ids() { # ids of this script's rulesets in a repository
  gh api "repos/${owner}/$1/rulesets" --jq '.[] | select(.name | startswith("monorepo-mirror")) | .id'
}

for repo in "${repos[@]}"; do
  echo "# ${owner}/${repo}"
  if [[ ${undo} -eq 0 ]]; then
    for target in branch tag; do
      run gh api -X POST "repos/${owner}/${repo}/rulesets" --input - <<JSON
{
  "name": "monorepo-mirror-${target}",
  "target": "${target}",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~ALL"], "exclude": []}},
  "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}, {"type": "non_fast_forward"}],
  "bypass_actors": [{"actor_id": ${app_id}, "actor_type": "Integration", "bypass_mode": "always"}]
}
JSON
    done
    while IFS=$'\t' read -r r wf; do
      if [[ "${r}" == "${repo}" ]]; then run gh workflow disable "${wf}" --repo "${owner}/${repo}" </dev/null; fi
    done < <(grep -v '^#' "${here}/old-repos-disabled.txt")
    run gh api -X DELETE "repos/${owner}/${repo}/automated-security-fixes"
  else
    if [[ ${apply} -eq 1 ]]; then
      for id in $(ruleset_ids "${repo}"); do run gh api -X DELETE "repos/${owner}/${repo}/rulesets/${id}"; done
    else
      echo "+ delete the rulesets named monorepo-mirror-* (ids listed at --apply)"
    fi
    while IFS=$'\t' read -r r wf; do
      if [[ "${r}" == "${repo}" ]]; then run gh workflow enable "${wf}" --repo "${owner}/${repo}" </dev/null; fi
    done < <(grep -v '^#' "${here}/old-repos-disabled.txt")
    run gh api -X PUT "repos/${owner}/${repo}/automated-security-fixes"
  fi
done
echo "# by hand: $([[ ${undo} -eq 0 ]] && echo remove || echo add) the old repositories in pre-commit.ci"
