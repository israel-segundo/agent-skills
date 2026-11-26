#!/usr/bin/env bash
# Watch one PR in its base branch's merge queue until something happens, for at most
# --max-wait seconds, so a host that caps command duration can call it in a loop.
#
# Every poll reads the PR, its queue entry, and every check on the merge-group commit in one
# GraphQL query. Watching the checks (not only the entry) matters: a merge-group job can fail
# many minutes before the queue marks the entry unmergeable, because the queue waits for the
# aggregate check to finish.
#
# Requires: gh (authenticated), jq
# Usage:   scripts/watch-queue.sh [<pr-number> | <pr-url>] [--repo owner/name]
#                                 [--max-wait 540] [--interval 30] [--hung-after 40]
#   No PR argument: the current branch's PR.
#   --hung-after  minutes a check may stay in progress before it counts as hung
#
# A one-line event goes to stderr each time the queue entry or the check counts change, so a
# background monitor can stream them (run with 2>&1). A JSON snapshot goes to stdout on exit.
#
# Exit codes:
#   0  the PR merged
#   1  at least one check on the merge-group commit failed, was cancelled or timed out
#   5  at least one check has been in progress longer than --hung-after (and none failed)
#   6  the PR is open but not in the queue, with no failed check seen (someone dequeued it,
#      or the queue removed it for a reason that left no failed check)
#   7  the PR is closed without merging
#   8  still waiting when --max-wait ran out; call again
#   2  usage error, or GitHub could not be read three polls in a row
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required" >&2; exit 2; }; }
need gh
need jq

PR_ARG=""; REPO_ARG=""; MAX_WAIT=540; INTERVAL=30; HUNG_AFTER=40
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)       shift; REPO_ARG="${1:-}" ;;
    --max-wait)   shift; MAX_WAIT="${1:-}" ;;
    --interval)   shift; INTERVAL="${1:-}" ;;
    --hung-after) shift; HUNG_AFTER="${1:-}" ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    -*)           echo "unknown arg: $1" >&2; exit 2 ;;
    *)            [ -z "$PR_ARG" ] || { echo "only one PR argument" >&2; exit 2; }; PR_ARG="$1" ;;
  esac
  shift
done
for v in "$MAX_WAIT" "$INTERVAL" "$HUNG_AFTER"; do
  [[ "$v" =~ ^[0-9]+$ ]] || { echo "numeric options only: $v" >&2; exit 2; }
done

URL_RE='^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)'
if [[ "$PR_ARG" =~ $URL_RE ]]; then
  OWNER="${BASH_REMATCH[1]}"; NAME="${BASH_REMATCH[2]}"; NUMBER="${BASH_REMATCH[3]}"
elif [[ "$PR_ARG" =~ ^#?([0-9]+)$ ]]; then
  NUMBER="${BASH_REMATCH[1]}"
  NWO="${REPO_ARG:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
  OWNER="${NWO%%/*}"; NAME="${NWO#*/}"
elif [ -z "$PR_ARG" ]; then
  URL=$(gh pr view ${REPO_ARG:+--repo "$REPO_ARG"} --json url -q .url) \
    || { echo "no PR for the current branch; pass a PR number or URL" >&2; exit 2; }
  [[ "$URL" =~ $URL_RE ]] || { echo "unexpected PR url: $URL" >&2; exit 2; }
  OWNER="${BASH_REMATCH[1]}"; NAME="${BASH_REMATCH[2]}"; NUMBER="${BASH_REMATCH[3]}"
else
  echo "not a PR number or URL: $PR_ARG" >&2; exit 2
fi

QUERY='query($owner:String!,$name:String!,$n:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$n){
      number url state mergedAt isInMergeQueue headRefOid baseRefName
      mergeQueueEntry{
        state position enqueuedAt
        headCommit{
          oid
          statusCheckRollup{
            contexts(first:100){
              pageInfo{ hasNextPage }
              nodes{
                __typename
                ... on CheckRun{
                  name status conclusion startedAt detailsUrl
                  checkSuite{ workflowRun{ databaseId workflow{ name } } }
                }
                ... on StatusContext{ context state targetUrl }
              }
            }
          }
        }
      }
    }
  }
}'

