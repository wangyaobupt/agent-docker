#!/usr/bin/env bash
set -euo pipefail

RETAIN_AGENT_BASE_DATES="${RETAIN_AGENT_BASE_DATES:-3}"

if ! [[ "${RETAIN_AGENT_BASE_DATES}" =~ ^[0-9]+$ && "${RETAIN_AGENT_BASE_DATES}" -gt 0 ]]; then
  echo "skipping agent-base tag retention; RETAIN_AGENT_BASE_DATES=${RETAIN_AGENT_BASE_DATES}"
  exit 0
fi

date_tags="$(
  docker image ls --format '{{.Tag}}' agent-base \
    | sed -nE 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/p' \
    | sort -u
)"
date_count="$(printf '%s\n' "${date_tags}" | sed '/^$/d' | wc -l | tr -d ' ')"
old_dates="$(
  printf '%s\n' "${date_tags}" \
    | sed '/^$/d' \
    | awk -v keep="${RETAIN_AGENT_BASE_DATES}" -v total="${date_count}" 'NR <= total - keep { print }'
)"

for old_date in ${old_dates}; do
  docker image ls --format '{{.Repository}}:{{.Tag}}' agent-base \
    | awk -v date="${old_date}" '$0 == "agent-base:" date || index($0, "agent-base:" date "-") == 1 { print }' \
    | while IFS= read -r image_ref; do
        echo "removing old base tag: ${image_ref}"
        docker image rm "${image_ref}" || true
      done
done
