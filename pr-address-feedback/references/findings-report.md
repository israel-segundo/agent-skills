# The findings report, the replies, and the thread mechanics (Steps 5, 10)

Two outputs: the **local HTML report** that is the confirmation gate and then the living
record of what happened, and the **replies** posted on each human thread once the work is
done. `$WORK/findings.md` stays the source of truth; the HTML is a view of it.

## The local HTML report

Write a self-contained `.html` to `$WORK` and open it with whatever the host has — always
falling back to printing the path:

```sh
html="$WORK/findings.html"
open "$html" 2>/dev/null || xdg-open "$html" 2>/dev/null || wslview "$html" 2>/dev/null \
  || echo "Open it manually: $html"
```

Keep it **local**: a self-contained file on disk, never a hosted render, an uploaded page, or
a published artifact.

**Columns: # · Where · What the reviewer said · Valid? · Planned action.** In plain human
words — this is read by a person deciding whether to approve the plan, not by a linter.

- Lead the "what the reviewer said" cell with a bold one-line restatement, detail underneath.
  Not a quote of the comment — a translation of it.
- Mark blocking findings unmistakably (a chip, not a footnote). Group by reviewer if that
  reads better than finding order.
- Severity or blocking chips colour-coded; red / amber / grey is enough.
- **Theme-aware** — light and dark via `prefers-color-scheme`.
- **Make cells wrap.** This bites every time. `table-layout: fixed` with a `<colgroup>`
  (narrow `#`, narrow `Valid?`, wide `What the reviewer said`, ~25% `Planned action`), plus
  `overflow-wrap: anywhere` on cells and `<code>`. Never leave `white-space: nowrap` on a
  column holding a sentence.
- Multi-item actions render as a real `<ul>`, not a run-on inline list.
- Inline all CSS. No CDN, no external fonts — it must open offline.

**Include a "where the deferred items will live" mini-table.** Each deferred finding → the
ticket summary you intend to file; each declined finding → "recorded in the plan". This
doubles as the ticket draft, so approving the report approves filing exactly those tickets.
Anything materially new after that gets shown before it's created.

**Then refresh it as the work lands.** Same file, same finding IDs: swap "planned action" for
what actually happened (fixed in `<sha>` / filed as `<KEY>` / declined, recorded), fill the
deferred table with real ticket numbers, and finish with a footer carrying the pushed
commits and the resolved-thread count. The report the user approved and the report they read
afterwards are the same document, which is what makes it a record rather than a pitch.

## Replies on human threads

One reply per human thread, after the work is pushed — so the reply can point at a real
commit.

```sh
gh api "repos/{owner}/{repo}/pulls/$PR/comments/$COMMENT_ID/replies" -F body=@"$WORK/reply-$N.md"
```

**Shape: 1–3 sentences.** Acknowledge the point, say what you did, name the commit, and for
anything deferred **cite the ticket number** so the reviewer can see where it went. That last
part is the whole reason the tickets get filed before the replies get posted.

- "Good catch — fixed in `a1b2c3d`; the guard now runs before the early return."
- "Fair point, but it's a bigger change than this PR should carry, so it's `ABC-1234`."
- "Left this one as-is — the duplication is deliberate so the two paths can diverge; say the
  word if you'd rather I collapse it."

**Tone: write like a person, not a linter.** Relaxed, plain, first-person, short sentences,
no hedging stacks. It should read like a colleague who did the work, not a status generator.

Pass reply bodies as a **file** (`-F body=@file`), never as an inline string: backticks in a
code span get run as command substitution, and an apostrophe closes the quote.

## Resolving the threads

Only **inline review threads** are resolvable — issue-level comments and review summaries
aren't threads, and bot threads are left alone regardless.

```sh
# Thread ids + first-comment author, so you can filter to humans
gh api graphql -f query='
query($owner:String!,$name:String!,$pr:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:100){ nodes { id isResolved
        comments(first:1){ nodes { databaseId author { login } } } } } } } }' \
  -F owner="$OWNER" -F name="$NAME" -F pr="$PR" > "$WORK/threads.json"

# Resolve one thread — pass the id as a variable, never interpolated into the query
gh api graphql -f query='
mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread { id isResolved } } }' \
  -f id="$THREAD_ID"
```

## Gotchas (learned the hard way)

- **`--jq` and `$1` don't mix.** Inside `gh api … --jq '…'`, a `$1` or `$name` is expanded by
  the *shell* before jq ever sees it, and blows up the expression. Use jq's own variables, or
  format the id outside jq.
- **A failed `--jq` doesn't mean a failed mutation.** The GraphQL call still *executes* even
  when the `--jq` formatting errors afterwards. So never trust the loop's stdout — verify the
  end state by re-querying the unresolved count:
  ```sh
  gh api graphql -f query='
  query($owner:String!,$name:String!,$pr:Int!){ repository(owner:$owner,name:$name){
    pullRequest(number:$pr){ reviewThreads(first:100){ nodes { isResolved } } } } }' \
    -F owner="$OWNER" -F name="$NAME" -F pr="$PR" \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)]|length'
  ```
- **Pagination truncates at 30.** `gh api "repos/{owner}/{repo}/pulls/$PR/comments"` without
  `--paginate` silently drops comments on a busy PR, and `reviewThreads(first:100)` needs a
  cursor past a hundred. A missed comment reads exactly like a comment you decided to ignore.
- **Amend vs. new commit.** If `git commit --amend` is blocked, or the commit is already
  pushed, make a separate commit instead. Don't rewrite published history to keep the log
  tidy.

## Length caps

Length is part of the tone. Nobody reads the third paragraph.

- Each report cell: **one bold claim + up to three sentences**.
- Each reply: **1–3 sentences**.
- Each ticket description: context, scope, and "surfaced on PR #N" — **a short paragraph**,
  but never a stub. A one-line ticket is the same as no ticket.
- The final summary to the user: **one short paragraph or a tight list**, ending with what
  you couldn't do.

If a section runs longer than that, you're explaining rather than reporting — cut it, or move
the depth into the ticket. If a paragraph reads robotic, rewrite it before showing the user,
and certainly before posting it.
