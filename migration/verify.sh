#!/usr/bin/env bash
# Verify an assembled Neurobagel monorepo against upstream.
#
# Usage: verify.sh <monorepo-dir> [work-dir]
#   VERIFY_SKIP=tests,cypress,images,readme,mirror  skip slow setup checks (development only;
#   a gate run uses no skips)
#
# Uses its own fresh (blobless, bare) clones of upstream in [work-dir]
# (default: <monorepo-dir>.verify), not the import's clones, and checks against the
# upstream commits recorded in import-sources.txt. Every check is labelled LOCAL
# (runs here) or CI (runs in GitHub Actions). Exits non-zero if any check fails.
#
# History checks (Phase 2):
#   H1 commit counts per tool (git rev-list --count)
#   H2 tags: count per tool, every tag-map.txt entry present, tree of every tag equals upstream
#   H3 tags on no branch (upstream) are present and also on no branch in the monorepo
#   H4 commit messages: no unqualified #N references left; sampled PR links point to the original repo
#   H5 commit title rewrites from commit-rewrites.yaml applied
#   H6 package trees identical to upstream at import, and at HEAD apart from the replaced gitlinks
#   H7 deploy/ and testdata/ identical to the upstream data repos
#   H8 symlinks are symlinks, point to the shared data dirs and resolve
#   H9 exactly the kept submodules are gitlinks, declared in the root .gitmodules,
#      initialized, at their upstream pins
#   H10 root layout

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${1:?usage: verify.sh <monorepo-dir> [work-dir]}" && pwd)"
work="${2:-${repo_dir%/}.verify}"
mkdir -p "${work}"
work="$(cd "${work}" && pwd)"

PY=(uv run --no-project --quiet --with pyyaml==6.0.3 --with git-filter-repo==2.47.0 python "${here}/import_helper.py")
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fails=0
pass() { printf 'PASS [%s] %s: %s\n' "$1" "$2" "$3"; }
fail() { printf 'FAIL [%s] %s: %s\n' "$1" "$2" "$3"; fails=$((fails + 1)); }
check() { # label id description expected actual
  if [[ "$4" == "$5" ]]; then pass "$1" "$2" "$3 = $4"; else fail "$1" "$2" "$3: expected '$4', got '$5'"; fi
}
g() { git -C "${repo_dir}" "$@"; }

org=""; pkgs=(); symlinks=(); submodules=(); datas=()
while IFS=$'\t' read -r kind a b c; do
  case "${kind}" in
    org) org="${a}" ;;
    pkg) pkgs+=("${a}"$'\t'"${b}"$'\t'"${c}") ;;
    symlink) symlinks+=("${a}"$'\t'"${b}"$'\t'"${c}") ;;
    submodule) submodules+=("${a}"$'\t'"${b}") ;;
    data) datas+=("${a}"$'\t'"${b}"$'\t'"${c}") ;;
  esac
done < <("${PY[@]}" names "${here}/names.yaml")

src_sha() { awk -F'\t' -v r="${org}/$1" '$2==r {print $3}' "${here}/import-sources.txt"; }

# Upstream bare clones (blobless: commits and trees only).
upstream() {
  local repo=$1 d="${work}/${1}.git"
  if [[ -d "${d}" ]]; then
    git -C "${d}" fetch -q --tags --force origin '+refs/heads/*:refs/heads/*'
  else
    git clone -q --bare --filter=blob:none "https://github.com/${org}/${repo}.git" "${d}"
  fi
  echo "${d}"
}

merge_of() { # merge commit that imported <repo>
  g log --first-parent --format=%H --grep="^chore: import ${org}/$1 history into " -n 1 HEAD
}

