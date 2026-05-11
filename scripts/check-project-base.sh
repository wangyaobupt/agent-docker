#!/usr/bin/env bash
set -euo pipefail

project_dir="${1:-$PWD}"
MAX_AGENT_BASE_AGE_DAYS="${MAX_AGENT_BASE_AGE_DAYS:-3}"

if [[ ! -d "${project_dir}" ]]; then
  echo "project directory does not exist: ${project_dir}" >&2
  exit 1
fi

latest_base_tag="$(
  docker image ls --format '{{.Repository}}:{{.Tag}}' agent-base \
    | sed -nE 's/^agent-base:([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' \
    | sort \
    | tail -n1
)"

if [[ -z "${latest_base_tag}" ]]; then
  echo "no local agent-base:YYYY-MM-DD image found"
  echo "build one first: REFRESH=1 bash /Users/wangyao/claudework/agent-docker/base/build.sh"
  exit 1
fi

if [[ ! "${MAX_AGENT_BASE_AGE_DAYS}" =~ ^[0-9]+$ ]]; then
  echo "invalid MAX_AGENT_BASE_AGE_DAYS: ${MAX_AGENT_BASE_AGE_DAYS}" >&2
  exit 1
fi

today_epoch="$(date -j -f '%Y-%m-%d' "$(date +%Y-%m-%d)" '+%s')"
latest_epoch="$(date -j -f '%Y-%m-%d' "${latest_base_tag}" '+%s')"
base_age_days="$(( (today_epoch - latest_epoch) / 86400 ))"

declared_tags=()

if [[ -n "${AGENT_BASE_TAG:-}" ]]; then
  declared_tags+=("${AGENT_BASE_TAG}")
fi

if [[ -f "${project_dir}/Dockerfile" ]]; then
  while IFS= read -r tag; do
    declared_tags+=("${tag}")
  done < <(
    sed -nE \
      -e 's/^ARG[[:space:]]+AGENT_BASE_TAG=([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/p' \
      -e 's/^FROM[[:space:]]+agent-base:([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/p' \
      "${project_dir}/Dockerfile"
  )
fi

for compose_file in docker-compose.yml compose.yml docker-compose.yaml compose.yaml; do
  if [[ -f "${project_dir}/${compose_file}" ]]; then
    while IFS= read -r tag; do
      declared_tags+=("${tag}")
    done < <(
      sed -nE 's/.*AGENT_BASE_TAG:[[:space:]]+\$\{AGENT_BASE_TAG:-([0-9]{4}-[0-9]{2}-[0-9]{2})\}.*/\1/p' \
        "${project_dir}/${compose_file}"
    )
  fi
done

project_tag=""
if [[ "${#declared_tags[@]}" -gt 0 ]]; then
  project_tag="${declared_tags[0]}"
fi

echo "latest local base: agent-base:${latest_base_tag}"
echo "latest local base age: ${base_age_days} day(s)"

if [[ "${base_age_days}" -gt "${MAX_AGENT_BASE_AGE_DAYS}" ]]; then
  echo "status: stale-local-base"
  echo "newest local base is older than ${MAX_AGENT_BASE_AGE_DAYS} day(s)"
  echo "refresh with: REFRESH=1 bash /Users/wangyao/claudework/agent-docker/base/build.sh"
  exit 2
fi

if [[ -z "${project_tag}" ]]; then
  echo "project base tag: not found"
  echo "status: unable to determine whether this project is pinned to the latest base"
  exit 0
fi

echo "project base tag: agent-base:${project_tag}"

if [[ "${project_tag}" == "${latest_base_tag}" ]]; then
  echo "status: current"
  exit 0
fi

echo "status: stale"
echo "rebuild with: AGENT_BASE_TAG=${latest_base_tag} docker compose build"
exit 2
