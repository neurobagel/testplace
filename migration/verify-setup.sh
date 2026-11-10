# Monorepo setup checks (Phase 3). Sourced by verify.sh, which provides: repo_dir, work,
# here, org, pkgs, symlinks, submodules, datas, g(), check(), pass(), fail(), upstream(),
# src_sha(), merge_of().
#
# Checks (S = setup), labelled LOCAL (run here) or CI (listed, verified on GitHub):
#   S1  check-unchanged.sh passes (a local migration check, not in CI); mirror workflow and
#       mirror-check PR job present
#   S2  release-please config and manifest (components, paths, versions = last tags,
#       bootstrap-sha), GitHub Releases on, release outputs wired to publishing, no
#       custom workflow scripts, no literal override marker in docs/templates, actionlint
#   S3  fresh clone with submodules; uv sync per Python package; npm ci per frontend
#   S4  pre-commit run --all-files passes without changing files
#   S5  pytest counts equal the baseline (per Python version); frontend counts in S10
#   S6  Python package versions come from the package's tags
#   S7  bagel wheel and sdist contents equal upstream's (communities, pipeline-catalog)
#   S8  images build from a clean checkout; file listings equal upstream images
#   S9  deliberate failures: every guard fires
#   S10 README "Working in the monorepo" commands run word for word in a fresh clone;
#       the frontend blocks run the full test suites: vitest and Cypress counts = baseline
#   S11 local mirror round trip into copies of the old repositories (verify-mirror.sh)

skip_has() { [[ ",${VERIFY_SKIP:-}," == *",$1,"* ]]; }
skipped() { printf 'SKIP [%s] %s: %s (VERIFY_SKIP)\n' "$1" "$2" "$3"; fails=$((fails + 1)); }
note_ci() { printf 'CI   %s: %s\n' "$1" "$2"; }
relabel() { command -v chcon >/dev/null && chcon -R -u system_u -l s0 "$1" 2>/dev/null || true; }

# Baseline (migration/baseline.md), per Python version of the shared matrix.
declare -A BASELINE_PYTEST=([api]=184 [federation-api]=111 [bagel-cli]=216)
declare -A PYTEST_ARGS=([api]='-m "not integration"' [federation-api]='' [bagel-cli]='-m "integration or not integration"')
PYTHONS=(3.12 3.13)
declare -A BASELINE_CY=([annotation-tool:e2e]=24 [annotation-tool:component]=185 [query-tool:component]=91 [query-tool:e2e]=41)
BASELINE_VITEST=263
CYPRESS_IMAGE=docker.io/cypress/included:15.21.1

py_pkgs=(); node_pkgs=()
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r _ dir _ <<<"${p}"
  if g cat-file -e "HEAD:packages/${dir}/pyproject.toml" 2>/dev/null; then py_pkgs+=("${dir}"); else node_pkgs+=("${dir}"); fi
done

# --- S1 check-unchanged ---------------------------------------------------------------
out="$(cd "${repo_dir}" && migration/check-unchanged.sh 2>&1)"; rc=$?
check LOCAL "S1" "check-unchanged.sh exit ($(tail -1 <<<"${out}"))" "0" "${rc}"
check LOCAL "S1" "check-unchanged not in CI (no workflow runs it)" "0" "$(g grep -c check-unchanged HEAD -- .github/workflows | wc -l)"
check LOCAL "S1" "mirror workflow and mirror-check PR job present" "yes yes" "$(g cat-file -e HEAD:.github/workflows/mirror.yml 2>/dev/null && echo yes) $(g show HEAD:.github/workflows/pr-checks.yml | grep -q "tools/mirror.py --check" && echo yes)"

