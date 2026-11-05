#!/usr/bin/env bash
# Assemble the Neurobagel monorepo history from the upstream repositories.
#
# Usage: import.sh <target-dir> [work-dir]
#
#   <target-dir>  where the monorepo is assembled. Must not exist, be empty, or be a
#                 git repository without commits (e.g. a fresh `git init` with a remote).
#   [work-dir]    scratch directory for fresh clones (default: <target-dir>.work).
#                 It is deleted and recreated on every run.
#
# Reads names.yaml and commit-rewrites.yaml next to this script. Writes tag-map.txt and
# import-sources.txt next to this script, and per-repo rewrite statistics to the work dir.
# Never pushes. Set IMPORT_ALLOW_UNRESOLVED=1 for a development run with unresolved
# entries in commit-rewrites.yaml (their titles are left unchanged, with a warning).
#
# Steps, per tool package (names.yaml order):
#   fresh clone -> git filter-repo (packages/<dir>/, tags <prefix>-*, commit title rewrites
#   from commit-rewrites.yaml, #N -> <org>/<repo>#N) -> merge --allow-unrelated-histories
#   into main, fetch all tags.
# Then: copy shared data repos (HEAD of their ref, plain files) to deploy/ and testdata/;
# replace the listed submodule gitlinks with relative symlinks to them; keep the other
# gitlinks and declare them in the root .gitmodules; initialize submodules last.
#
# Commits created here use a fixed identity and a fixed date (the newest upstream
# commit date) so that two runs against the same upstream state give identical hashes.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:?usage: import.sh <target-dir> [work-dir]}"
work="${2:-${target%/}.work}"

names="${here}/names.yaml"
rewrites="${here}/commit-rewrites.yaml"
tagmap="${here}/tag-map.txt"
sources="${here}/import-sources.txt"

PY=(uv run --no-project --quiet --with pyyaml==6.0.3 --with git-filter-repo==2.47.0 python "${here}/import_helper.py")

export GIT_AUTHOR_NAME="Claude" GIT_AUTHOR_EMAIL="noreply@anthropic.com"
export GIT_COMMITTER_NAME="Claude" GIT_COMMITTER_EMAIL="noreply@anthropic.com"
# Make git behave the same regardless of the caller's config.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

log() { printf '[import] %s\n' "$*" >&2; }
# git clone with retries (transient network errors); removes partial clones between tries.
clone() {
  local url=$1 dest=$2 i; shift 2
  for i in 1 2 3; do
    git clone -q "$@" "${url}" "${dest}" && return 0
    rm -rf "${dest}"; log "clone of ${url} failed (try ${i}), retrying"; sleep 5
  done
  return 1
}

# --- target -----------------------------------------------------------------
mkdir -p "${target}"
target="$(cd "${target}" && pwd)"
if [[ -d "${target}/.git" ]]; then
  if git -C "${target}" rev-parse -q --verify HEAD >/dev/null; then
    echo "target ${target} already has commits; refusing (import runs from scratch)" >&2; exit 1
  fi
  if [[ -n "$(ls -A "${target}" | grep -v '^\.git$' || true)" ]]; then
    echo "target ${target} has files besides .git; refusing" >&2; exit 1
  fi
else
  if [[ -n "$(ls -A "${target}")" ]]; then
    echo "target ${target} is not empty; refusing" >&2; exit 1
  fi
  git -C "${target}" init -q -b main
fi
git -C "${target}" symbolic-ref HEAD refs/heads/main
# Symlinks must be created as symlinks (relevant on Windows / core.symlinks=false).
git -C "${target}" config core.symlinks true

# --- work dir ---------------------------------------------------------------
rm -rf "${work}"
mkdir -p "${work}/clones" "${work}/stats"
work="$(cd "${work}" && pwd)"

mapfile -t name_lines < <("${PY[@]}" names "${names}")

