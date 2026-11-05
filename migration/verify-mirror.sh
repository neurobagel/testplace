# S11: local mirror round trip (sourced by verify-setup.sh). tools/mirror.py runs against
# local bare copies of the seven old repositories, set to the imported upstream commits, from
# a scratch clone of the assembled monorepo. GitHub is replaced by --assume-locked and
# --assume-green (pull requests, check waiting, statuses and issues are checked on GitHub in
# Phase 4). Checks, in order:
#   unlocked (before switchover): branches only, old main and tags untouched
#   the mirrored folders differ from old main only by allowlisted migration edits
#   locked and green but without --allow-merge (MIRROR_MERGE unset): still nothing on main
#   locked, green and --allow-merge: old main fast-forwarded to the branch
#   in the mirrored old repositories: hatch-vcs versions from the v* tags; pytest per Python
#   tool and vitest for annotation-tool pass with the baseline counts
#   a synthetic fix with a PR reference and a release tag, a deploy/ change and a multi-tool
#   merge give the expected commits, gitlink bump and vX.Y.Z tag; a rerun changes nothing
#   a foreign commit on an old main stops the mirror; --adopt recovers
#   a mirror branch from another build is rebuilt while unlocked, refused while locked
#   --check (the PR check) fails on a symlink leaving a package
mw="${work}/mirror"
rm -rf "${mw}"; mkdir -p "${mw}/old" "${mw}/src"
mono="${mw}/mono"
git clone -q --no-local "${repo_dir}" "${mono}"
gm() { git -C "${mono}" -c user.name=Dev -c user.email=dev@example.org "$@"; }
MIR() {
  ( cd "${mono}" && uv run --no-project --quiet --with pyyaml==6.0.3 python tools/mirror.py \
      --owner "${org}" --remote-template "${mw}/old/{repo}.git" --monorepo "${org}/neurobagel" "$@" )
}
go() { git -C "${mw}/old/$1.git" "${@:2}"; }

old_repos=(); declare -A folder_of
for d in "${datas[@]}"; do IFS=$'\t' read -r dir repo _ <<<"${d}"; old_repos+=("${repo}"); folder_of[${repo}]="${dir}"; done
for p in "${pkgs[@]}"; do IFS=$'\t' read -r repo dir _ <<<"${p}"; old_repos+=("${repo}"); folder_of[${repo}]="packages/${dir}"; done

for repo in "${old_repos[@]}"; do
  [[ -d "${work}/mirror-src/${repo}.git" ]] || git clone -q --bare "https://github.com/${org}/${repo}.git" "${work}/mirror-src/${repo}.git"
  git clone -q --bare "${work}/mirror-src/${repo}.git" "${mw}/old/${repo}.git"
  go "${repo}" update-ref refs/heads/main "$(src_sha "${repo}")"
  go "${repo}" for-each-ref --format='%(refname)' refs/heads | grep -v '^refs/heads/main$' | xargs -r -n1 git -C "${mw}/old/${repo}.git" update-ref -d
done
tags_before="$(for r in "${old_repos[@]}"; do go "${r}" tag | sed "s#^#${r} #"; done | sort | md5sum)"

# --- before switchover -------------------------------------------------------------------
MIR >"${mw}/run-unlocked.log" 2>&1; rc=$?
check LOCAL "S11" "unlocked run exit" "0" "${rc}"
n_main=0; n_branch=0
for r in "${old_repos[@]}"; do
  [[ "$(go "${r}" rev-parse main)" == "$(src_sha "${r}")" ]] && n_main=$((n_main + 1))
  go "${r}" rev-parse -q --verify refs/heads/monorepo-mirror >/dev/null && n_branch=$((n_branch + 1))
done
check LOCAL "S11" "unlocked: old main untouched / mirror branch present (of ${#old_repos[@]})" "${#old_repos[@]} ${#old_repos[@]}" "${n_main} ${n_branch}"
check LOCAL "S11" "unlocked: old tags untouched" "${tags_before}" "$(for r in "${old_repos[@]}"; do go "${r}" tag | sed "s#^#${r} #"; done | sort | md5sum)"

# Every change between the imported old main and the mirror branch is an allowlisted edit.
mapfile -t allowed < <(grep -v '^\s*#' "${here}/allowed-changes.txt" | grep -v '^\s*$' | cut -f1)
bad=()
for r in "${old_repos[@]}"; do
  f="${folder_of[${r}]}"
  while IFS= read -r path; do
    [[ " ${allowed[*]} " == *" ${f}/${path} "* ]] || bad+=("${r}:${path}")
  done < <(go "${r}" diff --name-only "$(src_sha "${r}")" monorepo-mirror)
done
check LOCAL "S11" "mirrored folders differ from old main only by allowlisted edits (unexpected paths)" "" "${bad[*]}"

