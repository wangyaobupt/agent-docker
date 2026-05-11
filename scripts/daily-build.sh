#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${REPO_DIR}/logs"
LOCK_DIR="${TMPDIR:-/tmp}/agent-docker-daily-build.lock"
BUILDER_PRUNE_UNTIL="${BUILDER_PRUNE_UNTIL:-168h}"

mkdir -p "${LOG_DIR}"

exec >>"${LOG_DIR}/daily-build.log" 2>&1

echo
echo "===== $(date '+%Y-%m-%d %H:%M:%S %z') agent-docker daily build start ====="

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "another daily build is already running; exiting"
  exit 0
fi
trap 'rm -rf "${LOCK_DIR}"' EXIT

if ! docker info >/dev/null 2>&1; then
  echo "docker is not available; start Docker Desktop and retry"
  exit 1
fi

REFRESH=1 bash "${REPO_DIR}/base/build.sh"

bash "${SCRIPT_DIR}/prune-old-bases.sh"

if [[ -n "${BUILDER_PRUNE_UNTIL}" ]]; then
  echo "pruning Docker build cache older than ${BUILDER_PRUNE_UNTIL}"
  docker builder prune -f --filter "until=${BUILDER_PRUNE_UNTIL}"
fi

echo "===== $(date '+%Y-%m-%d %H:%M:%S %z') agent-docker daily build complete ====="
