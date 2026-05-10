# agent-docker

A global skill for running **Codex** and **Claude Code** agents inside a versioned Docker base image, with full auto-execution backed by the host's `~/.codex` trust config (no `--dangerously-bypass-approvals-and-sandbox` flag, ever).

The repo provides:

- **`base/`** — a single base image (codex + claude + miniforge + build tools), tagged by build date, parameterized only at build time.
- **`lib/entrypoint-lib.sh`** — four shell primitives (`bootstrap_conda_env`, `editable_install_with_hash_stamp`, `default_codex_cmd`, `route_args`) that per-project entrypoints compose. Baked into the base image at `/usr/local/lib/agent-docker/entrypoint-lib.sh`.
- **`templates/`** — minimal per-project starters (Dockerfile ~10 lines, docker-compose.yml ~25 lines, entrypoint.sh ~20 lines). Each project copies these and fills placeholders.

The canonical documentation is **[SKILL.md](SKILL.md)** — read it before adopting the pattern in a new project. SKILL.md is symlinked into `~/.claude/skills/agent-docker/` and `~/.codex/skills/agent-docker/` so both agents can discover it.

To build the base image: `bash base/build.sh` (defaults to `codex@latest` + `claude@latest`, tags by date).