# --- locked but MIRROR_MERGE not set: still nothing on main, no tags ---------------------------
MIR --assume-locked --assume-green >"${mw}/run-locked-no-merge.log" 2>&1; rc=$?
n_main=0; for r in "${old_repos[@]}"; do [[ "$(go "${r}" rev-parse main)" == "$(src_sha "${r}")" ]] && n_main=$((n_main + 1)); done
check LOCAL "S11" "locked, without --allow-merge (MIRROR_MERGE unset): exit, old main untouched, tags untouched" \
  "0 ${#old_repos[@]} ${tags_before}" "${rc} ${n_main} $(for r in "${old_repos[@]}"; do go "${r}" tag | sed "s#^#${r} #"; done | sort | md5sum)"

# --- after switchover ---------------------------------------------------------------------
MIR --allow-merge --assume-locked --assume-green >"${mw}/run-locked.log" 2>&1; rc=$?
n_ff=0
for r in "${old_repos[@]}"; do [[ "$(go "${r}" rev-parse main)" == "$(go "${r}" rev-parse monorepo-mirror)" ]] && n_ff=$((n_ff + 1)); done
check LOCAL "S11" "locked: exit, old main fast-forwarded to the branch (of ${#old_repos[@]})" "0 ${#old_repos[@]}" "${rc} ${n_ff}"

# The mirrored old repositories work as old repositories.
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r repo dir _ <<<"${p}"
  oc="${mw}/checkout-${repo}"
  git clone -q "${mw}/old/${repo}.git" "${oc}"
  if [[ " ${py_pkgs[*]} " == *" ${dir} "* ]]; then
    desc="$(git -C "${oc}" describe --tags --long --match 'v*')"
    tag="${desc%-*-g*}"; n="${desc%-g*}"; n="${n##*-}"; v="${tag#v}"
    if [[ "${n}" == 0 ]]; then want="${v}"; else want="${v%.*}.$(( ${v##*.} + 1 )).dev${n}"; fi
    got="$(cd "${oc}" && uvx -q --with hatch-vcs hatchling version 2>&1 | tail -1)"
    check LOCAL "S11 ${repo}" "hatch-vcs version in the mirrored old repo (from ${tag})" "${want}" "${got}"
    log="${mw}/pytest-${repo}.log"
    ( cd "${oc}" && git submodule -q update --init --recursive \
        && export UV_PROJECT_ENVIRONMENT="${mw}/venv-${repo}" \
        && uv sync -q --python 3.12 --group dev \
        && eval "uv run --no-sync --python 3.12 pytest ${PYTEST_ARGS[${dir}]} -p no:cacheprovider" ) >"${log}" 2>&1
    rc=$?; passed="$(tail -1 "${log}" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')"
    check LOCAL "S11 ${repo}" "pytest 3.12 in the mirrored old repo: exit and passed" "0 ${BASELINE_PYTEST[${dir}]}" "${rc} ${passed:-0}"
  elif [[ "${dir}" == annotation-tool ]]; then
    relabel "${mw}"
    log="${mw}/vitest-${repo}.log"
    docker run --rm --network=host -v "${mw}:${mw}" -w "${oc}" --entrypoint bash "${CYPRESS_IMAGE}" \
      -eo pipefail -c 'npm ci --no-audit --no-fund >/dev/null && npm run test:unit' >"${log}" 2>&1
    rc=$?; passed="$(sed 's/\x1b\[[0-9;]*m//g' "${log}" | grep -E '^\s+Tests\s' | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')"
    check LOCAL "S11 ${repo}" "vitest in the mirrored old repo: exit and passed" "0 ${BASELINE_VITEST}" "${rc} ${passed:-0}"
  fi
done

# --- synthetic monorepo changes ---------------------------------------------------------------
declare -A tip_before
for r in "${old_repos[@]}"; do tip_before[${r}]="$(go "${r}" rev-parse main)"; done
echo "<!-- mirror test -->" >>"${mono}/packages/api/README.md"
gm commit -qam "fix(api): a mirror test fix (#12)"; fix="$(gm rev-parse HEAD)"; gm tag api-v99.0.0
echo "# mirror test" >>"${mono}/deploy/README.md"
gm commit -qam "fix: a deploy/ change"
gm checkout -q -b side
echo "<!-- mirror test -->" >>"${mono}/packages/federation-api/README.md"; gm commit -qam "fix(federation-api): f"
echo "<!-- mirror test -->" >>"${mono}/packages/query-tool/README.md"; gm commit -qam "fix(query-tool): q"
gm checkout -q main; gm merge -q --no-ff side -m "Merge pull request #13 from example/side"
MIR --allow-merge --assume-locked --assume-green >"${mw}/run-synthetic.log" 2>&1; rc=$?
counts=""
for r in "${old_repos[@]}"; do counts+="${r}=$(go "${r}" rev-list --count "${tip_before[${r}]}..main") "; done
check LOCAL "S11" "synthetic changes: exit and new commits per old repo" \
  "0 recipes=1 neurobagel_examples=0 api=2 federation-api=1 annotation-tool=0 bagel-cli=0 query-tool=2 " "${rc} ${counts}"
