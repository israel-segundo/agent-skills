#!/usr/bin/env bash
# Fetch the authenticated user's open PRs, classify status/action, detect stack
# dependencies, and print one JSON document sorted for morning triage.
#
# Requires: gh (authenticated), jq
# Usage:   scripts/fetch.sh
# Output:  JSON on stdout — { me, fetchedAt, count, prs: [...] }
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required" >&2; exit 1; }; }
need gh
need jq

if ! gh auth status >/dev/null 2>&1; then
  echo "error: gh is not authenticated; run: gh auth login" >&2
  exit 1
fi

QUERY='
query($cursor: String) {
  viewer {
    login
    pullRequests(first: 50, states: OPEN, orderBy: {field: CREATED_AT, direction: ASC}, after: $cursor) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id
        number
        title
        url
        body
        isDraft
        createdAt
        updatedAt
        reviewDecision
        mergeable
        mergeStateStatus
        baseRefName
        headRefName
        repository {
          nameWithOwner
          defaultBranchRef { name }
        }
        reviewRequests(first: 20) {
          nodes {
            requestedReviewer {
              __typename
              ... on User { login }
              ... on Team { combinedSlug name }
            }
          }
        }
        latestReviews(first: 20) {
          nodes {
            state
            submittedAt
            author { login }
          }
        }
        reviews(last: 30) {
          nodes {
            state
            submittedAt
            author { login }
            body
          }
        }
        comments(last: 20) {
          nodes {
            createdAt
            author { login }
          }
        }
        commits(last: 1) {
          nodes {
            commit {
              committedDate
              statusCheckRollup { state }
            }
          }
        }
      }
    }
  }
}'

WORK="$(mktemp -d "${TMPDIR:-/tmp}/my-open-prs.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

: >"$WORK/nodes.jsonl"
CURSOR=""
ME=""
while :; do
  if [ -n "$CURSOR" ]; then
    RESP="$(gh api graphql -f query="$QUERY" -f cursor="$CURSOR")"
  else
    RESP="$(gh api graphql -f query="$QUERY")"
  fi
  echo "$RESP" >"$WORK/page.json"

  if echo "$RESP" | jq -e '.errors? | select(length > 0)' >/dev/null 2>&1; then
    echo "error: GraphQL failed:" >&2
    echo "$RESP" | jq '.errors' >&2
    exit 1
  fi

  ME="$(echo "$RESP" | jq -r '.data.viewer.login')"
  echo "$RESP" | jq -c '.data.viewer.pullRequests.nodes[]' >>"$WORK/nodes.jsonl"

  HAS="$(echo "$RESP" | jq -r '.data.viewer.pullRequests.pageInfo.hasNextPage')"
  CURSOR="$(echo "$RESP" | jq -r '.data.viewer.pullRequests.pageInfo.endCursor // empty')"
  [ "$HAS" = "true" ] || break
done

# Empty set → still emit a valid document
if [ ! -s "$WORK/nodes.jsonl" ]; then
  jq -n --arg me "$ME" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{me:$me, fetchedAt:$at, count:0, prs:[]}'
  exit 0
fi

