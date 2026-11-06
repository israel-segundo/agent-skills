# Verify gate resolution (Step 0b)

**The repo's documented command always beats your inference.** Discover from the repo itself;
never assume Node, npm, or any single toolchain.

## Where to look (in order)

```sh
REPO=$(git rev-parse --show-toplevel)

# Agent instructions and contributor docs — highest authority
cat "$REPO/CLAUDE.md" "$REPO/AGENTS.md" 2>/dev/null
cat "$REPO/CONTRIBUTING.md" "$REPO/docs/CONTRIBUTING.md" 2>/dev/null
head -120 "$REPO/README.md" 2>/dev/null

# Build orchestration
[ -f "$REPO/Makefile" ] && grep -E '^[a-zA-Z0-9_.-]+:' "$REPO/Makefile" | head -40
[ -f "$REPO/justfile" ] && head -60 "$REPO/justfile"
[ -f "$REPO/Taskfile.yml" ] && head -60 "$REPO/Taskfile.yml"

# Package scripts (Node and others that use package.json)
[ -f "$REPO/package.json" ] && jq -r '.scripts // {} | keys[]' "$REPO/package.json" 2>/dev/null

# CI — what actually gates merge
ls "$REPO/.github/workflows/" 2>/dev/null
# Read the workflow that runs on pull_request; note container, services, env files

# Repo-local skills may document the gate
ls "$REPO/.claude/skills/" "$REPO/.agents/skills/" 2>/dev/null
```

Also honor **prohibitions**: if docs say never invoke a test runner directly, never start a
local service, or always run inside a container — follow that. The resolved gate must include
the documented wrapper (e.g. `docker compose run …`, `./mvnw`, `nix develop -c …`).

## Resolution priority (first usable match)

1. **Explicit verify command** named in contributor or agent docs — e.g. "run `make verify`",
   "`./scripts/check.sh`", "`ant compile && mvn test` (in container)". Use the exact command
   and environment the doc specifies.

2. **Unified script target** — one target that runs the full pre-merge check:
   - `make verify`, `make check`, `just verify`
   - `npm run verify`, `pnpm verify`, `yarn verify`
   - `./gradlew check`, `mvn -B verify`, `cargo test && cargo clippy`
   - Any single script documented as "run before opening a PR"

3. **Documented sequence** — when docs list separate steps (lint, then type-check, then test),
   run them in that order as one gate. Record the full sequence in the summary.

4. **CI primary job** — when nothing runs locally but CI documents the check, reconstruct the
   job's `run:` steps (including container image and working directory). State clearly that
   the gate is CI-derived.

5. **Marker-based inference** — only when steps 1–4 find nothing. Use the build marker table
   below. Prefer the repo's wrapper (`./mvnw`, `./gradlew`) over a bare tool on `PATH`.

6. **No gate found → stop.** Print that no verification gate could be resolved and do not
   commit anything. Committing unverified fixes is worse than doing nothing.

## Build marker → typical full check

| Marker | Full check | Notes |
|---|---|---|
| `package.json` | `npm run verify` if present; else `lint` + `type-check` + `test` scripts that exist | Never call `jest`, `vitest`, etc. directly — use the npm script |
| `pom.xml` | `mvn -B verify` or doc-specified `ant compile` + `mvn test` | Respect container/doc wrappers |
| `build.gradle`, `build.gradle.kts` | `./gradlew check` | |
| `Cargo.toml` | `cargo test` (+ `clippy` if CI runs it) | |
| `go.mod` | `go test ./...` (+ `golangci-lint run` if documented) | |
| `pyproject.toml`, `tox.ini` | `pytest`, `uv run pytest`, `tox -e lint,test` | Per tox env names |
| `Gemfile` | `bundle exec rspec` (+ rubocop if documented) | |
| `mix.exs` | `mix test` | |
| `Makefile` / `justfile` | `make test`, `make verify`, `just test` | Read target dependencies |
| Terraform, k8s, charts | Often **nothing runnable locally** | Stop unless CI steps are reconstructable |

Record **toolchain pins** (`.nvmrc`, `.tool-versions`, `java.version`, container image) when
the gate depends on them.

## `--fast` mode

When `--fast` is set:

- **Per round:** run only the static-analysis / compile / type-check portions of the resolved
  gate, if the repo separates them (e.g. `npm run lint`, `npm run type-check`, `ant compile`,
  `./gradlew compileJava`, `ruff check .`). If the gate is a single atomic command with no
  scoped subset, skip per-round verify and note that in the round table.
- **Before the final amend:** run the **full** resolved gate once.

## Scoped single-test command (optional)

For fixing one failing test mid-round, discover a single-test invocation from the same sources
(e.g. `mvn -B test -Dtest=Class`, `npm test -- --testPathPatterns=x`, `pytest path::test_name`).
Do not substitute this for the full gate at commit time.
