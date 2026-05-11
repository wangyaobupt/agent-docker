---
name: agent-docker
description: Run Codex / Claude Code agents inside a versioned base Docker image with full auto-execution backed by the host ~/.codex trust config. Provides a base-image build, an entrypoint shell library (sourced from per-project entrypoints), and copy-and-fill templates so each project carries only ~10 lines of Dockerfile and ~20 lines of entrypoint.
---

# agent-docker

A global pattern for running Codex/Claude Code agents in containers without per-project Docker maintenance and without the `--dangerously-bypass-approvals-and-sandbox` flag.

## What this skill is for

Every project that wants to run a coding agent in Docker needs the same scaffolding: a base image with codex+claude+conda, an entrypoint that bootstraps a conda env, an arg-routing table that distinguishes `codex exec` handoffs from `bash`/`make`/`pytest` invocations, mount declarations that pull in the host's `~/.codex` trust config, and a default command that does *not* pass `--dangerously-bypass-approvals-and-sandbox`. Maintaining all of that in every repo causes drift; this skill hoists the common 70% into a globally-built base image plus a sourced shell library, and lets each project carry only the genuinely project-specific 30% (apt extras, conda env name, editable install list, mount choices).

## The trust-config approval boundary

The container's approval boundary is the host's `~/.codex/config.toml`, mounted at `/root/.codex`. When a project is marked `trust_level = "trusted"` there, codex inside the container runs without per-tool approval prompts in non-interactive contexts. The container's *isolation* boundary is Docker (the bind-mount set is the surface area).

**Never pass `--dangerously-bypass-approvals-and-sandbox` to codex inside an agent container** — neither to `codex exec` nor to interactive `codex`. The flag conflates approval and sandbox, suppresses the audit signal that should fire if host trust is later revoked, and is documented by codex's own help as "EXTREMELY DANGEROUS … intended solely for environments that are externally sandboxed." The mounted trust config is the right boundary; the bypass flag is redundant.

`default_codex_cmd` in `lib/entrypoint-lib.sh` and the templates here all omit the flag deliberately. If a handoff fails because codex blocks on an approval, the fix is to mark the project trusted on the host (`~/.codex/config.toml`), not to add the bypass flag.

`-s danger-full-access` is a different flag — it controls the spawned-shell sandbox (`workspace-write` default blocks network; `danger-full-access` allows it). Live-LLM handoffs need `-s danger-full-access`. The bypass flag has nothing to do with spawned-shell network reach.

## Mount-safety checklist

Per-project `docker-compose.yml` declares the agent's reach. Treat every mount as a security decision, not boilerplate.

**Required:**
- The project workspace at a stable path inside the container (`/workspace/<project>` or a host-mirrored path).
- `~/.codex` → `/root/.codex` (trust config + auth state). Without this, the bypass flag becomes the only way to silence prompts — which is exactly what we don't want.

**Per-project decision:**
- `~/.ssh:ro` — required if the project uses git remotes via SSH aliases, or `vm04`-style hosts inside the container. Mount read-only.
- `~/.claude` and `~/.claude.json` — required only if Claude Code runs inside this container. Don't add them speculatively.
- AWS credential env vars (`AWS_ACCESS_KEY_ID`, etc.) — forward only if the project's pipeline calls Bedrock or AWS APIs.
- `CLAUDE_CODE_OAUTH_TOKEN` — only if Claude Code runs inside the container and needs non-interactive auth.

**Never mount:**
- `/` or `~/` (the entire home directory). The bind mount IS the security boundary; mounting the whole home defeats it.
- Anything under `output/` or other expensive pipeline outputs from a sibling project — agent could overwrite them.

**Use named Docker volumes** for `/opt/conda/envs`, `/opt/conda/pkgs`, `/root/.cache/pip`. They make first-run installs persist across container rebuilds and avoid putting build artifacts on the host filesystem.

## Handoff vs interactive

This skill optimizes for **unattended handoff**, not interactive REPL.

- **Handoff (canonical):** detached `codex exec --ephemeral -s danger-full-access` writing to a `-o <report>` file. Approval gating comes from the mounted trust config; sandbox mode is set explicitly per task. The `route_args` `codex)` case in the library passes these through verbatim.
- **Interactive (rare):** `docker compose run --rm agent` drops you into the per-project default CMD (interactive `codex`). Useful for debugging the container itself; for actual interactive coding, use `codex` on the host instead — that's the cheaper, faster path.

## Version-awareness preflight

A project image is derived from a date-tagged base; rebuilding the base does **not** retroactively update existing project images. Before running a container against a project, run:

```bash
/Users/wangyao/claudework/agent-docker/scripts/check-project-base.sh /path/to/project
```