total_tags=0
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r repo dir prefix <<<"${p}"
  up="$(upstream "${repo}")"
  sha="$(src_sha "${repo}")"
  merge="$(merge_of "${repo}")"
  if [[ -z "${merge}" || -z "${sha}" ]]; then fail LOCAL "H0 ${repo}" "import merge or source sha not found"; continue; fi
  imported="$(g rev-parse "${merge}^2")"

  # H1 commit counts
  check LOCAL "H1 ${repo}" "commits on main" "$(git -C "${up}" rev-list --count "${sha}")" "$(g rev-list --count "${imported}")"

  # H2 tags
  up_tags="$(git -C "${up}" tag | wc -l)"
  mono_tags="$(g tag -l "${prefix}-*" | wc -l)"
  total_tags=$((total_tags + up_tags))
  check LOCAL "H2 ${repo}" "tag count" "${up_tags}" "${mono_tags}"
  bad=0; n=0
  while IFS=$'\t' read -r r otag ocommit ntag ncommit _type; do
    [[ "${r}" == "${repo}" ]] || continue
    n=$((n + 1))
    if [[ "$(g rev-parse -q --verify "refs/tags/${ntag}^{commit}")" != "${ncommit}" ]]; then
      bad=$((bad + 1)); echo "  tag ${ntag} does not point to ${ncommit}"; continue
    fi
    if [[ "$(git -C "${up}" rev-parse "refs/tags/${otag}^{tree}")" != "$(g rev-parse "${ncommit}:packages/${dir}")" ]]; then
      bad=$((bad + 1)); echo "  tag ${ntag}: tree differs from upstream ${otag}"
    fi
    if [[ "$(git -C "${up}" rev-parse "refs/tags/${otag}^{commit}")" != "${ocommit}" ]]; then
      bad=$((bad + 1)); echo "  upstream ${otag} moved since import (was ${ocommit})"
    fi
  done < <(grep -v '^#' "${here}/tag-map.txt")
  check LOCAL "H2 ${repo}" "tag-map entries checked (target + tree vs upstream), mismatches" "0 of ${up_tags}" "${bad} of ${n}"

  # H3 tags on no branch upstream
  nobranch=()
  while read -r t; do
    if [[ -z "$(git -C "${up}" branch --contains "${t}^{commit}" 2>/dev/null)" ]]; then nobranch+=("${t}"); fi
  done < <(git -C "${up}" tag)
  bad=0
  for t in "${nobranch[@]}"; do
    if ! g rev-parse -q --verify "refs/tags/${prefix}-${t}" >/dev/null; then bad=$((bad + 1)); echo "  missing ${prefix}-${t}"; continue; fi
    if g merge-base --is-ancestor "${prefix}-${t}^{commit}" HEAD; then bad=$((bad + 1)); echo "  ${prefix}-${t} is on main in the monorepo"; fi
  done
  check LOCAL "H3 ${repo}" "upstream no-branch tags (${#nobranch[@]}: ${nobranch[*]:-none}) present and off-branch, problems" "0" "${bad}"

  # H4 sampled PR links: the last 20 upstream titles with (#N) appear qualified in the monorepo
  bad=0; n=0
  while read -r num; do
    n=$((n + 1))
    if ! g log --format=%s "${imported}" | grep -F "(${org}/${repo}#${num})" >/dev/null; then bad=$((bad + 1)); echo "  no (${org}/${repo}#${num}) in imported titles"; fi
  done < <(git -C "${up}" log --format=%s -n 200 "${sha}" | grep -oE '\(#[0-9]+\)$' | tr -dc '0-9\n' | head -20)
  check LOCAL "H4 ${repo}" "sampled PR links qualified (of ${n})" "0" "${bad}"

  # H6 package tree at import == upstream tree; at HEAD only the replaced gitlinks differ
  check LOCAL "H6 ${repo}" "packages/${dir} tree at import vs upstream ${sha:0:7}" \
    "$(git -C "${up}" rev-parse "${sha}^{tree}")" "$(g rev-parse "${imported}:packages/${dir}")"
  # The gitlinks replaced by symlinks are the only changes made by the import itself.
  import_end="$(g log --first-parent --format=%H -n 1 --grep='^chore: replace shared-data submodules' HEAD)"
  expected="$(for s in "${symlinks[@]}"; do IFS=$'\t' read -r d sub _ <<<"${s}"; [[ "${d}" == "${dir}" ]] && printf 'T\tpackages/%s/%s\n' "${d}" "${sub}"; done | sort)"
  actual="$(g diff --no-renames --name-status "${imported}" "${import_end}" -- "packages/${dir}" | sort)"
  check LOCAL "H6 ${repo}" "changes in packages/${dir} made by the import" "$(echo "${expected:-<none>}" | tr '\n\t' '; ')" "$(echo "${actual:-<none>}" | tr '\n\t' '; ')"
done

check LOCAL "H2 all" "total tags (sum of upstream tags)" "${total_tags}" "$(g tag | wc -l)"

# H4 no unqualified GitHub references in any commit message
unq="$(g log --format=%B HEAD | grep -cP '(?<![\w/.&-])#\d+\b' || true)"
check LOCAL "H4 all" "message lines with unqualified #N references" "0" "${unq}"

