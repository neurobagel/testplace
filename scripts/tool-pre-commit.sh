#!/usr/bin/env bash
# Run a tool's own pre-commit configuration (tools/<tool>/.pre-commit-config.yaml) from
# inside the tool folder, exactly as in the tool's old repository.
#
# Usage: tool-pre-commit.sh <tool-folder> [file ...]
#   files are relative to the repository root (as pre-commit passes them); without files,
#   the tool's hooks run on all its files. Extra arguments for `pre-commit run` (e.g. a hook
#   id) can be given in TOOL_PRE_COMMIT_ARGS.
#
# Used by the root .pre-commit-config.yaml (one hook per tool), so `pre-commit install`
# once at the root runs every tool's own hooks. pre-commit always runs hooks from the
# repository root, where the tools' relative config paths (--config=.flake8, ...) would not
# resolve. So this script shows git a view in which the tool folder is the repository root:
# the work tree is the folder, and a temporary index holds the folder's staged entries with
# the folder prefix removed. Inside that view, pre-commit behaves as in the old repository.
set -euo pipefail

dir="${1:?usage: tool-pre-commit.sh <tool-folder> [file ...]}"
shift
dir="${dir%/}"
root="$(git rev-parse --show-toplevel)"
gitdir="$(git rev-parse --absolute-git-dir)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# The folder's index entries (staged content), without the folder prefix.
git -C "${root}" ls-files --stage -z -- "${dir}" \
  | sed -z "s#\t${dir}/#\t#" \
  | GIT_INDEX_FILE="${tmp}/index" git -C "${root}" update-index -z --index-info

files=()
for f in "$@"; do files+=("${f#"${dir}"/}"); done

cd "${root}/${dir}"
export GIT_DIR="${gitdir}" GIT_WORK_TREE="${root}/${dir}" GIT_INDEX_FILE="${tmp}/index"
# shellcheck disable=SC2086
if [[ ${#files[@]} -eq 0 ]]; then
  exec pre-commit run ${TOOL_PRE_COMMIT_ARGS:-} --all-files
else
  exec pre-commit run ${TOOL_PRE_COMMIT_ARGS:-} --files "${files[@]}"
fi
