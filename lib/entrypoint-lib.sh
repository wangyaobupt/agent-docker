# /usr/local/lib/agent-docker/entrypoint-lib.sh
#
# Source this from a per-project entrypoint, then call the primitives.
#
# Public functions:
#   bootstrap_conda_env <env-name> [python-version]
#   editable_install_with_hash_stamp <state-dir> <stamp-name> [<spec> <dist-name> <norm-name>]...
#   default_codex_cmd <workspace-dir>
#   route_args <workspace-dir> <args...>
#
# The library never adds --dangerously-bypass-approvals-and-sandbox to any
# codex invocation. Trust gating must come from the mounted ~/.codex config.

_agent_docker_lib_loaded=1
CONDA_SH="${CONDA_SH:-/opt/conda/etc/profile.d/conda.sh}"

_hash_files() {
  # Internal helper: sha256 of concatenated file hashes (silently skips missing files).
  local f
  local present=()
  for f in "$@"; do
    [[ -f "${f}" ]] && present+=("${f}")
  done
  if [[ ${#present[@]} -eq 0 ]]; then
    echo ""
    return
  fi
  sha256sum "${present[@]}" | sha256sum | awk '{print $1}'
}

bootstrap_conda_env() {
  # Create the conda env if missing, then activate it. Idempotent.
  local env_name="${1:?env-name required}"
  local py_version="${2:-3.12}"

  source "${CONDA_SH}"
  if ! conda env list | awk '{print $1}' | grep -qx "${env_name}"; then
    conda create -y -n "${env_name}" "python=${py_version}" pip
  fi
  conda activate "${env_name}"
}

editable_install_with_hash_stamp() {
  # Hash project metadata; on hash drift OR install failure, do an editable
  # install with the CoT repair pattern (uninstall + clean stale dist-info,
  # then retry). Stamp file lives in <state-dir> and survives across runs.
  #
  # Each install is described by a (spec, dist-name, normalized-name) triple:
  #   spec            argument to `pip install -e` (path or path[extras])
  #   dist-name       distribution name for `pip uninstall`
  #   normalized-name PEP 503 name for *.dist-info / __editable__.<n>-*.pth
  #
  # Requires bootstrap_conda_env to have run first.
  local state_dir="${1:?state-dir required}"
  local stamp_name="${2:?stamp-name required}"
  shift 2

  mkdir -p "${state_dir}"
  local stamp_file="${state_dir}/${stamp_name}"

  local site_packages
  site_packages="$(python - <<'PY'
import sysconfig
print(sysconfig.get_paths()["purelib"])
PY
)"

  local -a triples=("$@")
  if (( ${#triples[@]} % 3 != 0 )); then
    echo "editable_install_with_hash_stamp: triples must be (spec, dist-name, normalized-name)" >&2
    return 1
  fi

  local -a meta_files=()
  local i
  for ((i=0; i<${#triples[@]}; i+=3)); do
    local spec="${triples[i]}"
    local path="${spec%%[*}"
    local candidate
    for candidate in "${path}/pyproject.toml" "${path}/setup.py" "${path}/setup.cfg" "${path}/requirements.txt"; do
      [[ -f "${candidate}" ]] && meta_files+=("${candidate}")
    done
  done

  local current_hash previous_hash=""
  current_hash="$(_hash_files "${meta_files[@]}")"
  [[ -f "${stamp_file}" ]] && previous_hash="$(cat "${stamp_file}")"

  if [[ "${current_hash}" == "${previous_hash}" && -n "${current_hash}" ]]; then
    return 0
  fi

  python -m pip install --upgrade pip
  for ((i=0; i<${#triples[@]}; i+=3)); do
    local spec="${triples[i]}"
    local dist_name="${triples[i+1]}"
    local norm_name="${triples[i+2]}"
    if ! python -m pip install -e "${spec}"; then
      echo "Repairing stale editable install for ${dist_name}" >&2
      python -m pip uninstall -y "${dist_name}" >/dev/null 2>&1 || true
      rm -rf \
        "${site_packages}/${norm_name}"-*.dist-info \
        "${site_packages}/__editable__.${norm_name}"-*.pth
      python -m pip install -e "${spec}"
    fi
  done

  printf '%s\n' "${current_hash}" > "${stamp_file}"
}

default_codex_cmd() {
  # Print the canonical interactive codex command (one token per line).
  # NEVER includes --dangerously-bypass-approvals-and-sandbox.
  local workspace="${1:?workspace required}"
  printf '%s\n' codex -C "${workspace}"
}

route_args() {
  # Standard arg-routing table. Always exec's; never returns on success.
  #
  #   no args              -> default_codex_cmd (interactive codex)
  #   $CODEX_PROMPT set    -> default_codex_cmd <prompt>
  #   codex ...            -> exec verbatim (handoff path: codex exec ...)
  #   bash|sh|zsh|...      -> pass through verbatim
  #   make|pytest|python*  -> pass through verbatim
  #   -*                   -> append to default_codex_cmd
  #   *                    -> treat $1+ as a single positional prompt
  local workspace="${1:?workspace required}"
  shift

  local -a base_cmd
  mapfile -t base_cmd < <(default_codex_cmd "${workspace}")

  if [[ $# -eq 0 ]]; then
    if [[ -n "${CODEX_PROMPT:-}" ]]; then
      exec "${base_cmd[@]}" "${CODEX_PROMPT}"
    fi
    exec "${base_cmd[@]}"
  fi

  case "$1" in
    codex)
      if [[ -n "${CODEX_PROMPT:-}" && "${2:-}" == "exec" ]]; then
        exec "$@" "${CODEX_PROMPT}"
      fi
      exec "$@"
      ;;
    bash|sh|zsh|/bin/bash|/bin/sh|/bin/zsh|make|pytest|python|python3)
      exec "$@"
      ;;
    -*)
      if [[ -n "${CODEX_PROMPT:-}" ]]; then
        exec "${base_cmd[@]}" "$@" "${CODEX_PROMPT}"
      fi
      exec "${base_cmd[@]}" "$@"
      ;;
    *)
      exec "${base_cmd[@]}" "$*"
      ;;
  esac
}
