# Monorepo setup checks (Phase 3). Sourced by verify.sh, which provides: repo_dir, work,
# here, org, pkgs, symlinks, datas, g(), check(), pass(), fail(), upstream(), src_sha(),
# merge_of().
#
# Checks (S = setup), labelled LOCAL (run here) or CI (listed, verified on GitHub):
#   S1  check-unchanged.sh passes (a local migration check, not in CI); mirror workflow and
#       mirror-check PR job present
#   S2  release-please config and manifest (components, paths, versions = last tags,
#       bootstrap-sha, changelog sections: only feat/fix/perf/refactor/revert release),
#       GitHub Releases on, release outputs wired to publishing, nightly jobs in the image
#       tools' workflows, no path-filter action, no custom workflow scripts, no literal
#       override marker in docs/templates, per-tool Python versions readable by the CI step
#   S3  fresh clone; uv sync per Python tool and Python version; npm ci for query-tool
#   S4  prek run --all-files (every tool's own config + the root config) passes without
#       changing files
#   S5  pytest counts equal the baseline (per tool and Python version); query-tool counts
#       in S10
#   S6  Python tool versions come from the tool's tags
#   S7  configure-nb wheel and sdist contents equal upstream's
#   S8  images build from a clean checkout; file listings equal upstream images
#   S9  deliberate failures: every guard fires
#   S10 README "Working in the monorepo" commands run word for word in a fresh clone;
#       query-tool's block runs its full Cypress suites: counts = baseline
#   S11 local mirror round trip into copies of the old repositories (verify-mirror.sh)

skip_has() { [[ ",${VERIFY_SKIP:-}," == *",$1,"* ]]; }
skipped() { printf 'SKIP [%s] %s: %s (VERIFY_SKIP)\n' "$1" "$2" "$3"; fails=$((fails + 1)); }
note_ci() { printf 'CI   %s: %s\n' "$1" "$2"; }
relabel() { command -v chcon >/dev/null && chcon -R -u system_u -l s0 "$1" 2>/dev/null || true; }

# Baseline (migration/baseline.md): pytest passed per tool, the same on each of the tool's
# Python versions (its own CI matrix, tools/<tool>/.github/workflows/test.yaml).
declare -A BASELINE_PYTEST=([tools/api]=184 [tools/federation-api]=111 [tools/configure-nb]=38)
declare -A PYTEST_ARGS=([tools/api]='-m "not integration"' [tools/federation-api]='' [tools/configure-nb]='')
declare -A BASELINE_CY=([tools/query-tool:component]=91 [tools/query-tool:e2e]=41)
CYPRESS_IMAGE=docker.io/cypress/included:15.21.1
PREK=(uvx --quiet prek@0.5.11)

# The Python versions of a tool, read by the same code as the CI step in test-python.yml.
py_snippet="${work}/python-versions.py"
g show HEAD:.github/workflows/test-python.yml | awk '/<<.PY.$/ {on=1; next} /^ *PY$/ {on=0} on' | sed 's/^          //' >"${py_snippet}"
py_versions() { uv run --no-project --quiet --with pyyaml==6.0.3 python "${py_snippet}" "$1" | tr -d '[]",'; }