# --- S2 release configuration -----------------------------------------------------------
s2="$(cd "${repo_dir}" && uv run --no-project --quiet --with pyyaml==6.0.3 python - "${here}/names.yaml" <<'PY'
import json, subprocess, sys, yaml
names = yaml.safe_load(open(sys.argv[1]))
cfg = json.load(open("release-please-config.json"))
man = json.load(open(".release-please-manifest.json"))
problems = []
want = {f"packages/{p['dir']}": p["tag_prefix"] for p in names["packages"]}
got = {path: c.get("component") for path, c in cfg["packages"].items()}
if want != got: problems.append(f"components {got} != names.yaml {want}")
for k, v in [("separate-pull-requests", False), ("bump-minor-pre-major", True), ("include-component-in-tag", True), ("tag-separator", "-"), ("include-v-in-tag", True)]:
    if cfg.get(k) != v: problems.append(f"{k}={cfg.get(k)!r}, want {v!r}")
for path, comp in want.items():
    tags = subprocess.run(["git", "tag", "-l", f"{comp}-v*", "--merged", "HEAD", "--sort=-v:refname"], capture_output=True, text=True).stdout.split()
    final = [t for t in tags if "-" not in t[len(comp) + 2:]]
    latest = final[0][len(comp) + 2:] if final else None
    if man.get(path) != latest: problems.append(f"manifest {path}={man.get(path)} != last tag {latest}")
    rt = cfg["packages"][path]["release-type"]
    is_py = subprocess.run(["git", "cat-file", "-e", f"HEAD:{path}/pyproject.toml"]).returncode == 0
    if rt != ("simple" if is_py else "node"): problems.append(f"{path} release-type {rt}")
print("; ".join(problems) or "ok")
PY
)"
check LOCAL "S2" "release-please config/manifest vs names.yaml and tags" "ok" "${s2}"
bsha="$(cd "${repo_dir}" && jq -r '."bootstrap-sha"' release-please-config.json)"
import_end="$(g log --first-parent --format=%H -n 1 --grep='^chore: replace shared-data submodules' HEAD)"
check LOCAL "S2" "bootstrap-sha is the last import commit (git cat-file -t)" "${import_end} commit" "${bsha} $(g cat-file -t "${bsha}" 2>&1)"
marker="BEGIN_COMMIT""_OVERRIDE"
hits="$(cd "${repo_dir}" && git grep -l -F "${marker}" -- '*.md' '.github/*.md' ':!packages' | tr '\n' ' ')"
check LOCAL "S2" "literal override marker in templates/docs" "" "${hits}"
if command -v actionlint >/dev/null; then
  al="$(cd "${repo_dir}" && actionlint .github/workflows/*.yml 2>&1 | grep -E '^\.github' | grep -v 'query-tool-examples-comment.yml:.*SC2046' | wc -l)"
  check LOCAL "S2" "actionlint findings (except 2 upstream SC2046 in the ported comment workflow)" "0" "${al}"
fi
rel="$(g show HEAD:.github/workflows/release.yml)"
check LOCAL "S2" "release-please creates GitHub Releases (no skip-github-release)" "0" "$(grep -c 'skip-github-release' <<<"${rel}")"
miss=""
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r _ dir _ <<<"${p}"
  grep -qF "steps.rp.outputs['packages/${dir}--release_created']" <<<"${rel}" || miss+="${dir} "
done
check LOCAL "S2" "release outputs exposed for every package" "" "${miss% }"
pub=""
for job in api-image federation-api-image query-tool-image bagel-cli annotation-tool-site query-tool-site; do
  grep -qE "^  ${job}:" <<<"${rel}" || pub+="${job} "
done
check LOCAL "S2" "publishing jobs in release.yml" "" "${pub% }"
check LOCAL "S2" "no custom workflow scripts (.github/scripts)" "" "$(g ls-tree --name-only -r HEAD .github/scripts | tr '\n' ' ')"
note_ci "S2" "release-please (bot token) opens one combined release PR; CI runs on it (Phase 4)"

# --- S3 fresh clone and installs --------------------------------------------------------
clone="${work}/clone"
rm -rf "${clone}"
git clone -q "${repo_dir}" "${clone}"
git -C "${clone}" submodule update --init -q
relabel "${clone}"
check LOCAL "S3" "fresh clone: submodules initialized" "3" "$(git -C "${clone}" submodule status | grep -c '^ ')"
for dir in "${py_pkgs[@]}"; do
  for py in "${PYTHONS[@]}"; do
    ( cd "${clone}/packages/${dir}" && UV_PROJECT_ENVIRONMENT="${work}/venvs/${dir}-${py}" uv sync -q --python "${py}" --group dev ) >"${work}/sync-${dir}-${py}.log" 2>&1
    check LOCAL "S3 ${dir}" "uv sync --python ${py} --group dev" "0" "$?"
  done
