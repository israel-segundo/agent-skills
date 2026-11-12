#!/usr/bin/env bash
# Read-only snapshot of a PR for pr-shepherd: state, head, new feedback since a cutoff,
# and the CI status of the current head. Prints one JSON document on stdout.
#
# Requires: gh (authenticated), jq
# Usage:   scripts/triage.sh [--pr N] [--since ISO8601]
#   --pr     PR number (default: the current branch's PR)
#   --since  cutoff timestamp (default: committer date of the PR's remote head)
#
# "New feedback" = comments created OR updated after the cutoff, excluding the PR author's
# own comments (the shepherd posts as the author, so its replies must not count). Review
# summaries count only when they carry a body or request changes; a bare approval is not
# feedback.
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required" >&2; exit 1; }; }
need gh
need jq

PR=""
SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)    shift; PR="$1" ;;
    --since) shift; SINCE="$1" ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

PRJSON=$(gh pr view ${PR:+"$PR"} --json \
  number,url,state,isDraft,reviewDecision,headRefOid,headRefName,baseRefName,author,mergeable,mergeStateStatus,statusCheckRollup)

# owner/repo from the PR URL (https://<host>/<owner>/<repo>/pull/<n>) — the PR's own repo,
# even when the checkout's remotes point at a fork.
OWNER_REPO=$(jq -r '.url | split("/") | "\(.[3])/\(.[4])"' <<<"$PRJSON")
NUM=$(jq -r .number <<<"$PRJSON")
HEAD=$(jq -r .headRefOid <<<"$PRJSON")
AUTHOR=$(jq -r .author.login <<<"$PRJSON")
[ -n "$SINCE" ] || SINCE=$(gh api "repos/$OWNER_REPO/commits/$HEAD" --jq '.commit.committer.date')

BOT='(.user.type == "Bot") or (.user.login | endswith("[bot]"))'

INLINE=$(gh api --paginate --slurp "repos/$OWNER_REPO/pulls/$NUM/comments" \
  | jq --arg cut "$SINCE" --arg me "$AUTHOR" "[ .[][]
      | select(([.created_at, .updated_at] | max) > \$cut)
      | select(.user.login != \$me)
      | {id, login: .user.login, bot: ($BOT), path, updated_at} ]")

REVIEWS=$(gh api --paginate --slurp "repos/$OWNER_REPO/pulls/$NUM/reviews" \
  | jq --arg cut "$SINCE" --arg me "$AUTHOR" "[ .[][]
      | select(.submitted_at > \$cut)
      | select(.user.login != \$me)
      | select(((.body // \"\") != \"\") or .state == \"CHANGES_REQUESTED\")
      | {id, login: .user.login, bot: ($BOT), state, submitted_at} ]")

ISSUE=$(gh api --paginate --slurp "repos/$OWNER_REPO/issues/$NUM/comments" \
  | jq --arg cut "$SINCE" --arg me "$AUTHOR" "[ .[][]
      | select(([.created_at, .updated_at] | max) > \$cut)
      | select(.user.login != \$me)
      | {id, login: .user.login, bot: ($BOT), updated_at} ]")

jq -n \
  --argjson pr "$PRJSON" \
  --arg ownerRepo "$OWNER_REPO" \
  --arg since "$SINCE" \
  --argjson inline "$INLINE" \
  --argjson reviews "$REVIEWS" \
  --argjson issue "$ISSUE" '
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
  ([ $pr.statusCheckRollup[]? | {
      name: (.name // .context),
      workflow: (.workflowName // ""),
      bucket: bucket,
      url: (.detailsUrl // .targetUrl // "")
    } ]) as $checks
  | ($inline + $reviews + $issue) as $all
  | {
      repo: $ownerRepo,
      number: $pr.number,
      url: $pr.url,
      state: $pr.state,
      isDraft: $pr.isDraft,
      author: $pr.author.login,
      reviewDecision: $pr.reviewDecision,
      mergeable: $pr.mergeable,
      mergeStateStatus: $pr.mergeStateStatus,
      headRefOid: $pr.headRefOid,
      headRefName: $pr.headRefName,
      baseRefName: $pr.baseRefName,
      since: $since,
      feedback: {
        inline: ($inline | length),
        reviews: ($reviews | length),
        issue: ($issue | length),
        human: ([ $all[] | select(.bot | not) ] | length),
        bot: ([ $all[] | select(.bot) ] | length),
        humanLogins: ([ $all[] | select(.bot | not) | .login ] | unique),
        items: (
          [ $inline[]  | {source: "inline", id, login, bot, at: .updated_at} ] +
          [ $reviews[] | {source: "review", id, login, bot, at: .submitted_at} ] +
          [ $issue[]   | {source: "issue",  id, login, bot, at: .updated_at} ]
        )
      },
      checks: {
        total: ($checks | length),
        pass: ([ $checks[] | select(.bucket == "pass") ] | length),
        skip: ([ $checks[] | select(.bucket == "skip") ] | length),
        pending: ([ $checks[] | select(.bucket == "pending") ] | length),
        fail: ([ $checks[] | select(.bucket == "fail" or .bucket == "cancel") ] | length),
        failing: [ $checks[] | select(.bucket == "fail" or .bucket == "cancel") ]
      }
    }'
