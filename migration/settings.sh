#!/usr/bin/env bash
# Repository settings for the Neurobagel monorepo (applied by a maintainer with `gh`).
#
# Usage: settings.sh <owner/repo> [--rehearsal]            print the gh commands (dry run)
#        settings.sh <owner/repo> [--rehearsal] --apply    run them
#
#   --rehearsal  for the rehearsal repository (neurobagel/testplace): no branch protection,
#                so rebuilds can be force-pushed.
#
# Sets: merge options, branch protection on main, labels, Dependabot security updates,
# CodeQL default setup, and repository variables with SAFE (validation) targets:
# ghcr.io images, TestPyPI, site deploys off; MIRROR_OWNER=neurobagel (the mirror to the old
# repositories: draft PRs only until they are locked at switchover). Switching the variables to production
# (Docker Hub, PyPI, site deploys on) is a separate maintainer decision, see the end of
# this script; it is never applied here.
#
# Not covered (by hand): access to org secrets and the bot app, the pre-commit.ci app,
# Netlify sites and their secrets, a TestPyPI PYPI_TOKEN repository secret for validation.
set -euo pipefail

repo="${1:?usage: settings.sh <owner/repo> [--rehearsal] [--apply]}"
shift
apply=0; rehearsal=0
for a in "$@"; do
  case "${a}" in
    --apply) apply=1 ;;
    --rehearsal) rehearsal=1 ;;
    *) echo "unknown option ${a}" >&2; exit 2 ;;
  esac
done

run() {
  printf '+'; printf ' %q' "$@"; printf '\n'
  if [[ ${apply} -eq 1 ]]; then "$@"; fi
}

# Merge options: squash (default, PR title as message, empty body) and merge commits
# (multi-package PRs); no rebase merges.
run gh api -X PATCH "repos/${repo}" \
  -F allow_squash_merge=true -F allow_merge_commit=true -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=BLANK \
  -f merge_commit_title=MERGE_MESSAGE -f merge_commit_message=PR_TITLE

# Branch protection on main: PRs with one approving review; no required status checks yet
# (when added: one always-running aggregator job, see DEVELOPING.md at the repository root).
# Not in the rehearsal repository, which is rebuilt by force-pushing.
[[ ${rehearsal} -eq 1 ]] || run gh api -X PUT "repos/${repo}/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "restrictions": null
}
JSON

# Labels used by release-please, Dependabot, bots, external PRs and the stale workflow.
label() { run gh label create "$1" --repo "${repo}" --color "$2" --description "$3" --force; }
label "autorelease: pending" "ededed" "release-please: release PR not yet tagged"
label "autorelease: tagged" "ededed" "release-please: release PR tagged"
label "_bot" "bfdadc" "Opened by a bot"
label "dependencies" "0366d6" "Dependency updates"
label "_community" "c5def5" "PR from a fork"
label "_flag:stale" "fef2c0" "No activity for 75 days"
label "someday" "d4c5f9" "Not prioritized; ignored by the stale workflow"

# Security: Dependabot alerts and security updates, CodeQL default setup.
run gh api -X PUT "repos/${repo}/vulnerability-alerts"
run gh api -X PUT "repos/${repo}/automated-security-fixes"
run gh api -X PATCH "repos/${repo}/code-scanning/default-setup" -f state=configured

# Repository variables: SAFE targets for validation.
# (gh api rather than `gh variable`, which needs gh >= 2.31)
variable() {
  printf '+ set repository variable %s=%s\n' "$1" "$2"
  if [[ ${apply} -eq 1 ]]; then
    gh api -X PATCH "repos/${repo}/actions/variables/$1" -f name="$1" -f value="$2" >/dev/null 2>&1 \
      || gh api -X POST "repos/${repo}/actions/variables" -f name="$1" -f value="$2" >/dev/null
  fi
}
variable IMAGE_REGISTRY "ghcr.io"
variable IMAGE_NAMESPACE "neurobagel"
variable PYPI_REPOSITORY_URL "https://test.pypi.org/legacy/"
variable SITE_DEPLOY "false"
variable MIRROR_OWNER "neurobagel"

cat <<EOF

# Production targets (maintainer decision, Phase 6; not run by this script):
#   gh api -X PATCH repos/${repo}/actions/variables/IMAGE_REGISTRY -f name=IMAGE_REGISTRY -f value=docker.io
#   gh api -X DELETE repos/${repo}/actions/variables/PYPI_REPOSITORY_URL
#   gh secret delete PYPI_TOKEN --repo ${repo}   # if a TestPyPI token was set for validation
#   gh api -X PATCH repos/${repo}/actions/variables/SITE_DEPLOY -f name=SITE_DEPLOY -f value=true
#
# Mirror merging (maintainer, after switchover, once the draft mirror PRs are green; never in
# the rehearsal repository):
#   gh api -X POST repos/${repo}/actions/variables -f name=MIRROR_MERGE -f value=true
EOF
