# Discovery (Steps 1, 4, 7, 8)

Everything this skill needs to know about the repo it's running in, discovered rather than
assumed. Save what you find to `$WORK/profile.md` so later steps read it from disk instead of
from memory.

## The remote and the default branch

**Never assume `origin` or `main`.**

```sh
UPSTREAM=$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
REMOTE=${UPSTREAM%%/*}; REMOTE=${REMOTE:-$(git -C "$REPO" remote | head -1)}
git -C "$REPO" remote set-head "$REMOTE" -a >/dev/null 2>&1 || true   # populate the ref if missing
DEFAULT=$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s|^$REMOTE/||")
[ -n "$DEFAULT" ] || DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
```

The PR's own base branch is more authoritative than either for anything diff-related — take
it from `gh pr view --json baseRefName` and use that.

## The repo's rules

Read the rules the repo states about itself before applying generic practice to it. A
documented rule you can cite is worth more than a preference you can't.

```sh
cat CLAUDE.md AGENTS.md 2>/dev/null                        # agent instructions: highest authority
cat CONTRIBUTING.md docs/CONTRIBUTING.md 2>/dev/null
cat .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null
find . -maxdepth 3 \( -name CLAUDE.md -o -name AGENTS.md \) | grep -v node_modules
```

Capture the commit-message convention, the branch-name convention, whether a trailer is
required on commits, whether a pre-push hook runs checks, and any outright prohibition (a
command never to run, a directory never to touch). A nested instruction file usually carries
the rules for the subsystem the PR actually touches and often overrides the root one on
purpose.

## The verification command

**The repo's documented command always beats your inference.** Check its instruction files
and README first; only fall back to markers. Honor prohibitions — if the docs say never to
invoke the test runner directly, don't.

| Marker | Full check | Single test |
|---|---|---|
| `package.json` | the repo's `verify` / `validate` / `check` script, else `npm test` | `npm test -- --testPathPatterns=<x>` (Jest 30+ is plural; older is `--testPathPattern`) |
| `pom.xml` | `mvn -B verify` | `mvn -B test -Dtest=<Class>` |
| `build.gradle`, `build.gradle.kts` | `./gradlew check` | `./gradlew test --tests '<Class>'` |
| `Cargo.toml` | `cargo test` | `cargo test <name>` |
| `go.mod` | `go test ./...` | `go test ./pkg -run <Name>` |
| `pyproject.toml`, `tox.ini` | `pytest`, `uv run pytest`, `tox` | `pytest path::test_name` |
| `Gemfile` | `bundle exec rspec` | `bundle exec rspec path:LINE` |
| `mix.exs` | `mix test` | `mix test path:LINE` |
| `*.csproj`, `*.sln` | `dotnet test` | `dotnet test --filter <Name>` |
| `composer.json` | `composer test`, `vendor/bin/phpunit` | `phpunit --filter <Name>` |
| `Makefile`, `justfile` | `make test`, `make verify`, `just test` | per the target |
| `*.tf`, `*.tofu`, charts, k8s manifests | **often nothing runnable locally** — CI is the only evidence | — |

List the actual scripts before picking one — never invent a script name:

```sh
jq -r '.scripts | keys[]' package.json 2>/dev/null
```

Note the toolchain pin too (`.nvmrc`, `.tool-versions`, `java.version`, `rust-toolchain`,
`python-version`). A wrong runtime version is the most common cause of a false red.

**Prefer the tool's own project-directory flag over changing directory** — `npm --prefix
"$REPO"`, `git -C "$REPO"`, `mvn -f "$REPO/pom.xml"`, `cargo --manifest-path`. When a tool
has none, run it as one subshell: `( cd "$REPO" && <command> )`.

## The tracker

Find the tracker before you need to file anything.

```sh
grep -rhoE 'https://[A-Za-z0-9-]+\.atlassian\.net' \
  CLAUDE.md AGENTS.md CONTRIBUTING.md README.md .github/ docs/ 2>/dev/null | sort -u
command -v jira acli                      # Jira transports
gh issue list -L 1 >/dev/null 2>&1        # GitHub Issues available?
```

The issue key usually comes from the branch name or the PR body — `[A-Z][A-Z0-9]+-[0-9]+`
for Jira, `#\d+` for GitHub Issues. Watch for key-shaped fragments that aren't tickets
(`UTF-8`, `SHA-256`).

**Transport ladder, in order.** Say which one you used:

1. the `jira` CLI — takes Jira **wiki markup**, and hangs on prompts, so always
   `--template <file> --no-input`,
2. `acli` — takes markdown,
3. a Jira or Atlassian integration the host exposes — takes markdown,
4. `gh issue create` when the repo tracks work in GitHub Issues,
5. **none of the above** — write the ticket body to `$WORK/tickets/` and hand the user the
   exact command. This is a supported outcome, not a failure. What must never happen is a
   deferred finding with nowhere to live.

**Ask the project which issue types it has before creating one.** Type schemes differ per
project, and a type that exists in one doesn't in the next:

```sh
jira issue create --help                                    # lists the configured types
acli jira workitem create --help
```

Pick the closest available type rather than assuming a favourite exists. Same for link
types — check what's configured before asking for `Relates`.

## The plan doc

If the repo keeps a written plan for the work this branch belongs to, declined findings get
recorded there. Find it rather than assuming a path:

```sh
git -C "$REPO" diff --name-only "$REMOTE/$DEFAULT...HEAD" | grep -iE 'plan|spec|design|rfc|adr'
find . -maxdepth 4 -iname 'PLAN.md' -o -maxdepth 4 -iname '*plan*.md' | grep -v node_modules
ls docs/ docs/plans/ specs/ 2>/dev/null
```

Prefer one the branch already touches — that's almost certainly the right document. If the
repo has no such doc, don't create the convention: record the declined items in the PR
description instead, and say that's where they went.

## Bot vs human reviewers

Bots get read but never replied to and never resolved.

Treat a reviewer as a bot when the login ends in `[bot]`, when `.user.type` is `Bot` in the
API payload, or when the name matches a known reviewer bot — `coderabbitai`,
`github-actions`, `copilot`, `dependabot`, `renovate`, `sonarcloud`, `codecov`, `sourcery`,
`greptile`, or an agent's own account. `.github/` config often names the repo's bots:

```sh
ls .github/workflows/ .github/*.yml 2>/dev/null
gh api "repos/{owner}/{repo}/pulls/$PR/comments" --jq '.[] | {login: .user.login, type: .user.type}' | sort -u
```

Read a bot's findings like anyone else's — a valid one gets fixed or ticketed. It just
doesn't get a reply.