done
for dir in "${node_pkgs[@]}"; do
  ( cd "${clone}/packages/${dir}" && npm ci ) >"${work}/npmci-${dir}.log" 2>&1
  check LOCAL "S3 ${dir}" "npm ci" "0" "$?"
done
check LOCAL "S3" "husky did not take over the git hooks (core.hooksPath unset)" "" "$(git -C "${clone}" config --get core.hooksPath)"

# --- S4 pre-commit ------------------------------------------------------------------------
( cd "${clone}" && pre-commit run --all-files ) >"${work}/pre-commit.log" 2>&1
check LOCAL "S4" "pre-commit run --all-files" "0" "$?"
check LOCAL "S4" "files changed by pre-commit" "" "$(git -C "${clone}" status --porcelain --untracked-files=no | tr '\n' ' ')"
note_ci "S4" "pre-commit.ci runs the root config on PRs (app installed by a maintainer; Phase 4)"

# --- S5 test counts ---------------------------------------------------------------------
if skip_has tests; then skipped LOCAL "S5" "pytest counts"; else
  for dir in "${py_pkgs[@]}"; do
    for py in "${PYTHONS[@]}"; do
      log="${work}/pytest-${dir}-${py}.log"
      ( cd "${clone}/packages/${dir}" && eval "UV_PROJECT_ENVIRONMENT=${work}/venvs/${dir}-${py} uv run --no-sync --python ${py} pytest ${PYTEST_ARGS[${dir}]} -p no:cacheprovider" ) >"${log}" 2>&1
      rc=$?
      summary="$(tail -1 "${log}")"
      passed="$(grep -oE '[0-9]+ passed' <<<"${summary}" | grep -oE '[0-9]+')"
      check LOCAL "S5 ${dir}" "pytest ${py} exit and passed (${summary//=/})" "0 ${BASELINE_PYTEST[${dir}]}" "${rc} ${passed:-0}"
    done
  done
fi
# Frontend test counts (vitest, Cypress component and e2e) are checked in S10 from the
# README commands, which run the full frontend test suites; running them twice costs ~10 min.
note_ci "S5" "path-filtered workflows: a PR touching one package runs only its tests; a shared workflow change runs all (Phase 4)"

# --- S6 versions from tags ----------------------------------------------------------------
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r _ dir prefix <<<"${p}"
  [[ " ${py_pkgs[*]} " == *" ${dir} "* ]] || continue
  latest="$(git -C "${clone}" tag -l "${prefix}-v*" --merged HEAD --sort=-v:refname | grep -E "^${prefix}-v[0-9]+\.[0-9]+\.[0-9]+$" | head -1)"
  latest="${latest#"${prefix}"-v}"
  IFS=. read -r ma mi pa <<<"${latest}"
  v="$(cd "${clone}/packages/${dir}" && uvx --quiet --with hatch-vcs hatchling version 2>&1 | tail -1)"
  check LOCAL "S6 ${dir}" "version after last tag ${prefix}-v${latest}" "${ma}.${mi}.$((pa + 1)).dev" "${v%.dev*}.dev"
  git -C "${clone}" tag "${prefix}-v99.1.2" HEAD
  v="$(cd "${clone}/packages/${dir}" && uvx --quiet --with hatch-vcs hatchling version 2>&1 | tail -1)"
  git -C "${clone}" tag -d "${prefix}-v99.1.2" >/dev/null
  check LOCAL "S6 ${dir}" "version with a temporary ${prefix}-v99.1.2 tag on HEAD" "99.1.2" "${v}"
done

