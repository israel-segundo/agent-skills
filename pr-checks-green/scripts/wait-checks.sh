#!/usr/bin/env bash
# Wait for a PR's checks on a specific commit to finish, for at most --max-wait seconds,
# so a host that caps command duration can call it in a loop. Head SHA and checks are read
# in one query, so a stale head can never be mistaken for the commit you pushed.
#
# Requires: gh (authenticated), jq
# Usage:   scripts/wait-checks.sh <sha> [--pr N] [--max-wait 540] [--interval 30] [--grace 180]
#   --grace  how long to tolerate "PR head is not <sha> yet" or "no checks reported yet"
#            before giving up on it (GitHub takes a moment to register both after a push)
#
# Exit codes (a JSON summary of the checks is always printed on stdout):
#   0  every check passed or was skipped
#   1  at least one check failed or was cancelled (all others finished)
#   3  no checks reported for <sha> within --grace (the repo may have no CI)
#   4  the PR head is a different commit than <sha> after --grace (someone else pushed)
#   8  still pending when --max-wait ran out; call again
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required" >&2; exit 1; }; }
need gh
need jq

SHA="${1:-}"; [ -n "$SHA" ] || { echo "usage: $0 <sha> [--pr N] [--max-wait S] [--interval S] [--grace S]" >&2; exit 2; }
shift
PR=""; MAX_WAIT=540; INTERVAL=30; GRACE=180
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)       shift; PR="$1" ;;
    --max-wait) shift; MAX_WAIT="$1" ;;
    --interval) shift; INTERVAL="$1" ;;
    --grace)    shift; GRACE="$1" ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

START=$(date +%s)
SUMMARY='{}'

snapshot() {
  gh pr view ${PR:+"$PR"} --json headRefOid,statusCheckRollup | jq --arg sha "$SHA" '
    def bucket:
      if .__typename == "CheckRun" then
        if .status != "COMPLETED" then "pending"
        elif .conclusion == "SUCCESS" then "pass"
        elif (.conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "skip"
        elif .conclusion == "CANCELLED" then "cancel"
        else "fail" end
      else
        if (.state == "PENDING" or .state == "EXPECTED") then "pending"
        elif .state == "SUCCESS" then "pass"
        else "fail" end
      end;
    ([ .statusCheckRollup[]? | {
        name: (.name // .context), workflow: (.workflowName // ""),
        bucket: bucket, url: (.detailsUrl // .targetUrl // "") } ]) as $c
    | {
        sha: $sha,
        head: .headRefOid,
        headMatches: (.headRefOid == $sha),
        total: ($c | length),
        pending: ([ $c[] | select(.bucket == "pending") ] | length),
        failed: [ $c[] | select(.bucket == "fail" or .bucket == "cancel") ],
        passed: ([ $c[] | select(.bucket == "pass" or .bucket == "skip") ] | length)
      }'
}

while :; do
  SUMMARY=$(snapshot)
  ELAPSED=$(( $(date +%s) - START ))

  if [ "$(jq -r .headMatches <<<"$SUMMARY")" != true ]; then
    if [ "$ELAPSED" -ge "$GRACE" ]; then echo "$SUMMARY"; exit 4; fi
  elif [ "$(jq -r .total <<<"$SUMMARY")" -eq 0 ]; then
    if [ "$ELAPSED" -ge "$GRACE" ]; then echo "$SUMMARY"; exit 3; fi
  elif [ "$(jq -r .pending <<<"$SUMMARY")" -eq 0 ]; then
    echo "$SUMMARY"
    [ "$(jq -r '.failed | length' <<<"$SUMMARY")" -eq 0 ] && exit 0 || exit 1
  fi

  if [ $(( ELAPSED + INTERVAL )) -gt "$MAX_WAIT" ]; then echo "$SUMMARY"; exit 8; fi
  sleep "$INTERVAL"
done