py_pkgs=(); node_pkgs=()
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r _ dir _ <<<"${p}"
  [[ "${dir}" == tools/* ]] || continue
  if g cat-file -e "HEAD:${dir}/pyproject.toml" 2>/dev/null; then py_pkgs+=("${dir}"); else node_pkgs+=("${dir}"); fi
done
declare -A PYTHONS
for dir in "${py_pkgs[@]}"; do
  PYTHONS[${dir}]="$(cd "${repo_dir}" && py_versions "${dir}/.github/workflows/test.yaml" 2>&1)"
done

# --- S1 check-unchanged ---------------------------------------------------------------
out="$(cd "${repo_dir}" && migration/check-unchanged.sh 2>&1)"; rc=$?
check LOCAL "S1" "check-unchanged.sh exit ($(tail -1 <<<"${out}"))" "0" "${rc}"
check LOCAL "S1" "check-unchanged not in CI (no workflow runs it)" "0" "$(g grep -c check-unchanged HEAD -- .github/workflows | wc -l)"
check LOCAL "S1" "mirror workflow and mirror-check PR job present" "yes yes" "$(g cat-file -e HEAD:.github/workflows/mirror.yml 2>/dev/null && echo yes) $(g show HEAD:.github/workflows/pr-checks.yml | grep -q "scripts/mirror.py --check" && echo yes)"

# --- S2 release configuration -----------------------------------------------------------
s2="$(cd "${repo_dir}" && uv run --no-project --quiet --with pyyaml==6.0.3 python - "${here}/names.yaml" <<'PY'
import json, subprocess, sys, yaml
names = yaml.safe_load(open(sys.argv[1]))
cfg = json.load(open("release-please-config.json"))
man = json.load(open(".release-please-manifest.json"))
problems = []
want = {p["dir"]: p["tag_prefix"] for p in names["packages"]}
got = {path: c.get("component") for path, c in cfg["packages"].items()}
if want != got: problems.append(f"components {got} != names.yaml {want}")
for k, v in [("separate-pull-requests", False), ("bump-minor-pre-major", True), ("include-component-in-tag", True), ("tag-separator", "-"), ("include-v-in-tag", True)]:
    if cfg.get(k) != v: problems.append(f"{k}={cfg.get(k)!r}, want {v!r}")
visible = sorted(s["type"] for s in cfg.get("changelog-sections", []) if not s.get("hidden"))
hidden = sorted(s["type"] for s in cfg.get("changelog-sections", []) if s.get("hidden"))
if visible != ["feat", "fix", "perf", "refactor", "revert"]: problems.append(f"releasing types {visible}")
if hidden != ["build", "chore", "ci", "docs", "style", "test"]: problems.append(f"hidden types {hidden}")
for path, comp in want.items():
    tags = subprocess.run(["git", "tag", "-l", f"{comp}-v*", "--merged", "HEAD", "--sort=-v:refname"], capture_output=True, text=True).stdout.split()
    final = [t for t in tags if "-" not in t[len(comp) + 2:]]
    latest = final[0][len(comp) + 2:] if final else None
    if man.get(path) != latest: problems.append(f"manifest {path}={man.get(path)} != last tag {latest}")
    rt = cfg["packages"][path]["release-type"]
    has = lambda f: subprocess.run(["git", "cat-file", "-e", f"HEAD:{path}/{f}"], capture_output=True).returncode == 0
    want_rt = "node" if path.startswith("tools/") and has("package.json") and not has("pyproject.toml") else "simple"
    if rt != want_rt: problems.append(f"{path} release-type {rt}, want {want_rt}")
print("; ".join(problems) or "ok")
PY
)"
check LOCAL "S2" "release-please config/manifest vs names.yaml and tags; changelog sections" "ok" "${s2}"
bsha="$(cd "${repo_dir}" && jq -r '."bootstrap-sha"' release-please-config.json)"
import_end="$(g log --first-parent --format=%H -n 1 --grep='^chore: replace submodules with symlinks' HEAD)"
check LOCAL "S2" "bootstrap-sha is the last import commit (git cat-file -t)" "${import_end} commit" "${bsha} $(g cat-file -t "${bsha}" 2>&1)"
marker="BEGIN_COMMIT""_OVERRIDE"
hits="$(cd "${repo_dir}" && git grep -l -F "${marker}" -- '*.md' '.github/*.md' ':!tools' ':!recipes' ':!examples' | tr '\n' ' ')"
check LOCAL "S2" "literal override marker in templates/docs" "" "${hits}"
if command -v actionlint >/dev/null; then
  al="$(cd "${repo_dir}" && actionlint .github/workflows/*.yml 2>&1 | grep -cE '^\.github')"
  check LOCAL "S2" "actionlint findings" "0" "${al}"
fi
rel="$(g show HEAD:.github/workflows/release.yml)"
check LOCAL "S2" "release-please creates GitHub Releases (no skip-github-release)" "0" "$(grep -c 'skip-github-release' <<<"${rel}")"
miss=""
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r _ dir _ <<<"${p}"
  grep -qF "steps.rp.outputs['${dir}--release_created']" <<<"${rel}" || miss+="${dir} "
done
check LOCAL "S2" "release outputs exposed for every package" "" "${miss% }"
pub=""
for job in api-image federation-api-image query-tool-image query-tool-site configure-nb; do
  grep -qE "^  ${job}:" <<<"${rel}" || pub+="${job} "
done
check LOCAL "S2" "publishing jobs in release.yml" "" "${pub% }"
grep -q 'Add the authors to the GitHub Releases' <<<"${rel}"; check LOCAL "S2" "release.yml adds the authors to the GitHub Releases" "0" "$?"
nightly=""
for t in api federation-api query-tool; do
  g show "HEAD:.github/workflows/${t}.yml" | grep -qE '^  nightly:' || nightly+="${t} "
done
check LOCAL "S2" "nightly job in each image tool's workflow" "" "${nightly% }"
check LOCAL "S2" "no path-filter action (dorny/paths-filter)" "" "$(g grep -l 'paths-filter' HEAD -- .github | tr '\n' ' ')"
check LOCAL "S2" "no custom workflow scripts (.github/scripts)" "" "$(g ls-tree --name-only -r HEAD .github/scripts | tr '\n' ' ')"
for dir in "${py_pkgs[@]}"; do
  check LOCAL "S2 ${dir}" "Python versions read by the test-python.yml step from the tool's test.yaml (${PYTHONS[${dir}]})" "ok" \
    "$([[ "${PYTHONS[${dir}]}" =~ ^3\.[0-9]+(\ 3\.[0-9]+)*$ ]] && echo ok || echo "${PYTHONS[${dir}]}")"
done
note_ci "S2" "release-please (bot token) opens one combined release PR; CI runs on it (Phase 4)"

# --- S3 fresh clone and installs --------------------------------------------------------
clone="${work}/clone"
rm -rf "${clone}"
git clone -q "${repo_dir}" "${clone}"
relabel "${clone}"
check LOCAL "S3" "fresh clone: no submodules" "0" "$(git -C "${clone}" submodule status | wc -l)"
for dir in "${py_pkgs[@]}"; do
  for py in ${PYTHONS[${dir}]}; do
    ( cd "${clone}/${dir}" && UV_PROJECT_ENVIRONMENT="${work}/venvs/${dir//\//_}-${py}" uv sync -q --python "${py}" --group dev ) >"${work}/sync-${dir//\//_}-${py}.log" 2>&1
    check LOCAL "S3 ${dir}" "uv sync --python ${py} --group dev" "0" "$?"
  done
done
for dir in "${node_pkgs[@]}"; do
  ( cd "${clone}/${dir}" && npm ci ) >"${work}/npmci-${dir//\//_}.log" 2>&1
  check LOCAL "S3 ${dir}" "npm ci" "0" "$?"
done
check LOCAL "S3" "husky did not take over the git hooks (core.hooksPath unset)" "" "$(git -C "${clone}" config --get core.hooksPath)"

# --- S4 commit hooks (prek workspace) ---------------------------------------------------------
( cd "${clone}" && "${PREK[@]}" run --all-files ) >"${work}/prek.log" 2>&1
check LOCAL "S4" "prek run --all-files" "0" "$?"
check LOCAL "S4" "files changed by the hooks" "" "$(git -C "${clone}" status --porcelain --untracked-files=no | tr '\n' ' ')"
projects="$(grep -v '^ ' "${work}/prek.log" | grep -oE '(tools/[^ ]+|<workspace>)$' | sort | tr '\n' ' ')"
check LOCAL "S4" "projects run (each tool's own config and the root config)" "<workspace> tools/api tools/configure-nb tools/federation-api tools/query-tool " "${projects}"
( cd "${clone}" && "${PREK[@]}" install ) >/dev/null 2>&1
check LOCAL "S4" "prek install: pre-commit and post-merge hooks (one command)" "post-merge pre-commit " \
  "$(ls "${clone}/.git/hooks" | grep -v '\.sample$' | sort | tr '\n' ' ')"
( cd "${clone}" && "${PREK[@]}" uninstall ) >/dev/null 2>&1
note_ci "S4" "the prek job of pr-checks.yml runs the hooks on every PR (Phase 4)"

# --- S5 test counts ---------------------------------------------------------------------
if skip_has tests; then skipped LOCAL "S5" "pytest counts"; else
  for dir in "${py_pkgs[@]}"; do
    for py in ${PYTHONS[${dir}]}; do
      log="${work}/pytest-${dir//\//_}-${py}.log"
      ( cd "${clone}/${dir}" && eval "UV_PROJECT_ENVIRONMENT=${work}/venvs/${dir//\//_}-${py} uv run --no-sync --python ${py} pytest ${PYTEST_ARGS[${dir}]} -p no:cacheprovider" ) >"${log}" 2>&1
      rc=$?
      summary="$(tail -1 "${log}")"
      passed="$(grep -oE '[0-9]+ passed' <<<"${summary}" | grep -oE '[0-9]+')"
      check LOCAL "S5 ${dir}" "pytest ${py} exit and passed (${summary//=/})" "0 ${BASELINE_PYTEST[${dir}]}" "${rc} ${passed:-0}"
    done
  done
fi
# query-tool's test counts (Cypress component and e2e) are checked in S10 from the README
# commands, which run its full test suites; running them twice costs ~10 min.
note_ci "S5" "path-filtered workflows: a PR touching one tool runs only its tests; a shared workflow change runs all (Phase 4)"

# --- S6 versions from tags ----------------------------------------------------------------
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r _ dir prefix <<<"${p}"
  [[ " ${py_pkgs[*]} " == *" ${dir} "* ]] || continue
  latest="$(git -C "${clone}" tag -l "${prefix}-v*" --merged HEAD --sort=-v:refname | grep -E "^${prefix}-v[0-9]+\.[0-9]+\.[0-9]+$" | head -1)"
  latest="${latest#"${prefix}"-v}"
  IFS=. read -r ma mi pa <<<"${latest}"
  v="$(cd "${clone}/${dir}" && uvx --quiet --with hatch-vcs hatchling version 2>&1 | tail -1)"
  check LOCAL "S6 ${dir}" "version after last tag ${prefix}-v${latest}" "${ma}.${mi}.$((pa + 1)).dev" "${v%.dev*}.dev"
  git -C "${clone}" tag "${prefix}-v99.1.2" HEAD
  v="$(cd "${clone}/${dir}" && uvx --quiet --with hatch-vcs hatchling version 2>&1 | tail -1)"
  git -C "${clone}" tag -d "${prefix}-v99.1.2" >/dev/null
  check LOCAL "S6 ${dir}" "version with a temporary ${prefix}-v99.1.2 tag on HEAD" "99.1.2" "${v}"
done

# Full upstream clones at the imported commits (for S7, S8).
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

# --- S7 configure-nb wheel and sdist ---------------------------------------------------------
cnb_up="$(upstream_full configure-nb)"
list_dist() { # dir -> "wheel files" and "sdist files", versions normalized
  ( cd "$1" && rm -rf dist && uvx --quiet --from build pyproject-build --installer uv >/dev/null 2>&1 \
    && python3 -c '
import tarfile, zipfile, glob, re
w = glob.glob("dist/*.whl")[0]; s = glob.glob("dist/*.tar.gz")[0]
norm = lambda n: re.sub(r"configure_nb-[0-9][^/]*?(\.dist-info|/|$)", r"configure_nb-VERSION\1", n)
wf = sorted(norm(n) for n in zipfile.ZipFile(w).namelist() if not n.endswith("RECORD"))
sf = sorted(norm(m.name) for m in tarfile.open(s).getmembers() if m.isfile())
print(len(wf), len(sf))
open("dist/wheel.txt","w").write("\n".join(wf)); open("dist/sdist.txt","w").write("\n".join(sf))
' )
}
mono_counts="$(list_dist "${clone}/tools/configure-nb")"
up_counts="$(list_dist "${cnb_up}")"
check LOCAL "S7" "configure-nb wheel files, sdist files" "${up_counts}" "${mono_counts}"
d="$(diff <(cat "${cnb_up}/dist/wheel.txt") <(cat "${clone}/tools/configure-nb/dist/wheel.txt") | grep -c '^[<>]')"
check LOCAL "S7" "configure-nb wheel file list differences vs upstream" "0" "${d}"
d="$(diff <(cat "${cnb_up}/dist/sdist.txt") <(cat "${clone}/tools/configure-nb/dist/sdist.txt") | grep -c '^[<>]')"
check LOCAL "S7" "configure-nb sdist file list differences vs upstream" "0" "${d}"
rm -rf "${clone}/tools/configure-nb/dist" "${cnb_up}/dist"

# --- S8 images ------------------------------------------------------------------------------
if skip_has images; then skipped LOCAL "S8" "image builds and file listings"; else
  # Images are built from a pristine clone: earlier checks leave __pycache__ and
  # _version.py in ${clone}, and api/federation-api have no .dockerignore.
  iclone="${work}/clone-images"
  rm -rf "${iclone}"
  git clone -q "${repo_dir}" "${iclone}"
  # As docker-build.yml does: replace the tools' symlinks with copies of their targets.
  ( cd "${iclone}" && git ls-files -s tools | awk '$1=="120000" {print $4}' | while read -r link; do
      target="$(readlink -f "${link}")"; rm "${link}"; cp -R "${target}" "${link}"; done )
  # file listing of an image: every path in its filesystem, with symlink targets
  listing() { local c; c="$(docker create "$1")"; docker export "${c}" | tar -tv | awk '{$1=$2=$3=$4=$5=""; print}' | sed 's/^ *//' | sort; docker rm -f "${c}" >/dev/null; }
  build_list() { # name context dockerfile out
    docker build -q -t "verify/$1" -f "$2/$3" "$2" >"${work}/build-$1.log" 2>&1 || { echo BUILD-FAILED; return; }
    listing "verify/$1" >"$4"
  }
  for repo in api federation-api query-tool; do
    up="$(upstream_full "${repo}")"
    git -C "${up}" clean -q -fdx && git -C "${up}" submodule foreach -q --recursive git clean -q -fdx
    build_list "up-${repo}" "${up}" Dockerfile "${work}/image-up-${repo}.txt"
    build_list "mono-${repo}" "${iclone}/tools/${repo}" Dockerfile "${work}/image-mono-${repo}.txt"
    nd="$(diff "${work}/image-up-${repo}.txt" "${work}/image-mono-${repo}.txt" | grep -c '^[<>]')"
    check LOCAL "S8 ${repo}" "image builds; file listing differences vs upstream image ($(wc -l <"${work}/image-mono-${repo}.txt") entries)" "0" "${nd}"
  done
  note_ci "S8" "images-validation.yml pushes every image to ghcr with a validation tag; a push to main builds the nightly images of the changed tools (Phase 4)"
fi

# --- S9 deliberate failures -------------------------------------------------------------------
scratch="${work}/guards"
rm -rf "${scratch}"; git clone -q "${repo_dir}" "${scratch}"
gs() { git -C "${scratch}" -c user.name=verify -c user.email=verify@example.org "$@"; }
base="$(gs rev-parse HEAD)"
# Controls: each guard command below passes on the unchanged files (so a failure below comes
# from the deliberate change, not from a hook that is not found).
ctl=""
for spec in "check-dependabot .github/dependabot.yml" "actionlint .github/workflows/release.yml" \
            "codespell tools/query-tool/src/main.tsx" "flake8 tools/configure-nb/configure_nb/__init__.py"; do
  ( cd "${scratch}" && "${PREK[@]}" run ${spec%% *} --files ${spec#* } >"${work}/guard-control.log" 2>&1 ) || ctl+="${spec%% *} "
  grep -q 'Passed' "${work}/guard-control.log" || ctl+="${spec%% *}(not run) "
done
check LOCAL "S9" "controls: the guard hooks run and pass on unchanged files" "" "${ctl% }"
# check-unchanged: a protected tool file changes
echo "# changed" >>"${scratch}/tools/api/app/main.py"
gs commit -qam "fix(api): touch a protected file"
( cd "${scratch}" && migration/check-unchanged.sh >/dev/null 2>&1 ); check LOCAL "S9" "check-unchanged fails on a changed protected file (exit)" "1" "$?"
gs reset -q --hard "${base}"
# dependabot schema check (root config)
printf 'version: 2\nupdates:\n  - package-ecosystem: "npm"\n    schedule: {interval: "sometimes"}\n' >"${scratch}/.github/dependabot.yml"
( cd "${scratch}" && "${PREK[@]}" run check-dependabot --files .github/dependabot.yml >/dev/null 2>&1 ); check LOCAL "S9" "check-dependabot fails on an invalid config (exit != 0)" "1" "$(( $? != 0 ))"
gs checkout -q -- .github/dependabot.yml
# actionlint (root config)
printf 'name: x\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ${{ github.nonexistent }}\n' >"${scratch}/.github/workflows/broken.yml"
( cd "${scratch}" && "${PREK[@]}" run actionlint --files .github/workflows/broken.yml >/dev/null 2>&1 ); check LOCAL "S9" "actionlint hook fails on a broken workflow (exit != 0)" "1" "$(( $? != 0 ))"
rm -f "${scratch}/.github/workflows/broken.yml"
# codespell in query-tool's own config (moved from its CI into the commit hooks)
echo "// teh" >>"${scratch}/tools/query-tool/src/main.tsx"
( cd "${scratch}" && "${PREK[@]}" run codespell --files tools/query-tool/src/main.tsx >/dev/null 2>&1 ); check LOCAL "S9" "query-tool codespell hook fails on a typo (exit != 0)" "1" "$(( $? != 0 ))"
gs checkout -q -- tools/query-tool/src/main.tsx
# a tool's own config runs from its folder: flake8 in configure-nb (its .flake8)
printf '\nimport os\n' >>"${scratch}/tools/configure-nb/configure_nb/__init__.py"
( cd "${scratch}" && "${PREK[@]}" run flake8 --files tools/configure-nb/configure_nb/__init__.py >/dev/null 2>&1 ); check LOCAL "S9" "configure-nb flake8 hook (own config) fails on an unused import (exit != 0)" "1" "$(( $? != 0 ))"
gs checkout -q -- tools/configure-nb/configure_nb/__init__.py
# shared configs: a copy that differs from its source
echo "shared" >"${scratch}/shared/verify.txt"; echo "edited copy" >"${scratch}/tools/api/verify.txt"
printf -- '- source: shared/verify.txt\n  copies:\n    - tools/api/verify.txt\n    - tools/federation-api/verify.txt\n' >"${scratch}/shared/files.yaml"
( cd "${scratch}" && uv run --no-project --quiet --with pyyaml==6.0.3 python scripts/sync-shared.py --check >/dev/null 2>&1 ); rc=$?
( cd "${scratch}" && "${PREK[@]}" run sync-shared --all-files >/dev/null 2>&1 ); rc2=$?
check LOCAL "S9" "shared configs: --check fails on differing copies; the hook fails and writes them" "1 1 shared shared" \
  "$(( rc != 0 )) $(( rc2 != 0 )) $(cat "${scratch}/tools/api/verify.txt") $(cat "${scratch}/tools/federation-api/verify.txt" 2>/dev/null)"
( cd "${scratch}" && uv run --no-project --quiet --with pyyaml==6.0.3 python scripts/sync-shared.py --check >/dev/null 2>&1 ); check LOCAL "S9" "shared configs: --check passes once the copies are written" "0" "$?"
gs checkout -q -- shared/files.yaml; rm -f "${scratch}/shared/verify.txt" "${scratch}/tools/api/verify.txt" "${scratch}/tools/federation-api/verify.txt"
# Python versions: a tool test workflow without a python-version list
printf 'jobs:\n  test:\n    runs-on: ubuntu-latest\n' >"${scratch}/tools/api/.github/workflows/test.yaml"
( cd "${scratch}" && py_versions tools/api/.github/workflows/test.yaml >/dev/null 2>&1 ); check LOCAL "S9" "test-python.yml step fails on a test.yaml without Python versions (exit != 0)" "1" "$(( $? != 0 ))"
gs checkout -q -- tools/api/.github/workflows/test.yaml
note_ci "S9" "on GitHub: PR title check rejects a non-conventional title; release preview shows per-tool entries (Phase 4)"

# --- S10 README commands ------------------------------------------------------------------------
if skip_has readme; then skipped LOCAL "S10" "README commands"; else
  source "${here}/verify-readme.sh"
fi

# --- S11 mirror round trip ------------------------------------------------------------------------
if skip_has mirror; then skipped LOCAL "S11" "mirror round trip"; else
  source "${here}/verify-mirror.sh"
fi
