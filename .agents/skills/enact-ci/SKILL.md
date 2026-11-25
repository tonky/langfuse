---
name: enact-ci
description: Expert instructions for AI coding agents to discover, compile, validate, dry-run, execute, test, and transpile declarative CI/CD pipelines and zero-docker services with enact and enve.
---

# enact AI Agent Guidelines

## 1. Toolchain Invocation Protocol
- **`enact` calls `enve` under the hood**: always invoke `enact` directly (`enact run`, `enact plan`, `enact ci matrix`, `enact reach`). Never wrap `enact` in `enve run -- enact`.
- **Run external tools inside `enve`**: compilers, test runners and package managers (`cargo test`, `pytest`, `uv`, `just`) run via `enve run -- <cmd>`.
- **Never execute raw repository toolchains directly against the host shell.** All dependencies and tools execute within the hermetic `enve` environment.

## 2. Daemonless & Zero-Docker Execution
- **Never spin up Docker, Docker Compose, Podman, or container runtimes for development services or CI tests.**
- Microservices execute rootless in user space with loopback networking (`127.0.0.1`).
- `enact` and `enve` operate daemonless: no `nix-daemon` or Docker daemon required.

## 3. Two-Binary Discovery & Execution Protocol (`enve` + `enact`)
When starting in any repository equipped with `enve` and `enact`, keep inspection separate from execution and file generation (see `enact handbook commands` for the full command-effects table):
- **Inspect & Plan (does not execute pipeline jobs; may run `components_discovery` helpers or pull remote reach maps into the local reach store)**:
  1. Read the schemas and readiness: `enact agent schema`, `enve agent schema`, and `enact setup --check`
  2. Preview the pipeline execution DAG: `enact plan`
  3. Check affected components & CAS cache status: `enact ci matrix`
  4. Verify pipeline contracts and workflow drift: `enact check` and `enact ci generate --check`
- **Execute & Generate (mutates run state or tracked workflow files when requested)**:
  5. Run a targeted component: `enact run <component>` (reserve `enact run --all` for an explicit whole-pipeline request)
  6. Inspect execution traces: `enact runs inspect <run-id>`
  7. Regenerate GitHub Actions workflows after `.enact/*.cue` edits: `enact ci generate`