The script reports one of four statuses (default tolerance: 3 days; override with `MAX_AGENT_BASE_AGE_DAYS=N`):

- `current` — proceed.
- `stale-local-base` — newest local base is older than the window. Run `REFRESH=1 bash base/build.sh` (see below), then re-check (the project may now be `stale`).
- `stale` — project pins an older base. Rebuild it against the newest local tag and proceed. Projects vary in how they wire `AGENT_BASE_TAG` (compose `build.args`, Dockerfile `ARG` default, custom build script), so inspect the `Dockerfile` and `docker-compose.yml` to pick the right rebuild path.
- `unable to determine` — project doesn't wire `AGENT_BASE_TAG`. Don't auto-rebuild (the env-var override would be a no-op); inspect the FROM line in `Dockerfile` / `docker-compose.yml` and ask the user.

### Build the base image

Run when the preflight reports `stale-local-base`, or when there's no local image yet:

```bash
cd /Users/wangyao/claudework/agent-docker
bash base/build.sh                                                # codex@latest, claude@latest
REFRESH=1 bash base/build.sh                                      # --pull --no-cache (forces @latest re-resolution)
CODEX_VERSION=0.129.0 CLAUDE_VERSION=2.1.133 bash base/build.sh   # pin specific versions
```

Each build is tagged three ways:

- `agent-base:YYYY-MM-DD` — canonical date tag (what projects pin to)
- `agent-base:YYYY-MM-DD-codex-X.Y.Z-claude-A.B.C` — audit trail of what npm resolved
- `agent-base:latest` — convenience pointer at the most recent build

Projects pin to a date tag, not `:latest` — opting into a newer base means editing one date string in their Dockerfile, on their own schedule.

**After a fresh base build:** every project image pinned to an older date is now out of date. Re-run the preflight in each affected project and follow the `stale` instructions above to rebuild it.

**Prune old base tags.** Keep at most the newest 3 `agent-base:YYYY-MM-DD` builds. The daily launchd job (see README) handles this automatically. If you build manually:

```bash
bash /Users/wangyao/claudework/agent-docker/scripts/prune-old-bases.sh
```

(Override the count with `RETAIN_AGENT_BASE_DATES=N`. The script removes both the `agent-base:DATE` tag and its `agent-base:DATE-codex-X-claude-Y` audit-trail tag for each pruned date.)

## Start a new project

```bash
mkdir -p new-project/docker
cd new-project
cp /Users/wangyao/claudework/agent-docker/templates/Dockerfile         Dockerfile
cp /Users/wangyao/claudework/agent-docker/templates/docker-compose.yml docker-compose.yml
cp /Users/wangyao/claudework/agent-docker/templates/entrypoint.sh      docker/entrypoint.sh

# Fill placeholders. Pick today's date tag for AGENT_BASE_DATE_TAG (or use :latest for casual work):
sed -i '' \
  -e 's|<PROJECT_NAME>|new-project|g' \
  -e 's|<PROJECT_CONDA_ENV>|new-project|g' \
  -e "s|<AGENT_BASE_DATE_TAG>|$(date +%Y-%m-%d)|g" \
  Dockerfile docker-compose.yml docker/entrypoint.sh
chmod +x docker/entrypoint.sh

# Add project-specific apt extras to Dockerfile if needed (uncomment the RUN block).
# Add editable_install_with_hash_stamp triples to docker/entrypoint.sh if your project ships a Python package.

docker compose build
docker compose run --rm agent bash -c 'echo ready && python --version && conda env list'
```

If the smoke run prints `ready`, your conda env is the active one, and python is 3.12.x, the wiring is correct. The next section shows how to actually drive the container for handoff jobs.

## Operational recipes

### Spawned-shell sandbox modes (`-s` flag)

`codex exec` spawns shells under codex's own sandbox. Default is `workspace-write`: writes allowed in cwd and TMPDIR, **network disabled**. So `pytest`, `git`, `pip install -e`, file edits, and conda-only commands work fine — but anything codex spawns that calls a remote API (Bedrock / Anthropic SDK / LiteLLM), pulls from PyPI, or pushes to git will hang or time out.

For unattended jobs that hit the network, switch the mode:

```bash
codex exec -s danger-full-access ...
```

The available modes are `read-only` (diagnosis), `workspace-write` (default; safe for non-network work), and `danger-full-access` (live-LLM, package installs, git push). Mode is per-invocation — a TDD phase with no live calls can use the safer default while a live-LLM smoke uses `danger-full-access`.

`-s danger-full-access` is **not** the same as `--dangerously-bypass-approvals-and-sandbox`. The bypass flag is forbidden (it suppresses approvals and audit). `-s danger-full-access` only widens the spawned-shell sandbox; approvals still resolve against the mounted host trust config.