# Full upstream clones at the imported commits (for S7, S8), with submodules.
upstream_full() {
  local repo=$1 d="${work}/full-$1" sha
  sha="$(src_sha "${repo}")"
  if [[ ! -d "${d}" ]]; then
    git clone -q "https://github.com/${org}/${repo}.git" "${d}"
  fi
  git -C "${d}" checkout -q "${sha}" && git -C "${d}" submodule update --init -q --recursive
  relabel "${d}"
  echo "${d}"
}

# --- S7 bagel wheel and sdist -----------------------------------------------------------
bagel_up="$(upstream_full bagel-cli)"
list_dist() { # dir -> "wheel files" and "sdist files", versions normalized
  ( cd "$1" && rm -rf dist && uvx --quiet --from build pyproject-build --installer uv >/dev/null 2>&1 \
    && python3 -c '
import sys, tarfile, zipfile, glob, re
w = glob.glob("dist/*.whl")[0]; s = glob.glob("dist/*.tar.gz")[0]
norm = lambda n: re.sub(r"bagel-[0-9][^/]*?(\.dist-info|/|$)", r"bagel-VERSION\1", n)
wf = sorted(norm(n) for n in zipfile.ZipFile(w).namelist() if not n.endswith("RECORD"))
sf = sorted(norm(m.name) for m in tarfile.open(s).getmembers() if m.isfile())
print(len(wf), sum("bagel/communities/" in n for n in wf), sum("bagel/pipeline-catalog/" in n for n in wf), len(sf))
open("dist/wheel.txt","w").write("\n".join(wf)); open("dist/sdist.txt","w").write("\n".join(sf))
' )
}
mono_counts="$(list_dist "${clone}/packages/bagel-cli")"
up_counts="$(list_dist "${bagel_up}")"
check LOCAL "S7" "bagel wheel files, communities files, pipeline-catalog files, sdist files" "${up_counts}" "${mono_counts}"
d="$(diff <(cat "${bagel_up}/dist/wheel.txt") <(cat "${clone}/packages/bagel-cli/dist/wheel.txt") | grep -c '^[<>]')"
check LOCAL "S7" "bagel wheel file list differences vs upstream" "0" "${d}"
d="$(diff <(cat "${bagel_up}/dist/sdist.txt") <(cat "${clone}/packages/bagel-cli/dist/sdist.txt") | grep '^[<>]' | grep -v -E 'bagel-VERSION/(\.gitmodules|\.git)$' | wc -l)"
check LOCAL "S7" "bagel sdist file list differences vs upstream" "0" "${d}"
rm -rf "${clone}/packages/bagel-cli/dist" "${bagel_up}/dist"

# --- S8 images ------------------------------------------------------------------------------
if skip_has images; then skipped LOCAL "S8" "image builds and file listings"; else
  # Images are built from a pristine clone: earlier checks leave __pycache__ and
  # _version.py in ${clone}, and api/federation-api have no .dockerignore.
  iclone="${work}/clone-images"
  rm -rf "${iclone}"
  git clone -q "${repo_dir}" "${iclone}"
  git -C "${iclone}" submodule update --init -q
  # As docker-build.yml does: replace the packages' symlinks with copies of their targets.
  ( cd "${iclone}" && git ls-files -s packages | awk '$1=="120000" {print $4}' | while read -r link; do
      target="$(readlink -f "${link}")"; rm "${link}"; cp -R "${target}" "${link}"; done )
  # file listing of an image: every path in its filesystem, with symlink targets
  listing() { local c; c="$(docker create "$1")"; docker export "${c}" | tar -tv | awk '{$1=$2=$3=$4=$5=""; print}' | sed 's/^ *//' | sort; docker rm -f "${c}" >/dev/null; }
  build_list() { # name context dockerfile out [build-arg]
    local args=(-q -t "verify/$1" -f "$2/$3" "$2"); [[ -n "${5:-}" ]] && args=(--build-arg "$5" "${args[@]}")
    docker build "${args[@]}" >"${work}/build-$1.log" 2>&1 || { echo BUILD-FAILED; return; }
    listing "verify/$1" >"$4"
  }
  for spec in "api:api:Dockerfile" "federation-api:federation-api:Dockerfile" "query-tool:query-tool:Dockerfile" "bagel-cli:bagel-cli:Dockerfile" "bagel-cli-nightly:bagel-cli:Dockerfile.nightly"; do
    IFS=: read -r name repo dockerfile <<<"${spec}"
    up="$(upstream_full "${repo}")"
    git -C "${up}" clean -q -fdx && git -C "${up}" submodule foreach -q --recursive git clean -q -fdx
    arg=""
    if [[ ${name} == bagel-cli-nightly ]]; then
      arg="SETUPTOOLS_SCM_PRETEND_VERSION=$(cd "${clone}/packages/bagel-cli" && uvx --quiet --with hatch-vcs hatchling version)"
    fi
    build_list "up-${name}" "${up}" "${dockerfile}" "${work}/image-up-${name}.txt"
    build_list "mono-${name}" "${iclone}/packages/${repo}" "${dockerfile}" "${work}/image-mono-${name}.txt" "${arg}"
    # Expected differences, normalized away:
    #  - bagel nightly: upstream copies its .git into /app (the monorepo package folder has
    #    none) and the dev version differs (distance to the tag).
    norm() { sed -E -e 's#(bagel-)[0-9][^/ ]*(\.dist-info)#\1VERSION\2#g' "$1" | grep -v -E '^app/\.git(/| |$)'; }
    nd="$(diff <(norm "${work}/image-up-${name}.txt") <(norm "${work}/image-mono-${name}.txt") | grep -c '^[<>]')"
    check LOCAL "S8 ${name}" "image builds; file listing differences vs upstream image ($(wc -l <"${work}/image-mono-${name}.txt") entries)" "0" "${nd}"
  done
  note_ci "S8" "images-validation.yml pushes every image to ghcr with a validation tag; nightly builds only changed packages (Phase 4)"
fi

# --- S9 deliberate failures -------------------------------------------------------------------
scratch="${work}/guards"
rm -rf "${scratch}"; git clone -q "${repo_dir}" "${scratch}"
gs() { git -C "${scratch}" -c user.name=verify -c user.email=verify@example.org "$@"; }
base="$(gs rev-parse HEAD)"
# check-unchanged: a protected package file changes
echo "# changed" >>"${scratch}/packages/api/app/main.py"
gs commit -qam "fix(api): touch a protected file"
( cd "${scratch}" && migration/check-unchanged.sh >/dev/null 2>&1 ); check LOCAL "S9" "check-unchanged fails on a changed protected file (exit)" "1" "$?"
gs reset -q --hard "${base}"
# dependabot schema check
printf 'version: 2\nupdates:\n  - package-ecosystem: "npm"\n    schedule: {interval: "sometimes"}\n' >"${scratch}/.github/dependabot.yml"
( cd "${scratch}" && pre-commit run check-dependabot --files .github/dependabot.yml >/dev/null 2>&1 ); check LOCAL "S9" "check-dependabot fails on an invalid config (exit != 0)" "1" "$(( $? != 0 ))"
gs checkout -q -- .github/dependabot.yml
# codespell on a frontend (moved from the frontend CI into pre-commit)
echo "// teh" >>"${scratch}/packages/query-tool/src/main.tsx"
( cd "${scratch}" && pre-commit run codespell-query-tool --files packages/query-tool/src/main.tsx >/dev/null 2>&1 ); check LOCAL "S9" "codespell hook fails on a frontend typo (exit != 0)" "1" "$(( $? != 0 ))"
gs checkout -q -- packages/query-tool/src/main.tsx
note_ci "S9" "on GitHub: PR title check rejects a non-conventional title; release preview shows per-tool entries (Phase 4)"

# --- S10 README commands ------------------------------------------------------------------------
if skip_has readme; then skipped LOCAL "S10" "README commands"; else
  source "${here}/verify-readme.sh"
fi

# --- S11 mirror round trip ------------------------------------------------------------------------
if skip_has mirror; then skipped LOCAL "S11" "mirror round trip"; else
  source "${here}/verify-mirror.sh"
fi