# H5 commit title rewrites applied
h5="$(cd "${repo_dir}" && uv run --no-project --quiet --with pyyaml==6.0.3 python - "${here}/commit-rewrites.yaml" "${org}" <<'EOF'
import re, subprocess, sys, yaml
data = yaml.safe_load(open(sys.argv[1])) or {}
org = sys.argv[2]
subjects = set(subprocess.run(["git", "log", "--format=%s", "HEAD"], capture_output=True, text=True, check=True).stdout.splitlines())
ref = re.compile(r"(?<![\w/.&-])#(\d+)\b")
total = missing = unresolved = 0
for repo, entry in data.items():
    for c in entry.get("commits") or []:
        if not c.get("new"):
            unresolved += 1
            continue
        total += 1
        want = ref.sub(f"{org}/{repo}#\\1", c["new"])
        if want not in subjects:
            missing += 1
            print(f"  missing: {want}", file=sys.stderr)
print(f"{total} {missing} {unresolved}")
EOF
)"
read -r h5_total h5_missing h5_unresolved <<<"${h5}"
check LOCAL "H5" "rewritten titles missing (of ${h5_total})" "0" "${h5_missing}"
check LOCAL "H5" "unresolved entries in commit-rewrites.yaml" "0" "${h5_unresolved}"

# H7 shared data
for d in "${datas[@]}"; do
  IFS=$'\t' read -r ddir repo ref <<<"${d}"
  up="$(upstream "${repo}")"
  sha="$(src_sha "${repo}")"
  check LOCAL "H7 ${ddir}" "tree vs ${org}/${repo}@${sha:0:7}" "$(git -C "${up}" rev-parse "${sha}^{tree}")" "$(g rev-parse "HEAD:${ddir}")"
done

# H8 symlinks
for s in "${symlinks[@]}"; do
  IFS=$'\t' read -r dir sub ddir <<<"${s}"
  path="packages/${dir}/${sub}"
  want="$("${PY[@]}" relpath "$(dirname "${path}")" "${ddir}")"
  mode="$(g ls-files -s -- "${path}" | awk '{print $1}')"
  target="$(g cat-file -p "HEAD:${path}" 2>/dev/null)"
  resolves="no"; [[ -d "${repo_dir}/${path}/" && "$(cd "${repo_dir}/${path}/" && pwd -P)" == "${repo_dir}/${ddir}" ]] && resolves="yes"
  check LOCAL "H8 ${path}" "mode, target, resolves" "120000 ${want} yes" "${mode} ${target} ${resolves}"
done

# H9 submodules
bagel_sha=""
expected_links=""
for s in "${submodules[@]}"; do
  IFS=$'\t' read -r dir sub <<<"${s}"
  repo="$(for p in "${pkgs[@]}"; do IFS=$'\t' read -r r d _ <<<"${p}"; [[ "${d}" == "${dir}" ]] && echo "${r}"; done)"
  up="${work}/${repo}.git"
  pin="$(git -C "${up}" ls-tree "$(src_sha "${repo}")" -- "${sub}" | awk '{print $3}')"
  path="packages/${dir}/${sub}"
  expected_links+="${path}"$'\n'
  status="$(g submodule status -- "${path}" 2>&1)"
  state="${status:0:1}"; [[ "${state}" == " " ]] && state="ok"
  check LOCAL "H9 ${path}" "pin, initialized, declared" "${pin} ok ${path}" \
    "$(g ls-tree HEAD -- "${path}" | awk '{print $3}') ${state} $(git config -f "${repo_dir}/.gitmodules" --get "submodule.${path}.path")"
done
check LOCAL "H9 all" "gitlinks in the tree" "$(printf '%s' "${expected_links}" | sort | tr '\n' ' ')" \
  "$(g ls-files -s | awk '$1=="160000" {print $4}' | sort | tr '\n' ' ')"

# H10 root layout
import_end="$(g log --first-parent --format=%H -n 1 --grep='^chore: replace shared-data submodules' HEAD)"
check LOCAL "H10" "root entries after the import" ".gitmodules deploy packages testdata " "$(g ls-tree --name-only "${import_end}" | sort | tr '\n' ' ')"
check LOCAL "H10" "packages/" "$(for p in "${pkgs[@]}"; do IFS=$'\t' read -r _ d _ <<<"${p}"; echo "${d}"; done | sort | tr '\n' ' ')" \
  "$(g ls-tree --name-only "${import_end}" packages/ | sed 's#packages/##' | sort | tr '\n' ' ')"

# Monorepo setup checks (Phase 3): only once the setup patches are applied.
if g cat-file -e HEAD:release-please-config.json 2>/dev/null; then
  source "${here}/verify-setup.sh"
else
  echo "SKIP [LOCAL] setup checks: no release-please-config.json (history only)"
fi

echo
if [[ ${fails} -eq 0 ]]; then echo "verify: all checks passed"; else echo "verify: ${fails} check(s) failed"; fi
exit $((fails > 0))