snapshot() {
  gh api graphql -F owner="$OWNER" -F name="$NAME" -F n="$NUMBER" -f query="$QUERY" |
  jq --argjson hungAfter "$HUNG_AFTER" '
    .data.repository.pullRequest as $p
    | ($p.mergeQueueEntry) as $e
    | ($e.headCommit.statusCheckRollup.contexts) as $ctx
    | ([ $ctx.nodes[]? |
        if .__typename == "CheckRun" then {
          name,
          workflow: (.checkSuite.workflowRun.workflow.name // ""),
          runId: (.checkSuite.workflowRun.databaseId // null),
          jobId: (try (.detailsUrl | capture("/job/(?<j>[0-9]+)").j | tonumber) catch null),
          url: (.detailsUrl // ""),
          minutes: (if .startedAt then (((now - (.startedAt | fromdateiso8601)) / 60) | floor) else null end),
          bucket: (if .status != "COMPLETED" then
                     (if .status == "IN_PROGRESS" then "running" else "pending" end)
                   elif .conclusion == "SUCCESS" then "pass"
                   elif (.conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "skip"
                   else "fail" end),
          conclusion: (.conclusion // .status)
        } else {
          name: .context, workflow: "", runId: null, jobId: null, url: (.targetUrl // ""),
          minutes: null,
          bucket: (if (.state == "PENDING" or .state == "EXPECTED") then "pending"
                   elif .state == "SUCCESS" then "pass" else "fail" end),
          conclusion: .state
        } end ]) as $c
    | {
        repo: "\($p.url | capture("github.com/(?<r>[^/]+/[^/]+)/").r)",
        pr: $p.number, url: $p.url, state: $p.state, mergedAt: $p.mergedAt,
        base: $p.baseRefName, prHead: $p.headRefOid,
        inQueue: $p.isInMergeQueue,
        entryState: ($e.state // null), position: ($e.position // null),
        enqueuedAt: ($e.enqueuedAt // null),
        groupSha: ($e.headCommit.oid // null),
        checksTruncated: ($ctx.pageInfo.hasNextPage // false),
        total: ($c | length),
        pending: ([ $c[] | select(.bucket == "pending" or .bucket == "running") ] | length),
        passed: ([ $c[] | select(.bucket == "pass" or .bucket == "skip") ] | length),
        failed: [ $c[] | select(.bucket == "fail") | del(.bucket, .minutes) ],
        hung: [ $c[] | select(.bucket == "running" and .minutes != null and .minutes >= $hungAfter)
                     | del(.bucket) ]
      }'
}

START=$(date +%s)
PREV=""
ERRORS=0
SUMMARY='{}'

while :; do
  if SNAP=$(snapshot 2>/dev/null) && [ -n "$SNAP" ] && [ "$(jq -r .pr <<<"$SNAP")" != null ]; then
    SUMMARY="$SNAP"; ERRORS=0
  else
    ERRORS=$((ERRORS + 1))
    echo "$(date -u +%H:%M:%SZ) could not read the PR (attempt $ERRORS/3)" >&2
    if [ "$ERRORS" -ge 3 ]; then echo "$SUMMARY"; exit 2; fi
    sleep "$INTERVAL"; continue
  fi

  LINE=$(jq -r '"\(.state) queue=\(.entryState // "none") pos=\(.position // "-") checks: \(.passed) passed, \(.pending) running, \(.failed | length) failed, \(.hung | length) hung"' <<<"$SUMMARY")
  if [ "$LINE" != "$PREV" ]; then
    echo "$(date -u +%H:%M:%SZ) #$NUMBER $LINE" >&2
    jq -r '.failed[] | "  FAILED \(.name) (\(.conclusion)) \(.url)"' <<<"$SUMMARY" >&2
    jq -r '.hung[] | "  HUNG \(.name) running \(.minutes) min \(.url)"' <<<"$SUMMARY" >&2
    PREV="$LINE"
  fi

  STATE=$(jq -r .state <<<"$SUMMARY")
  if [ "$STATE" = MERGED ]; then echo "$SUMMARY"; exit 0; fi
  if [ "$STATE" = CLOSED ]; then echo "$SUMMARY"; exit 7; fi
  if [ "$(jq '.failed | length' <<<"$SUMMARY")" -gt 0 ]; then echo "$SUMMARY"; exit 1; fi
  if [ "$(jq '.hung | length' <<<"$SUMMARY")" -gt 0 ]; then echo "$SUMMARY"; exit 5; fi
  if [ "$(jq -r .inQueue <<<"$SUMMARY")" != true ]; then echo "$SUMMARY"; exit 6; fi

  ELAPSED=$(( $(date +%s) - START ))
  if [ $(( ELAPSED + INTERVAL )) -gt "$MAX_WAIT" ]; then echo "$SUMMARY"; exit 8; fi
  sleep "$INTERVAL"
done