jq -s --arg me "$ME" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  # ── helpers ──────────────────────────────────────────────────────────
  def age_days:
    ((now - (fromdateiso8601)) / 86400) | floor;

  def reviewers_requested:
    [.reviewRequests.nodes[]?
      | .requestedReviewer
      | if .__typename == "User" then .login
        elif .__typename == "Team" then (.combinedSlug // .name)
        else empty end];

  def other_reviews($me):
    [.latestReviews.nodes[]? | select(.author.login != $me)];

  def last_commit_at:
    .commits.nodes[0].commit.committedDate // .createdAt;

  def ci_state:
    .commits.nodes[0].commit.statusCheckRollup.state // "UNKNOWN";

  def feedback_after_push($me; $push):
    # Non-author reviews (COMMENTED / CHANGES_REQUESTED) or issue comments after last push
    ( [.reviews.nodes[]?
        | select(.author.login != $me)
        | select(.state == "COMMENTED" or .state == "CHANGES_REQUESTED")
        | select(.submittedAt > $push)]
      + [.comments.nodes[]?
        | select(.author.login != $me)
        | select(.createdAt > $push)]
    ) | length > 0;

  def classify($me):
    . as $pr
    | ($pr | last_commit_at) as $push
    | ($pr | ci_state) as $ci
    | ($pr.reviewDecision // "NONE") as $rd
    | ($pr.mergeable // "UNKNOWN") as $mg
    | if $pr.isDraft then
        {status:"Draft", action:"Finish and mark ready for review"}
      elif $mg == "CONFLICTING" then
        {status:"Conflicted", action:"Rebase / resolve conflicts"}
      elif $rd == "CHANGES_REQUESTED" then
        {status:"Changes requested", action:"Address review feedback"}
      elif ($pr | feedback_after_push($me; $push)) and $rd != "APPROVED" then
        {status:"Feedback received", action:"Address review comments"}
      elif $rd == "APPROVED" then
        if $ci == "FAILURE" or $ci == "ERROR" then
          {status:"Approved", action:"Fix failing CI"}
        elif $ci == "PENDING" or $ci == "EXPECTED" then
          {status:"Approved", action:"Wait for CI, then merge"}
        elif $mg == "MERGEABLE" then
          {status:"Approved", action:"Ready to merge"}
        else
          {status:"Approved", action:"Approved — check merge blockers"}
        end
      elif $ci == "FAILURE" or $ci == "ERROR" then
        {status:"Awaiting review", action:"Fix failing CI (reviewers may wait)"}
      else
        ($pr.createdAt | age_days) as $age
        | if $age >= 3 then
            {status:"Awaiting review", action:"Waiting on reviewers — consider nudging (\($age)d old)"}
          else
            {status:"Awaiting review", action:"Waiting on reviewers"}
          end
      end;

  # ── normalize raw nodes ──────────────────────────────────────────────
  ($me) as $me
  | map(
      . as $raw
      | ($raw | classify($me)) as $cls
      | {
          id: $raw.id,
          repo: $raw.repository.nameWithOwner,
          number: $raw.number,
          title: $raw.title,
          url: $raw.url,
          body: ($raw.body // ""),
          isDraft: $raw.isDraft,
          createdAt: $raw.createdAt,
          updatedAt: $raw.updatedAt,
          ageDays: ($raw.createdAt | age_days),
          base: $raw.baseRefName,
          head: $raw.headRefName,
          defaultBranch: ($raw.repository.defaultBranchRef.name // "main"),
          reviewDecision: ($raw.reviewDecision // "NONE"),
          mergeable: ($raw.mergeable // "UNKNOWN"),
          mergeStateStatus: ($raw.mergeStateStatus // "UNKNOWN"),
          ci: ($raw | ci_state),
          lastCommitAt: ($raw | last_commit_at),
          reviewRequests: ($raw | reviewers_requested),
          latestReviews: [ $raw.latestReviews.nodes[]? | {state, author: .author.login, at: .submittedAt} ],
          status: $cls.status,
          action: $cls.action
        }
    ) as $prs

  # ── stack dependencies (same-repo: base == another open PR head) ─────
  | (
      reduce $prs[] as $p ({};
        .[$p.repo + "\t" + $p.head] = {repo:$p.repo, number:$p.number, url:$p.url, title:$p.title}
      )
    ) as $by_head

  | ($prs | map(
      . as $p
      | if $p.base != $p.defaultBranch then
          ($by_head[$p.repo + "\t" + $p.base] // null) as $dep
          | if $dep != null then
              .dependsOn = [{repo:$dep.repo, number:$dep.number, url:$dep.url, title:$dep.title, kind:"stack"}]
            else
              .dependsOn = [{repo:$p.repo, number:null, url:null, title:("branch " + $p.base), kind:"stack-branch"}]
            end
        else
          .dependsOn = []
        end
    )) as $with_stack

  # ── body / title references to other open PRs of mine ────────────────
  # Matches: owner/repo#N, #N (same-repo context weak — only when unique),
  # full PR URLs, and "depends on … #N" phrases.
  | (
      reduce $with_stack[] as $p ({};
        .[$p.repo + "#" + ($p.number|tostring)] = $p
        | .["url:" + $p.url] = $p
      )
    ) as $by_key

  | ($with_stack | map(
      . as $p
      | (
          [ ($p.body + "\n" + $p.title)
            | scan("https://github[.]com/([^/]+/[^/]+)/pull/([0-9]+)")
            | {repo:.[0], number:(.[1]|tonumber)}
          ]
          + [ ($p.body + "\n" + $p.title)
            | scan("([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)")
            | {repo:.[0], number:(.[1]|tonumber)}
          ]
        ) as $refs
      | (
          $refs
          | map(select(.repo + "#" + (.number|tostring) != ($p.repo + "#" + ($p.number|tostring))))
          | map(. as $r | $by_key[$r.repo + "#" + ($r.number|tostring)] // empty)
          | unique_by(.repo + "#" + (.number|tostring))
          | map({repo:.repo, number:.number, url:.url, title:.title, kind:"mentioned"})
        ) as $mentioned
      | .dependsOn = (
          (.dependsOn + $mentioned)
          | unique_by((.kind // "") + "|" + (.repo // "") + "#" + ((.number // 0)|tostring) + "|" + (.title // ""))
        )
      | del(.body)   # drop body from final payload — was only for parsing
    )) as $enriched

  # ── sort: no-deps first, then by age (oldest first); deps after deps ─
  # Kahn-style: repeatedly emit ready nodes (dependsOn open-PR numbers all emitted),
  # oldest-first among ready. Mentions of stack-branch (no number) do not block.
  | (
      $enriched
      | map(.key = (.repo + "#" + (.number|tostring)))
    ) as $nodes
  | (
      reduce $nodes[] as $n ({};
        .[$n.key] = (
          [$n.dependsOn[]? | select(.number != null) | .repo + "#" + (.number|tostring)]
          | unique
        )
      )
    ) as $deps
  | (
      # only keep deps that are actually in the open set
      reduce ($deps | keys[]) as $k ({};
        .[$k] = [ $deps[$k][]? | select($deps[.] != null) ]
      )
    ) as $deps
  | (
      def sort_keys($keys):
        ($nodes | map(select(.key as $k | $keys | index($k) != null)))
        | sort_by(.createdAt)
        | map(.key);

      def kahn($remaining; $done):
        if ($remaining | length) == 0 then $done
        else
          ($remaining | map(select(
            ($deps[.] | map(select($done | index(.) == null)) | length) == 0
          ))) as $ready
          | if ($ready | length) == 0 then
              # cycle / unresolved — append remaining oldest-first and stop
              $done + sort_keys($remaining)
            else
              (sort_keys($ready)) as $emit
              | kahn(
                  ($remaining - $emit);
                  $done + $emit
                )
            end
        end;

      kahn(($nodes | map(.key)); [])
    ) as $order

  | (
      $nodes
      | map(. as $n | .order = ($order | index($n.key)))
      | sort_by(.order)
      | map(del(.key, .order, .defaultBranch, .head, .updatedAt))
      | map(
          # human-readable dependsOn summary
          .dependsOnSummary =
            ( if (.dependsOn | length) == 0 then "—"
              else
                [.dependsOn[]
                  | if .number != null then "\(.repo)#\(.number)"
                    else .title end]
                | join(", ")
              end
            )
        )
    ) as $sorted

  | {
      me: $me,
      fetchedAt: $at,
      count: ($sorted | length),
      prs: $sorted
    }
' "$WORK/nodes.jsonl"
