#!/usr/bin/env bash
# Summarize why one failed GitHub Actions job failed, so the caller can classify it.
# Prints three sections: the failing tests it can recognize, the infrastructure signatures it
# found, and the first error lines. It never decides "flaky"; that needs evidence from other
# runs (see references/diagnose.md).
#
# Requires: gh (authenticated)
# Usage:   scripts/failure-summary.sh <run-id> <job-id> [--repo owner/name] [--save FILE]
#          scripts/failure-summary.sh <job-url> [--save FILE]
#   --save  also keep the full failed-step log in FILE
#
# Exit codes: 0 summary printed · 2 usage error · 3 log not readable (expired, still running,
# or not a GitHub Actions job)
set -euo pipefail

command -v gh >/dev/null 2>&1 || { echo "error: 'gh' is required" >&2; exit 2; }

RUN=""; JOB=""; REPO_ARG=""; SAVE=""
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) shift; REPO_ARG="${1:-}" ;;
    --save) shift; SAVE="${1:-}" ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) echo "unknown arg: $1" >&2; exit 2 ;;
    *) POS+=("$1") ;;
  esac
  shift
done

JOB_URL_RE='^https://github\.com/([^/]+/[^/]+)/actions/runs/([0-9]+)/job/([0-9]+)'
if [ "${#POS[@]}" -eq 1 ] && [[ "${POS[0]}" =~ $JOB_URL_RE ]]; then
  REPO_ARG="${BASH_REMATCH[1]}"; RUN="${BASH_REMATCH[2]}"; JOB="${BASH_REMATCH[3]}"
elif [ "${#POS[@]}" -eq 2 ]; then
  RUN="${POS[0]}"; JOB="${POS[1]}"
else
  echo "usage: $0 <run-id> <job-id> [--repo owner/name] | <job-url>" >&2; exit 2
fi

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
NWO="${REPO_ARG:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
# The jobs API serves a finished job's log while the rest of its run is still going, which is
# exactly when a merge-group failure needs reading; `gh run view --log` waits for the whole run.
if ! gh api --allow-escape-sequences "repos/$NWO/actions/jobs/$JOB/logs" >"$TMP" 2>/dev/null \
   || [ ! -s "$TMP" ]; then
  gh run view "$RUN" --job "$JOB" --repo "$NWO" --log-failed >"$TMP" 2>/dev/null || true
  [ -s "$TMP" ] || gh run view "$RUN" --job "$JOB" --repo "$NWO" --log >"$TMP" 2>/dev/null || true
fi
[ -s "$TMP" ] || { echo "log not readable for run $RUN job $JOB (still running, expired, or not an Actions job)" >&2; exit 3; }

# Drop the line prefix (the jobs API writes "<timestamp> "; gh run view writes
# "<job>\t<step>\t<timestamp> "). Then drop the step scripts GitHub echoes in cyan
# (`[36;1m`, as a literal "^[" or as the ESC byte): they are source, not events, and their
# error-handling branches would otherwise match the signatures below. NUL bytes (some steps
# print them) are dropped too, or grep treats the whole log as binary and prints nothing.
CLEAN=$(tr -d '\000' <"$TMP" \
  | sed -E 's/^[^\t]*\t[^\t]*\t//; s/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z ?//; s/[[:space:]]+$//' \
  | grep -v -E '^(\^\[|'$'\e'')\[36;1m' || true)
[ -n "$SAVE" ] && printf '%s\n' "$CLEAN" >"$SAVE"

echo "== Failing tests"
{
  # Playwright list reporter: "  ✘  12 [project] › path/spec.ts:42:3 › Suite › title"
  grep -E '^\s*✘' <<<"$CLEAN" | sed -E 's/^\s*✘\s+[0-9]+\s+//; s/ \(retry #[0-9]+\)//; s/ \([0-9.]+m?s\)$//'
  # Playwright failure headers: "  1) [project] › path/spec.ts:42:3 › ..."
  grep -E '^\s*[0-9]+\) \[[^]]+\] › ' <<<"$CLEAN" | sed -E 's/^\s*[0-9]+\) //'
  # Jest: "FAIL path/to/file.test.ts" and "● Suite › title"
  grep -E '^\s*FAIL\s+\S+' <<<"$CLEAN" | sed -E 's/^\s*//'
  grep -E '^\s*● ' <<<"$CLEAN" | grep -v '● Console' | sed -E 's/^\s*//'
  # pytest, go test
  grep -E '^FAILED |^--- FAIL: ' <<<"$CLEAN"
} | awk '!seen[$0]++' | head -40 || true

echo
echo "== Infrastructure signatures"
grep -n -i -E \
  'runner has received a shutdown signal|lost communication with the server|The operation was canceled|No space left on device|exit code 137|Killed$|out of memory|OOMKilled|ECONNRESET|ETIMEDOUT|EAI_AGAIN|socket hang up|429 Too Many Requests|rate limit|secondary rate|Error response from daemon|failed to (pull|download)|Unable to (resolve|download)|503 Service Unavailable|502 Bad Gateway|exceeded the maximum execution time|watchdog.{0,40}(fired|kill|expired|exceeded)|Emulators? failed to start|Timed out waiting|Test timeout of [0-9]+ms exceeded|globalTimeout' \
  <<<"$CLEAN" | awk '!seen[$0]++' | head -20 || true

echo
echo "== First error lines"
grep -n -E '##\[error\]|Error:|^\s*(Expected|Received)( value)?:|AssertionError|Traceback' <<<"$CLEAN" | head -25 || true
