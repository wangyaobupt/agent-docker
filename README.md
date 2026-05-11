# agent-docker

A global skill for running **Codex** and **Claude Code** agents inside a versioned Docker base image, with full auto-execution backed by the host's `~/.codex` trust config (no `--dangerously-bypass-approvals-and-sandbox` flag, ever).

The repo provides:

- **`base/`** — a single base image (codex + claude + miniforge + build tools), tagged by build date, parameterized only at build time.
- **`lib/entrypoint-lib.sh`** — four shell primitives (`bootstrap_conda_env`, `editable_install_with_hash_stamp`, `default_codex_cmd`, `route_args`) that per-project entrypoints compose. Baked into the base image at `/usr/local/lib/agent-docker/entrypoint-lib.sh`.
- **`templates/`** — minimal per-project starters (Dockerfile ~10 lines, docker-compose.yml ~25 lines, entrypoint.sh ~20 lines). Each project copies these and fills placeholders.

The canonical documentation is **[SKILL.md](SKILL.md)** — read it before adopting the pattern in a new project. SKILL.md is symlinked into `~/.claude/skills/agent-docker/` and `~/.codex/skills/agent-docker/` so both agents can discover it.

To build the base image: `bash base/build.sh` (defaults to `codex@latest` + `claude@latest`, tags by date).

For a guaranteed refresh that re-pulls the base image and re-resolves npm
`latest` packages, run:

```bash
REFRESH=1 bash base/build.sh
```

To install a daily macOS launchd job that does this at 06:30 local time:

```bash
bash scripts/install-launchd-daily-build.sh
```

Build logs are written to `logs/daily-build.log`.

The daily job keeps the newest 3 `agent-base:YYYY-MM-DD` builds by default and
prunes Docker build cache older than 168 hours. Override with
`RETAIN_AGENT_BASE_DATES=<count>` or `BUILDER_PRUNE_UNTIL=<duration>` if needed.

Before running a project container, check whether the newest local base image is
no more than 3 days old and whether that project is pinned to it:

```bash
scripts/check-project-base.sh /path/to/project
```

If it reports `status: stale`, rebuild that project image with the reported
latest date tag, for example:

```bash
cd /path/to/project
AGENT_BASE_TAG=YYYY-MM-DD docker compose build
```