org=""; pkgs=(); symlinks=(); submodules=(); datas=()
for line in "${name_lines[@]}"; do
  IFS=$'\t' read -r kind a b c <<<"${line}"
  case "${kind}" in
    org) org="${a}" ;;
    pkg) pkgs+=("${a}"$'\t'"${b}"$'\t'"${c}") ;;
    symlink) symlinks+=("${a}"$'\t'"${b}"$'\t'"${c}") ;;
    submodule) submodules+=("${a}"$'\t'"${b}") ;;
    data) datas+=("${a}"$'\t'"${b}"$'\t'"${c}") ;;
  esac
done

# --- fresh clones -----------------------------------------------------------
: >"${sources}.tmp"
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r repo dir prefix <<<"${p}"
  log "clone ${org}/${repo}"
  clone "https://github.com/${org}/${repo}.git" "${work}/clones/${repo}"
  printf 'package\t%s/%s\t%s\n' "${org}" "${repo}" "$(git -C "${work}/clones/${repo}" rev-parse HEAD)" >>"${sources}.tmp"
done
for d in "${datas[@]}"; do
  IFS=$'\t' read -r ddir repo ref <<<"${d}"
  log "clone ${org}/${repo} (${ref})"
  clone "https://github.com/${org}/${repo}.git" "${work}/clones/${repo}" --branch "${ref}"
  printf 'data\t%s/%s\t%s\n' "${org}" "${repo}" "$(git -C "${work}/clones/${repo}" rev-parse HEAD)" >>"${sources}.tmp"
done

# Fixed date for the commits created here: newest committer date of any upstream HEAD.
fixed_date="$(for c in "${work}"/clones/*; do git -C "${c}" log -1 --format=%ct HEAD; done | sort -n | tail -1)"
export GIT_AUTHOR_DATE="@${fixed_date} +0000" GIT_COMMITTER_DATE="@${fixed_date} +0000"

# --- original tags (before rewriting) ---------------------------------------
: >"${tagmap}.tmp"
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r repo dir prefix <<<"${p}"
  git -C "${work}/clones/${repo}" for-each-ref refs/tags \
    --format="%(refname:strip=2)%09%(objecttype)%09%(*objectname)%(if:equals=commit)%(objecttype)%(then)%(objectname)%(end)" \
    | while IFS=$'\t' read -r tag type commit; do
        printf '%s\t%s\t%s\t%s\n' "${repo}" "${tag}" "${type}" "${commit}"
      done >>"${work}/orig-tags.tsv"
done

# --- initial commit ---------------------------------------------------------
git -C "${target}" commit -q --allow-empty -m "chore: initialize Neurobagel monorepo"

# --- per package: filter and merge ------------------------------------------
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r repo dir prefix <<<"${p}"
  clone="${work}/clones/${repo}"
  head_before="$(git -C "${clone}" rev-parse HEAD)"
  log "filter ${repo} -> packages/${dir}, tags ${prefix}-*"
  "${PY[@]}" filter "${clone}" "${org}" "${repo}" "${dir}" "${prefix}" "${rewrites}" "${work}/stats/${repo}.json"
  # filter-repo maps old -> new commits; record the new commit of every original tag.
  map="${clone}/.git/filter-repo/commit-map"
  awk -F'\t' -v r="${repo}" '$1==r' "${work}/orig-tags.tsv" | while IFS=$'\t' read -r _ tag type commit; do
    new_commit="$(awk -v o="${commit}" '$1==o {print $2}' "${map}")"
    new_tag_commit="$(git -C "${clone}" rev-parse "refs/tags/${prefix}-${tag}^{commit}")"
    if [[ "${new_commit}" != "${new_tag_commit}" ]]; then
      echo "tag map mismatch for ${repo} ${tag}: ${new_commit} vs ${new_tag_commit}" >&2; exit 1
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${repo}" "${tag}" "${commit}" "${prefix}-${tag}" "${new_tag_commit}" "${type}"
  done >>"${tagmap}.tmp"
  new_head="$(awk -v o="${head_before}" '$1==o {print $2}' "${map}")"

  git -C "${target}" fetch -q --no-tags "${clone}" "${new_head}"
  git -C "${target}" fetch -q "${clone}" "refs/tags/*:refs/tags/*"
  git -C "${target}" merge -q --no-ff --allow-unrelated-histories --no-edit \
    -m "chore: import ${org}/${repo} history into packages/${dir}" "${new_head}"
