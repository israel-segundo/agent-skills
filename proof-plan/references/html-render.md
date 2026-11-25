# Re-rendering a sibling PLAN.html (Step 4b)

Only when an HTML sibling already exists. Do not create one unless the user or repo rules ask
for it.

## Keep the existing shell

The existing file carries the author's styling (theme tokens, table wrappers). Keep everything
outside `<main>…</main>` (or `<body>…</body>` when there is no `<main>`) and replace only the
rendered content. Update `<title>` only if the plan's H1 changed.

## Pick a renderer that is already installed

Probe in order; use the first that works. **Never download one** (`npx --yes`, `pip install`):
fetching a package to re-render a note is not worth an unreviewed dependency.

1. `marked` resolvable by Node: the target repo's or plan-store's `node_modules/marked`, or a
   global install (`npm root -g`). Render with GFM on.
2. `pandoc -f gfm -t html`
3. Python `markdown` module (`python3 -c 'import markdown'`) with the `tables` extension
4. `cmark-gfm`

```sh
# marked via Node, resolved from a local node_modules
MARKED=$(for d in "$REPO/node_modules" "$(npm root -g 2>/dev/null)"; do
  [ -f "$d/marked/lib/marked.esm.js" ] && echo "$d/marked/lib/marked.esm.js" && break; done)
```

## Post-process

- Wrap each `<table>` in `<div class="tbl">…</div>` when the existing file does (horizontal
  scroll on narrow screens).
- GFM treats a pair of `~` in one paragraph or cell as strikethrough. If the plan writes `~`
  for "approximately", that is a plan nit for the review round, not something to patch in the
  HTML.

## None available

Leave the HTML as is, and report: `PLAN.html is stale (no local markdown renderer); refresh
with: <command>`.

## Opening it

On an interactive desktop host, open the file after rendering (`xdg-open`, `open`) without
waiting on it. Headless: print the path.
