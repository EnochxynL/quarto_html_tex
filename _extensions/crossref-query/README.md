# Crossref Query

Read Quarto's existing reference numbers without counting objects or scraping HTML.
This is a prototype compatibility extension, not a public Quarto API.

Enable `filters: [crossref-query]` to turn
`[]{.reference-number target="fig-example"}` into a number-only link.
For your own consumer, load `crossref-query.lua` with `dofile()` and call
`query.lookup("fig-example")` from a **post-quarto or later** callback.
Paths passed to `dofile()` should be resolved relative to your filter file.
The example consumer uses a document callback so forward references are available.

The result contains `identifier`, `ref_type`, `parent` (if any), `target`
(a local `#fragment`), and `number` (detached Pandoc Inlines). Unknown targets
return `nil`; invalid argument types raise an error. Use
`pandoc.utils.stringify(ref.number)` for plain text. The query does not mutate
the index. Number formatting is delegated to Quarto, including custom categories,
chapter offsets, label styles and subreferences.

Files have separate responsibilities:

- `query.lua`: query algorithm, depending only on an injected backend.
- `quarto-internal.lua`: all unsupported `_G` access, isolated for replacement.
- `crossref-query.lua`: selects a future public `quarto.doc.crossref.lookup`
  when available, otherwise loads the compatibility adapter.
- `reference-numbers.lua`: optional example consumer, not part of the query API.

An upstream implementation can reuse the query algorithm with a backend bound
to core state, or expose equivalent lookup directly. Consumers need no changes
if the future API adopts this contract. No core source modification is required.

## Limits

The compatibility adapter cannot reliably detect an early call: an index may
exist before it is complete. Scheduling at post-quarto is mandatory. Its private
dependencies may change between Quarto versions; missing helpers raise an error.

Only targets indexed in the current document are available. Raw LaTeX labels
and arbitrary HTML anchors are not automatically registered. This alone does
not replace the project's raw-LaTeX reference support or all Python postprocessors.
In multi-file books, project-level resolution can be deferred; `number` is then
absent. `target` is not a final cross-file URL. Preserve native references for
that later resolver. Numbers also do not reflect arbitrary counter changes made
by LaTeX templates after Quarto has finished.

The existing core API proposal is archived separately on branch
`archive/crossref-lookup-api-20261027`, commit `e3777fca1` in the Quarto worktree.

## Validation

Validated with unmodified Quarto 1.10.19, including loading the packaged
extension by name. From the project root, with Quarto on PATH, run:

```sh
python _regression/crossref-query/run.py
```

The fixtures check seven reference categories, forward queries, custom number
styles, chapter offsets, subreferences, detached results, and deferred book
numbering. Generated native reference text is checked independently. These
tests do not claim compatibility with every Quarto version or output format.
The project's existing reference filters and Python postprocessors have not
yet been switched to this module.
