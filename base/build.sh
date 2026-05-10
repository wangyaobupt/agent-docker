#!/usr/bin/env bash
set -euo pipefail

CODEX_VERSION="${CODEX_VERSION:-latest}"
CLAUDE_VERSION="${CLAUDE_VERSION:-latest}"
DATE_TAG="${DATE_TAG:-$(date +%Y-%m-%d)}"
PRIMARY_TAG="agent-base:${DATE_TAG}"

cd "$(dirname "$0")/.."

docker build \
  --build-arg "CODEX_VERSION=${CODEX_VERSION}" \
  --build-arg "CLAUDE_VERSION=${CLAUDE_VERSION}" \
  -f base/Dockerfile.base \
  -t "${PRIMARY_TAG}" \
  .

_extract_semver() {
  # First semver-looking token in the input. Handles `codex-cli X.Y.Z` and
  # `X.Y.Z (Claude Code)` and any future minor format change as long as the
  # version is the only X.Y.Z[.W] token.
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

resolved_codex=$(docker run --rm "${PRIMARY_TAG}" codex --version 2>/dev/null | _extract_semver)
resolved_claude=$(docker run --rm "${PRIMARY_TAG}" claude --version 2>/dev/null | _extract_semver)
SECONDARY_TAG="agent-base:${DATE_TAG}-codex-${resolved_codex}-claude-${resolved_claude}"
docker tag "${PRIMARY_TAG}" "${SECONDARY_TAG}"
docker tag "${PRIMARY_TAG}" agent-base:latest

cat <<EOF
built ${PRIMARY_TAG}
  also tagged: ${SECONDARY_TAG}
  also tagged: agent-base:latest
  resolved codex:  ${resolved_codex}
  resolved claude: ${resolved_claude}

Projects should pin to the date tag (${PRIMARY_TAG}) for reproducibility.
The :latest tag exists for casual / fresh-project use; do not rely on it
for production projects without re-validating after each rebuild.
EOF