### Canonical detached-handoff recipe

For unattended handoff (e.g. an `implement-from-doc` phase, an overnight smoke), launch detached with a name and an output file:

```bash
docker compose run -T --interactive=false -d \
  --name <task-name> \
  agent \
  codex exec --ephemeral \
    -s danger-full-access \
    -C /workspace/<project> \
    -o /workspace/<project>/output/<task-name>-report.md \
    "<prompt>"
```

Then poll: `docker wait <task-name>` (blocks until exit), `docker logs <task-name>` for the running narration, read the report file at the `-o` path for the structured result.

For parallel jobs, use distinct `--name` and `-o` per task. Every container gets the full mount set, so any task can edit any file under the workspace — scope prompts accordingly.

`--ephemeral` means no session persistence between handoffs — each task starts context-clean, which is what you want for independent jobs.

### Long prompts via `CODEX_PROMPT` env var

Command-line prompts get unwieldy fast. Pipe via env var instead:

```bash
CODEX_PROMPT="$(cat /path/to/task_prompt.md)" \
docker compose run -T --interactive=false -d \
  --name <task-name> \
  -e CODEX_PROMPT \
  agent \
  codex exec --ephemeral \
    -s danger-full-access \
    -C /workspace/<project> \
    -o /workspace/<project>/output/<task-name>-report.md
```

The library's `route_args` automatically appends `$CODEX_PROMPT` as the prompt when it's set and the command is `codex exec ...` or interactive `codex`. No prompt argument needed on the command line.

### Claude Code auth in the container

If a project runs **Claude Code** (not just codex) inside the container, host-keychain auth doesn't carry across the bind-mount — `~/.claude*` mounts pass through state but on macOS the actual login is in the keychain. You need a long-lived OAuth token:

1. On the host: `claude setup-token` → produces an `sk-ant-oat01-...` token (requires a Claude subscription).
2. Export in your shell rc:
   ```bash
   export CC_AUTH_TOKEN_FOR_LINUX=sk-ant-oat01-...
   ```