## 4. Key Agent Commands
- `enact check`                            : Pre-push 5-phase clean-room local CI check
- `enact check -f <files...>`              : Check CI execution for specific pull request diffs
- `enact check --strict`                   : Strict check (treat warnings/unmapped files as errors)
- `enact plan`                             : Preview topological execution DAG without executing pipeline jobs (`--github-output <file>` writes `stage_has_work` to `<file>`)
- `enact plan --pr`                        : Plan the whole feature branch as its PR: merge base with the default branch (`--base <ref>` to name another) to the work tree; `enact run --pr` runs it
- `enact explain <component>`              : Final planner and target selection verdicts, with reasons
- `enact ci matrix`                        : Transitive blast radius analysis from git diff
- `enact ci matrix --updated <comp>`       : Simulate blast radius from updated components
- `enact ci matrix --format json`          : Output GitHub Actions matrix with CAS filtering
- `enact run <component>`                  : Execute targeted component in user space
- `enact run <comp>:<job>`                 : Execute specific job (e.g. `api:test`)
- `enact run --all`                        : Run all components
- `enact run --rerun`                      : Bypass task/target result reuse while keeping installs and key-matching `#Job.outputs`
- `enact run --no-cache`                   : Bypass result reuse, rebuild declared `#Job.outputs`, and rerun current `prepare` installs
- `enact runs report --dir .enact/state/telemetry` : Render consolidated terminal report & HTML dashboard
- `enact runs inspect <run-id>`            : Render OpenTelemetry waterfall diagram
- `enact reach explain <file>`             : Which test targets cover a source file, through which functions or probes (`-f <map>`)
- `enact reach covers <test>`              : Which production files and functions a test target covers (`-f <map>`)
- `enact reach why <target>`               : Raw reach-map evidence linking a test to the diff (`-f <map>`, `--diff <patch>`)
- `enact reach stale`                      : Tests that need a new trace (`--explain` for aging/staleness reasons)
- `enact reach map --summary`              : Fast overview of a reach map (`enact reach map <file>`, `--target <pattern>`, `--service <name>`, `--path <substr>`, `--outcome <kind>`, `--suite <suite>`, `--suiteless`, `--keys`, `--diff <other.bin>`, `--json`)
- `enact reach audit <target>`             : Audit one target's or service's (`--service <name>`) reach footprint (`--format json`)
- `enact reach store where`                : Which reach map planning reads (the reach store's, at an ancestor of HEAD)
- `enact ci generate`                      : Generate the GitHub Actions workflows from the pipeline
- `enact ci generate --check`              : Fail when the committed workflows differ from the generated ones
- `enact handbook all`                     : Built-in agent reference handbook

## 5. Content-Addressable Caching (CAS)
- Task keys are computed with BLAKE3 over git tree hash, toolchain hash, upstream task keys, and commands.
- Local cache is stored in `.enact/state/cache/`. An opt-in remote cache (`ENACT_R2_BUCKET` locally; `ci.remote_cache` in generated CI) syncs to Cloudflare R2 / S3 via SigV4.
- In CI matrix generation, cached tasks are automatically pruned, allocating 0 runner VMs!

## 6. Service Blueprints & Lifecycle
- Standard blueprints (`postgres`, `redis`, `kafka`, `clickhouse`, `seaweedfs`, `temporal`) require zero boilerplate.
- Services start in topological dependency order and are shared across consuming components.
- **Agent Rule**: Never run client commands (`psql`, `rpk`, `aws`) in `init` or `preStart`. Always use `postStart` when sockets are live!
- **Service instances (`pipeline.service_instances`)**: `"per_run"` (default) runs each `enact run`'s services in an enve instance of its own (`enact-<n>`) on free ports, so concurrent runs, checkouts and machines never collide. It needs ports read from the environment: `$PORT`/`$PORT_<KEY>` in service commands, hooks and probes, `${ENVE_SERVICE_<NAME>_PORT}` in env values and tasks; a literal port is `SERVICE_PORT_COLLISION`. Use `"declared"` only for repositories whose code or tests hardcode ports: services run on the declared ports in enve's default instance, and a checkout's runs take turns (`⏳ Waiting for this checkout's services`, a `Wait for services` trace step, `ENACT_SERVICE_QUEUE_TIMEOUT_SECS`); matrix shards on one host serialize on them (check: `SERVICE_INSTANCES_DECLARED`, info).

## 7. Onboarding & Gap-Fixing Loop
- Run `enact init` (or turnkey `enact onboard`) to discover packages, ingest CI workflows, emit `.enact/*.cue`, and report any onboarding gaps.
- Resolve reported gaps (unclassified CI steps, expression commands or toolchains, unknown service images, cycle-closing watch paths) in `.enact/components.cue` and `.enact/services.cue`.
- Audit repository file ownership with `enact audit unmapped` so every tracked file belongs to a component or `workspace_scope.ignore`.
- Verify inter-component dependency cones with `enact deps check` or discover missing edges with `enact deps discover`.
- Validate workflow contracts, matrix blast radius, sparse cones, and cache globs with `enact check`.
- Record initial reachability traces across test suites with `enact reach sample -n 3`.

## 8. CI Workflow Transpilation & Caching Invariants
- **Scoped Cache Isolation**: When transpiling matrix test jobs with task-scoped caches (`${matrix.task_id}`), never add the stage cache prefix to `restore-keys`. Keep restore keys strictly scoped to `{key_prefix}-` to avoid multi-hundred-MB redundant cache downloads.
- **Dynamic Host Sizing in CI**: CI runs default to the measured host's profile, using every vCPU and the RAM of the runner rather than throttling to 2 vCPUs.
- **Dynamic Test Runner Workers**: Monorepo test runners (e.g. Vitest) must dynamically size workers: `MAX_WORKERS="${MAX_WORKERS:-${ENACT_SHARD_WORKERS:-$(nproc 2>/dev/null || echo 2)}}"`.
- **Zero-Host Direct Invocation in Workflow Steps**: In generated GitHub Actions steps, any repository script or tool invocation must be prefixed with `$RUN_PREFIX` (`enve run $([ -f enve.lock ] && echo --locked) -- `) so it runs under the hermetic toolchain.
- **Database Template Cache Targeting**:
  - Cache key `hashFiles()` patterns must point to real migration paths (e.g. `packages/db/src/migrations/**`).
  - Target DB template caches to the components that use them: SQLite templates belong to Playwright/E2E test jobs; PostgreSQL snapshots belong to backend services/tests.
- **One install, CI and local**: Put the once-before-tasks install in `toolchain.<eco>.install` (without one, the package manager's frozen install runs). In CI it runs as the install step. Locally, the prepare phase of `enact run` runs it once, before services and shards, under a checkout lock. It skips it while the inputs are unchanged and the `outputs` exist. Declare in `toolchain.<eco>.outputs` what a custom install leaves (e.g. its own stamp file), so a deleted one reinstalls. Don't provision the same thing again in shard scripts or wrap it in per-shard locks. Per-shard locks are only for what a task installs itself (a downloaded database, a sub-workspace's node_modules).
- **Reach maps live in the reach store, never in git**: planning takes the newest stored map at an ancestor of HEAD (local tier `.git/enact/reach`, the CI cache, R2 with `ci.remote_cache`), ages it and lays the local layer over it; stderr says which (`🗺️  Reach map: …`). No map means every reach-scoped test runs (check: `REACH_MAP_ABSENT`, info). Only default-branch pushes write the shared tiers (the generated `reach` job). Record with `enact reach record`/`enact reach pack` without `-o` (into the local tier), `enact reach store put <map>` to seed one, `ENACT_REACH_FILE` to pin one. Don't commit `.enact/trace-reach.bin` or add a map to `workspace_scope`.
- **Component Scope Fencing**: Component `target_scope.rules` must strictly match files within the component's package root to prevent cross-component scope contamination and duplicate linting.

## 9. Local Pre-Push CI Check (`enact check`)
- **MANDATORY PRE-PUSH GATE**: Before pushing pull requests or changes to CI, agents MUST run `enact check` locally.
- **The 5 Check Phases**:
  1. *Phase 1 (Scope Audit)*: Verifies all changed files map to `#Component` watch paths or root ignores (`CHANGESET_UNMAPPED_FILE`).
  2. *Phase 2 (AST Linting)*: Validates transpiled workflow ASTs against GitHub Actions schemas and action pinning invariants.
  3. *Phase 3 (State Machine & Blast Radius)*: Simulates event triggers, prunes unaffected modules via trace reach, enforces worker CPU headroom (`SERVICE_CPU_STARVATION_RISK`), and audits monorepo inter-component build ordering (`INTER_COMPONENT_BUILD_ORDER_HAZARD`).
  4. *Phase 4 (Polyglot Sparse Cones)*: Creates isolated ephemeral clean rooms omitting ambient host artifacts (`node_modules`, `.venv`, `target`), auditing Cargo/Go dependencies, package manifests, toolchains/helpers (`SPARSE_CONE_MISSING_*`), and database template installed module coverage.
  5. *Phase 5 (Cache & Hermeticity)*: Evaluates all `hashFiles(...)` globs against the filesystem, validates service loopback ports (`SERVICE_PORT_COLLISION`), verifies Unix executable permissions on lifecycle scripts and hooks (`SERVICE_SCRIPT_NOT_EXECUTABLE`, `HOOK_SCRIPT_NOT_EXECUTABLE`), and audits non-interactive Corepack settings (`COREPACK_INTERACTIVE_HANG_RISK`).
