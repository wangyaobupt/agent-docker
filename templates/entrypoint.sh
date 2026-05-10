#!/usr/bin/env bash
set -euo pipefail

source /usr/local/lib/agent-docker/entrypoint-lib.sh

CONDA_ENV_NAME="${CONDA_ENV_NAME:-<PROJECT_CONDA_ENV>}"
WORKSPACE="${WORKSPACE:-/workspace/<PROJECT_NAME>}"
STATE_DIR="/opt/conda/envs/${CONDA_ENV_NAME}/.container-state"

if [[ ! -d "${WORKSPACE}" ]]; then
  echo "Missing workspace mount at ${WORKSPACE}" >&2
  exit 1
fi

bootstrap_conda_env "${CONDA_ENV_NAME}"

# Editable installs — adjust triples for your project. Each triple is:
#   <pip-spec> <dist-name> <normalized-name>
# editable_install_with_hash_stamp \
#   "${STATE_DIR}" python-deps.sha256 \
#   "${WORKSPACE}" my-project my_project

# project_specific_bootstrap (config gen, env exports, etc.) goes here.

cd "${WORKSPACE}"
route_args "${WORKSPACE}" "$@"