done

# --- shared data (plain files) ----------------------------------------------
for d in "${datas[@]}"; do
  IFS=$'\t' read -r ddir repo ref <<<"${d}"
  src="${work}/clones/${repo}"
  sha="$(git -C "${src}" rev-parse HEAD)"
  log "copy ${org}/${repo}@${sha:0:7} -> ${ddir}/"
  mkdir -p "${target}/${ddir}"
  git -C "${src}" archive --format=tar HEAD | tar -x -C "${target}/${ddir}"
  git -C "${target}" add -- "${ddir}"
  git -C "${target}" commit -q -m "chore: add ${ddir}/ from ${org}/${repo}@${sha}" \
    -m "Plain copy of ${org}/${repo} at ${ref} (${sha}), without history. It replaces the ${repo} submodules of the packages."
done

# --- replace gitlinks with symlinks -----------------------------------------
for s in "${symlinks[@]}"; do
  IFS=$'\t' read -r dir sub ddir <<<"${s}"
  path="packages/${dir}/${sub}"
  mode="$(git -C "${target}" ls-files -s -- "${path}" | awk '{print $1}')"
  if [[ "${mode}" != "160000" ]]; then
    echo "${path} is not a gitlink (mode '${mode}')" >&2; exit 1
  fi
  git -C "${target}" rm -q --cached -- "${path}"
  rm -rf "${target:?}/${path}"
  link="$("${PY[@]}" relpath "$(dirname "${path}")" "${ddir}")"
  ln -s "${link}" "${target}/${path}"
  git -C "${target}" add -- "${path}"
  log "symlink ${path} -> ${link}"
done

# --- root .gitmodules for the kept submodules -------------------------------
: >"${target}/.gitmodules"
for s in "${submodules[@]}"; do
  IFS=$'\t' read -r dir sub <<<"${s}"
  path="packages/${dir}/${sub}"
  mode="$(git -C "${target}" ls-files -s -- "${path}" | awk '{print $1}')"
  if [[ "${mode}" != "160000" ]]; then
    echo "${path} is not a gitlink (mode '${mode}')" >&2; exit 1
  fi
  # URL from the package's own .gitmodules (kept there as dead code).
  pkg_gm="${target}/packages/${dir}/.gitmodules"
  name="$(git config -f "${pkg_gm}" --get-regexp '^submodule\..*\.path$' | awk -v p="${sub}" '$2==p {print $1}' | sed -e 's/^submodule\.//' -e 's/\.path$//')"
  url="$(git config -f "${pkg_gm}" --get "submodule.${name}.url")"
  git config -f "${target}/.gitmodules" "submodule.${path}.path" "${path}"
  git config -f "${target}/.gitmodules" "submodule.${path}.url" "${url}"
done
git -C "${target}" add .gitmodules
git -C "${target}" commit -q -m "chore: replace shared-data submodules with symlinks, declare kept submodules at the root" \
  -m "Gitlinks replaced by relative symlinks to deploy/ and testdata/; the bagel-cli data submodules stay submodules at their upstream pins and are declared in the root .gitmodules. Package .gitmodules files are kept unchanged as dead code."

# --- outputs ----------------------------------------------------------------
{
  printf '# Generated by import.sh. Columns: repo, original tag, original commit, monorepo tag, monorepo commit, tag object type\n'
  sort "${tagmap}.tmp"
} >"${tagmap}"
rm -f "${tagmap}.tmp"
{
  printf '# Generated by import.sh. Upstream commits imported. Columns: kind, repository, commit\n'
  cat "${sources}.tmp"
} >"${sources}"
rm -f "${sources}.tmp"

# --- submodules last --------------------------------------------------------
log "initialize submodules"
git -C "${target}" -c protocol.file.allow=never submodule update --init --quiet

log "done: $(git -C "${target}" rev-list --count HEAD) commits, $(git -C "${target}" tag | wc -l) tags"
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r repo _ _ <<<"${p}"
  log "stats ${repo}: $(tr -d '\n ' <"${work}/stats/${repo}.json")"
done
