#!/usr/bin/env bash
# Build the Neurobagel monorepo from scratch: import, migration/ records, patches, verify.
#
# Usage: migrate.sh <target-dir> [--no-patches] [--no-verify] [--work-dir=DIR]
#
#   --work-dir=DIR  scratch space for the import (DIR/import) and verify (DIR/verify);
#                   default: next to the target (<target-dir>.work, <target-dir>.verify)
#
#   1. import.sh <target-dir>             history, tags, shared data, symlinks, submodules
#   2. commit the current migration/ directory (generated, see below)
#   3. git am migration/patches/*.patch   the monorepo setup, one concern per patch
#   4. verify.sh <target-dir>
#
# Step 2 copies this directory into <target-dir>/migration/, with the plan (without its
# agent environment section) as migration/PLAN.md. It is generated rather than a patch
# because these files keep changing until the final import.
#
# Step 3 sets release-please's bootstrap-sha (in release-please-config.json, added by a
# patch) to the last import commit, and each package's version in the manifest
# (.release-please-manifest.json) to its latest imported release tag, so a refresh against
# newer upstream (new commits or releases) needs no patch edit.
#
# Commits use a fixed identity and the import's fixed date, so reruns against the same
# upstream state give identical hashes. Never pushes.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:?usage: migrate.sh <target-dir> [--no-patches] [--no-verify] [--work-dir=DIR]}"
shift
patches=1; verify=1; workdir=""
for a in "$@"; do
  case "${a}" in
    --no-patches) patches=0 ;;
    --no-verify) verify=0 ;;
    --work-dir=*) workdir="${a#--work-dir=}" ;;
    *) echo "unknown option ${a}" >&2; exit 2 ;;
  esac
done
plan="${here}/../Neurobagel monorepo migration plan.md"

log() { printf '[migrate] %s\n' "$*" >&2; }

"${here}/import.sh" "${target}" ${workdir:+"${workdir}/import"}
target="$(cd "${target}" && pwd)"

export GIT_AUTHOR_NAME="Claude" GIT_AUTHOR_EMAIL="noreply@anthropic.com"
export GIT_COMMITTER_NAME="Claude" GIT_COMMITTER_EMAIL="noreply@anthropic.com"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fixed_date="$(git -C "${target}" log -1 --format=%ct HEAD)"
import_end="$(git -C "${target}" rev-parse HEAD)"
export GIT_AUTHOR_DATE="@${fixed_date} +0000" GIT_COMMITTER_DATE="@${fixed_date} +0000"

log "commit migration/"
mkdir -p "${target}/migration"
# Copy every file of the working migration/ directory except caches.
( cd "${here}" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' -print0 ) \
  | ( cd "${here}" && xargs -0 -I{} cp --parents {} "${target}/migration/" )
# The plan, without the agent environment section (last section of the plan).
awk '/^## Agent environment/ {exit} {print}' "${plan}" >"${target}/migration/PLAN.md"
git -C "${target}" add migration
git -C "${target}" commit -q -m "docs: add migration/ (plan, scripts and records of the monorepo migration)"

if [[ ${patches} -eq 1 ]]; then
  shopt -s nullglob
  list=("${here}"/patches/*.patch)
  log "apply ${#list[@]} patches (bootstrap-sha ${import_end})"
  if [[ ${#list[@]} -gt 0 ]]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT
    # Manifest versions: the latest <prefix>-vX.Y.Z tag (no pre-releases) on main per package
    # (upstream can have tags on no branch, e.g. query-tool's, or a release in progress).
    versions=()
    while IFS=$'\t' read -r kind _ dir prefix; do
      [[ "${kind}" == pkg ]] || continue
      v="$(git -C "${target}" tag -l "${prefix}-v*" --merged HEAD --sort=-v:refname | sed "s/^${prefix}-v//" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
      versions+=(-e "s#(\"packages/${dir}\": \")[^\"]*\"#\\1${v}\"#")
      log "manifest packages/${dir}: ${v}"
    done < <(uv run --no-project --quiet --with pyyaml==6.0.3 --with git-filter-repo==2.47.0 python "${here}/import_helper.py" names "${here}/names.yaml")
    for f in "${list[@]}"; do
      sed -E -e "s/(\"bootstrap-sha\": \")[0-9a-f]{40}/\1${import_end}/" "${versions[@]}" "${f}" >"${tmp}/$(basename "${f}")"
    done
    git -C "${target}" am -q --committer-date-is-author-date "${tmp}"/*.patch
  fi
fi

if [[ ${verify} -eq 1 ]]; then
  "${here}/verify.sh" "${target}" ${workdir:+"${workdir}/verify"}
fi
