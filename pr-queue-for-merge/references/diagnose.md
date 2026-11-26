# Diagnosing a merge-group failure (Step 5)

Goal: decide, with evidence, whether a failed or hung merge-group check is **flaky** (re-queue)
or **real** (stop). The default is real. Re-queueing a real failure wastes a full queue cycle
for everyone behind you and teaches nobody anything.

## 1. Read it

For each entry in the snapshot's `failed[]` (or `hung[]`):

```sh
"$SKILL_DIR/scripts/failure-summary.sh" "<url from the snapshot>" --save "$RUN/<job-id>.log"
# or: failure-summary.sh <run-id> <job-id> --repo <owner/name>
```

- It prints the failing tests it recognizes (Playwright, Jest, pytest, go), infrastructure
  signatures, and the first error lines. Read the saved log around them when the summary is
  thin. The summary never decides "flaky"; you do, with the evidence below.
- **A check that isn't a GitHub Actions job** (a commit status from another CI, such as a
  Cloud Build mirror): follow its `url` if you can read it. If you can't read why it failed,
  that is **BLOCKED** (say which check and link it), never a guess.
- The helper reads the job through the jobs API, which serves a finished job's log while the
  rest of its run is still going. `gh run view --log` only works once the whole run is done.
- **A hung job** has no readable log until it ends. The hang itself is the evidence: compare
  how long the same job takes in other runs (step 3). Many times longer than its peers, and
  past its own configured timeouts, means a lost or wedged runner.
- **The aggregate check** (a "CI Success"-style job that only says "a needed job failed") is
  never the cause. Find the job it points at.
- **A group that holds other PRs** (`gh-readonly-queue/<base>/pr-<n>-<sha>` names the last PR
  in it; GitHub lists the others on the run's summary page): the failure may belong to a PR
  ahead of yours. Note it; the queue usually removes the culprit by itself.

## 2. Classify

| Class | What it looks like | Verdict |
|---|---|---|
| **Infrastructure** | runner lost or shut down (`The runner has received a shutdown signal`), cancelled by the platform, disk full, OOM kill (`exit code 137`), network or registry errors (`ECONNRESET`, `ETIMEDOUT`, 429, 5xx, image pull failed), a service that never started, a hang far past its peers. **No failing assertion.** | flaky |
| **Flaky test** | a real assertion failed, **and** both proofs in step 3 hold | flaky |
| **Caused by this PR** | the failing test or build step covers code the diff touches or depends on, or the same failure shows up on this PR's own head | real → BLOCKED |
| **Red on the base branch** | the same test fails on other merge groups or on the base branch's own runs too | real → BLOCKED, with both links (re-queueing can't help) |
| **Can't tell** | anything else | real → BLOCKED |

## 3. The two proofs for "flaky test"

A test assertion counts as flaky only when **both** hold. Write both down in the report.

**(a) The diff can't reach it.** Compare the failing test's area with the PR's changed files
(`gh pr diff <n> --name-only`). Say concretely why it can't, e.g. "API tests write through the
Admin SDK, which bypasses the rules file this PR changes; none of the 30 API specs import the
two helpers it edits". "Unrelated" with no reason is not a proof.

**(b) The same test passed on an equivalent tree.** Look, in this order:

1. **Another merge group on the same base.** Merge groups built moments apart share most of
   the tree. List them and find the same job:

   ```sh
   gh run list --repo "$NWO" --event merge_group --workflow "<workflow>" -L 15 \
     --json databaseId,conclusion,headBranch,createdAt
   gh run view <other-run> --repo "$NWO" --json jobs \
     --jq '.jobs[] | select(.name == "<job name>") | "\(.databaseId) \(.conclusion)"'
   gh run view <other-run> --repo "$NWO" --job <other-job> --log | grep -F '<test id>'
   ```

   A passing line for the same test id (Playwright `✓ … <spec>:<line>`, Jest `✓ <title>` or
   `PASS <file>`, pytest `PASSED`) is the proof. The best match is the group just ahead of
   yours: its tree is yours minus your diff.
2. **This PR's own CI run on its head**, if that ran the same test.
3. **The base branch's latest run** of the same workflow.

If the test **failed** in those places too, it is red on base, not flaky. If you find no run
of the same test at all, proof (b) fails: **BLOCKED** (can't tell).

## 4. Caps that override a "flaky" verdict

- The **same check and test** failed in the previous attempt too → it is not flaky; BLOCKED.
- `--max-requeues` (default 3) already spent → BLOCKED.
- The PR's head moved, it was closed, or it lost its approval since it was queued → stop; the
  re-queue would test something nobody approved.