check LOCAL "S11" "api tag v99.0.0 on the mirrored fix, PR reference qualified" \
  "fix(api): a mirror test fix (${org}/neurobagel#12) | ${fix}" \
  "$(go api log -1 --format='%s | %(trailers:key=Monorepo-Commit,valueonly)' v99.0.0 2>&1 | sed "s#${org}/neurobagel@##")"
check LOCAL "S11" "api and query-tool gitlink recipes = recipes main" \
  "$(go recipes rev-parse main) $(go recipes rev-parse main)" \
  "$(go api ls-tree main recipes | awk '{print $3}') $(go query-tool ls-tree main recipes | awk '{print $3}')"
declare -A tip_after
for r in "${old_repos[@]}"; do tip_after[${r}]="$(go "${r}" rev-parse main)"; done
MIR --allow-merge --assume-locked --assume-green >"${mw}/run-rerun.log" 2>&1; rc=$?
same=0; for r in "${old_repos[@]}"; do [[ "$(go "${r}" rev-parse main)" == "${tip_after[${r}]}" ]] && same=$((same + 1)); done
check LOCAL "S11" "rerun: exit, old repos unchanged" "0 ${#old_repos[@]}" "${rc} ${same}"

# --- a foreign commit on an old main ------------------------------------------------------------
fc="${mw}/foreign"; git clone -q "${mw}/old/api.git" "${fc}"
echo "foreign" >>"${fc}/README.md"
git -C "${fc}" -c user.name=X -c user.email=x@example.org commit -qam "a direct write"
git -C "${fc}" push -q origin HEAD:main; foreign="$(git -C "${fc}" rev-parse HEAD)"
echo "<!-- mirror test 2 -->" >>"${mono}/packages/api/README.md"; gm commit -qam "fix(api): after a foreign write"
MIR --allow-merge --assume-locked --assume-green >"${mw}/run-foreign.log" 2>&1; rc=$?
check LOCAL "S11" "foreign commit on old main: mirror fails, main unchanged" "1 ${foreign}" "$(( rc != 0 )) $(go api rev-parse main)"
MIR --allow-merge --assume-locked --assume-green --adopt "api=${foreign}" >"${mw}/run-adopt.log" 2>&1; rc=$?
check LOCAL "S11" "adopt: exit, main fast-forwarded over the foreign commit" "0 yes" \
  "${rc} $(go api merge-base --is-ancestor "${foreign}" main && [[ "$(go api rev-parse main)" == "$(go api rev-parse monorepo-mirror)" ]] && echo yes)"

# --- a mirror branch from another build ----------------------------------------------------------
stray="$(go api commit-tree -p "$(src_sha api)" -m "x

Monorepo-Commit: ${org}/neurobagel@0000000000000000000000000000000000000000" "$(src_sha api)^{tree}")"
go api update-ref refs/heads/monorepo-mirror "${stray}"
MIR --dry-run >"${mw}/run-rebuild.log" 2>&1; rc=$?
check LOCAL "S11" "branch from another build, unlocked: rebuilt (dry run)" "0 1" "${rc} $(grep -c 'belongs to an earlier build' "${mw}/run-rebuild.log")"
MIR --dry-run --allow-merge --assume-locked >"${mw}/run-rebuild-locked.log" 2>&1; rc=$?
check LOCAL "S11" "branch from another build, locked: refused" "1 1" "$(( rc != 0 )) $(grep -c 'does not continue' "${mw}/run-rebuild-locked.log")"

# --- the PR check ---------------------------------------------------------------------------------
( cd "${mono}" && uv run --no-project --quiet --with pyyaml==6.0.3 python tools/mirror.py --check HEAD ) >/dev/null 2>&1
check LOCAL "S11" "mirror check passes on the monorepo (exit)" "0" "$?"
ln -s ../../README.md "${mono}/packages/api/stray-link"; gm add packages/api/stray-link; gm commit -qm "chore: a stray symlink"
( cd "${mono}" && uv run --no-project --quiet --with pyyaml==6.0.3 python tools/mirror.py --check HEAD ) >/dev/null 2>&1
check LOCAL "S11" "mirror check fails on a symlink leaving a package (exit != 0)" "1" "$(( $? != 0 ))"
note_ci "S11" "on GitHub (Phase 4): draft mirror PRs in the old repos, old CI green on them, mirror/<repo> statuses, issue on red old CI"