3. In `docker-compose.yml`, forward as `CLAUDE_CODE_OAUTH_TOKEN`:
   ```yaml
   environment:
     CLAUDE_CODE_OAUTH_TOKEN: ${CC_AUTH_TOKEN_FOR_LINUX:-}
   ```
   (The template's `docker-compose.yml` has this line commented under "Forward any host env vars".)

Do **not** pass the `oat01` token as `ANTHROPIC_API_KEY`. `claude auth status` will misleadingly report `loggedIn: true` but real requests fail with `Invalid API key`.

## Entrypoint library reference

All four functions live in `/usr/local/lib/agent-docker/entrypoint-lib.sh` (baked into the base image). Source them at the top of your per-project entrypoint:

```bash
source /usr/local/lib/agent-docker/entrypoint-lib.sh
```

### `bootstrap_conda_env <env-name> [python-version]`

Creates the conda env if missing, then activates it. Idempotent. `python-version` defaults to `3.12`. After this returns, `python` and `pip` resolve to the env's binaries.

### `editable_install_with_hash_stamp <state-dir> <stamp-name> [<spec> <dist-name> <norm-name>]...`

For each `(spec, dist-name, norm-name)` triple, runs `pip install -e <spec>`. On failure, uninstalls and removes stale `.dist-info` / `__editable__.<norm-name>-*.pth` files, then retries — this is the CoT repair pattern that handles editable-install corruption from previous failed runs.

Hashes the project metadata files (`pyproject.toml`, `setup.py`, `setup.cfg`, `requirements.txt`) found alongside each spec. If the hash matches the prior run's stamp, skips the install entirely. The stamp file lives at `<state-dir>/<stamp-name>` — typically inside the conda env (`/opt/conda/envs/<env>/.container-state/`) so the stamp's lifetime matches the env's: rebuilding the env wipes the stamp and forces a re-install.

The `dist-name` is what `pip uninstall <dist-name>` expects (PEP 8 lowercased name with hyphens). The `norm-name` is the PEP 503 normalized name used in `.dist-info` and `__editable__.*.pth` filenames (lowercased, hyphens replaced with underscores). For most packages they're the same; differences typically arise from package extras or dotted namespaces.

Requires `bootstrap_conda_env` to have run first.

### `default_codex_cmd <workspace-dir>`

Prints the canonical interactive codex command, one token per line: `codex\n-C\n<workspace-dir>`. Never includes `--dangerously-bypass-approvals-and-sandbox`. Used internally by `route_args`; you generally don't need to call it directly.

### `route_args <workspace-dir> <args...>`

The arg-routing table. Always `exec`s; never returns on success. Use as the last line of your entrypoint: `route_args "${WORKSPACE}" "$@"`.

| Args | Routed to |
|---|---|
| (none) | `default_codex_cmd <workspace>` |
| (none) + `$CODEX_PROMPT` set | `default_codex_cmd <workspace> "$CODEX_PROMPT"` |
| `codex ...` | `exec` verbatim (handoff path: `codex exec ...`) |
| `codex exec ...` + `$CODEX_PROMPT` set | append `$CODEX_PROMPT` as the prompt |
| `bash` / `sh` / `zsh` / `make` / `pytest` / `python` / `python3` | `exec` verbatim |
| `-<flag> ...` | `default_codex_cmd <workspace>` + the flags |
| anything else | `default_codex_cmd <workspace>` + `"$*"` as a single positional prompt |

### Composing in a project entrypoint

```bash
#!/usr/bin/env bash
set -euo pipefail

source /usr/local/lib/agent-docker/entrypoint-lib.sh

CONDA_ENV_NAME="${CONDA_ENV_NAME:-myproject}"
WORKSPACE="${WORKSPACE:-/workspace/myproject}"
STATE_DIR="/opt/conda/envs/${CONDA_ENV_NAME}/.container-state"

bootstrap_conda_env "${CONDA_ENV_NAME}"

editable_install_with_hash_stamp \
  "${STATE_DIR}" python-deps.sha256 \
  "${WORKSPACE}" myproject myproject

# Project-specific bootstrap: config materialization, env exports, etc.
# (e.g. investment writes a config.yaml here with rewritten Mongo URI)

cd "${WORKSPACE}"
route_args "${WORKSPACE}" "$@"
```

Anything more elaborate (config gen, conda-wrapped bash for projects that want auto-activation in `bash -c '...'`, custom validation) lives between `bootstrap_conda_env` and `route_args`. It is *not* in the library — keeping the library minimal makes the four primitives easy to reason about.

## Migrating an existing project

The pattern is additive. Don't migrate critical projects without a parity gate.

1. Build the new base image (`bash base/build.sh`).
2. In a feature branch of the project, replace its Dockerfile with a thin `FROM agent-base:<date>` + project apt extras.
3. Replace the project's entrypoint with the template, plus the project-specific bootstrap calls (config gen, editable install triples).
4. Keep the project's existing `docker-compose.yml` mostly as-is — mount declarations are project-specific security decisions, not boilerplate.
5. **Parity gate before merging:** run an identical `codex exec --ephemeral` smoke task against (a) the project's current image and (b) the new base-image variant. Diff exit codes, report contents, conda env state, and editable-install package versions. Only merge when they match.

For CoT specifically, the canonical reference is commit `b9dd6cf` (the bypass-flag fix). For investment, the entrypoint still ships the bypass flag — the migration should include removing it, not just changing the FROM line.

## Troubleshooting

These are the failure modes that have actually bitten this workflow:

- **Codex broker dies on laptop suspend.** The `codex-companion` broker socket goes stale; jobs report "running" with dead PIDs. Clean `~/.codex/companion/broker.json` and the socket dir, then restart. (Memory: `feedback_codex_broker_dies_on_suspend.md` in the CoT memory tree.)
- **`bash -lc` loses the conda env.** Login shells re-source profiles and reset `PATH`, dropping the activated conda env. Either use `bash -c '...'` (non-login) or `source /opt/conda/etc/profile.d/conda.sh && conda activate <env>` inside the `-lc` script. (Memory: `feedback_codex_docker_conda_path.md`.)
- **Disk near-full corrupts Docker overlay2.** The entrypoint re-runs editable installs (~100 MB) on hash mismatch; with <1 GB free, BuildKit metadata corrupts. Pre-check `diskutil info /` before unattended runs. (Memory: `feedback_codex_docker_disk_full_recovery.md`.)
- **Approval prompt blocks a handoff.** Means the host trust config didn't reach the container. Check that `~/.codex` is mounted at `/root/.codex` and that the project's path is `trust_level = "trusted"` in `~/.codex/config.toml`. **Do not** add the bypass flag as a workaround.

## See also

- `~/.claude/projects/-Users-wangyao-PycharmProjects-CoT/memory/feedback_codex_docker_no_bypass.md` — the canonical no-bypass rule and rationale.
- `/Users/wangyao/PycharmProjects/CoT/docs/tooling/run-agents-in-docker.md` — the per-project doc that this skill generalizes.
- `/Users/wangyao/PycharmProjects/CoT/.claude/skills/implement-from-doc/SKILL.md` — example downstream skill that uses the handoff pattern.
