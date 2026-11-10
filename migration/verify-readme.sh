# S10: run the commands of each tool README's "Working in the monorepo" section word for
# word in the fresh clone (sourced by verify-setup.sh). Every ```bash block of the section
# runs from the clone root with `bash -eo pipefail`, except the block that clones the
# monorepo itself (the clone already exists). Frontend blocks run inside the Cypress image
# (Cypress needs its browser dependencies); Python blocks run on the host.
readme_blocks() { # README -> blocks separated by NUL
  python3 - "$1" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"^## Working in the monorepo\n(.*?)(?=^## |\Z)", s, re.S | re.M)
for b in re.findall(r"```bash\n(.*?)```", m.group(1) if m else "", re.S):
    if "git clone" not in b:
        sys.stdout.write(b + "\0")
PY
}
for p in "${pkgs[@]}"; do
  IFS=$'\t' read -r _ dir _ <<<"${p}"
  n=0
  while IFS= read -r -d '' block; do
    n=$((n + 1))
    log="${work}/readme-${dir}-${n}.log"
    printf '%s\n' "${block}" >"${work}/readme-${dir}-${n}.sh"
    if [[ " ${node_pkgs[*]} " == *" ${dir} "* ]]; then
      docker run --rm --network=host -v "${clone}:${clone}" -v "${work}:${work}" -w "${clone}" --entrypoint bash \
        "${CYPRESS_IMAGE}" -eo pipefail "${work}/readme-${dir}-${n}.sh" >"${log}" 2>&1
    else
      ( cd "${clone}" && bash -eo pipefail "${work}/readme-${dir}-${n}.sh" ) >"${log}" 2>&1
    fi
    check LOCAL "S10 ${dir}" "README block ${n} ($(head -c 60 <<<"${block//$'\n'/; }")...) exit" "0" "$?"
    # Frontend blocks run the test suites: compare the counts with the baseline.
    clean="$(sed 's/\x1b\[[0-9;]*m//g' "${log}")"
    if grep -q 'npm run test:unit' <<<"${block}"; then
      v="$(grep -E '^\s+Tests\s' <<<"${clean}" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')"
      check LOCAL "S10 ${dir}" "vitest passed (baseline)" "${BASELINE_VITEST}" "${v:-0}"
    fi
    kinds=(); grep -q 'cypress run --component' <<<"${block}" && kinds+=(component); grep -q 'cypress run --e2e' <<<"${block}" && kinds+=(e2e)
    mapfile -t runs < <(grep -E 'All specs passed!|[0-9]+ of [0-9]+ failed' <<<"${clean}")
    for i in "${!kinds[@]}"; do
      line="${runs[$i]:-}"
      passed="$(grep -E 'All specs passed!' <<<"${line}" | awk '{print $(NF-3)}')"
      check LOCAL "S10 ${dir}" "Cypress ${kinds[$i]} passed (baseline)" "${BASELINE_CY[${dir}:${kinds[$i]}]}" "${passed:-0}"
    done
  done < <(readme_blocks "${clone}/packages/${dir}/README.md")
  check LOCAL "S10 ${dir}" "README section has runnable blocks" "yes" "$([[ ${n} -gt 0 ]] && echo yes)"
done
