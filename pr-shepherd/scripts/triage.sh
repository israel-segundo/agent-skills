#!/usr/bin/env bash
# Read-only snapshot of a PR for pr-shepherd: state, head, new feedback since a cutoff,
# the CI status of the current head, and whether the head still merges cleanly into the
# latest base. Prints one JSON document on stdout.
#
# Conflicts: GitHub's `mergeable` goes stale (it stays MERGEABLE for a while after the base
# moves, and longer while the PR sits in a merge queue), so when run inside a checkout of the
# PR's repo this script also fetches the base and test-merges with `git merge-tree`. The
# fetch updates remote-tracking refs only; the working tree and branches are untouched.
# `conflicting` is true when either GitHub or the local test-merge says so.
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
BASE=$(jq -r .baseRefName <<<"$PRJSON")
[ -n "$SINCE" ] || SINCE=$(gh api "repos/$OWNER_REPO/commits/$HEAD" --jq '.commit.committer.date')

# Local test-merge of the PR head into the freshly fetched base (git >= 2.38).
local_merge() {
  local remote base_oid out rc
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { jq -n '{checked:false, reason:"not in a git checkout"}'; return; }
  remote=$(git remote -v | awk -v r="$OWNER_REPO" '$2 ~ ("[:/]" r "(\\.git)?/?$") {print $1; exit}')
  [ -n "$remote" ] || { jq -n --arg r "$OWNER_REPO" '{checked:false, reason:("no remote points at " + $r)}'; return; }
  git fetch -q "$remote" "$BASE" 2>/dev/null || { jq -n '{checked:false, reason:"fetch of the base failed"}'; return; }
  base_oid=$(git rev-parse FETCH_HEAD)
  if ! git cat-file -e "$HEAD^{commit}" 2>/dev/null; then
    git fetch -q "$remote" "refs/pull/$NUM/head" 2>/dev/null || { jq -n '{checked:false, reason:"PR head not available locally"}'; return; }
  fi
  rc=0; out=$(git merge-tree --write-tree --name-only --no-messages "$base_oid" "$HEAD" 2>&1) || rc=$?
  case $rc in
    0) jq -n --arg b "$base_oid" '{checked:true, baseOid:$b, conflict:false, files:[]}' ;;
    1) jq -n --arg b "$base_oid" --arg f "$(tail -n +2 <<<"$out")" \
         '{checked:true, baseOid:$b, conflict:true, files:($f | split("\n") | map(select(length > 0)) | unique)}' ;;
    *) jq -n --arg e "$out" '{checked:false, reason:("git merge-tree failed: " + $e)}' ;;
  esac
}
LOCAL_MERGE=$(local_merge)

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
  --argjson issue "$ISSUE" \
  --argjson localMerge "$LOCAL_MERGE" '
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
      localMerge: $localMerge,
      conflicting: ($pr.mergeable == "CONFLICTING" or ($localMerge.conflict // false)),
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
