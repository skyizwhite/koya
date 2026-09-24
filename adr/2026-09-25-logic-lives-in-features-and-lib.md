# Logic lives in features/ and lib/, not in pages and components

*2026-09-25*

## Context

With the components in `ui/`, what was left in a page file was its components,
its actions, and a mix of everything else: how the content list builds its
search and its ORDER BY, the labels a reference field offers, what a bulk
publish skips, what a revision changed, how a selection of media is deleted, how
an uploaded archive becomes a space. Some of it was written twice: the editor
and the list each looked up the contents a reference points at, the library and
the picker each stored uploads one by one, and five pages each had their own
page size and `page-number`.

`lib/` meanwhile held two kinds of module side by side: what any part of koya
uses (`http`, `auth`, `query`) and what belongs to one part (`content-service`,
`media-store`, `space-archive`, `webhook`).

## Decision

The logic of one part of koya is under `src/server/features/<part>/`:

- `contents/`: `service` (was `lib/content-service`), `presenter`, `forms`,
  `revisions` (with what a revision changed), `listing` (a page of a model's
  contents, searched, filtered and sorted), `labels` (what a content is called,
  and what a reference field offers), `bulk`
- `media/`: `store` (was `lib/media-store`), `image`, `library` (storing and
  removing several files)
- `spaces/`: `archive` (was `lib/space-archive`, now also reading one from a
  stream), `lifecycle` (removing a space and its files)
- `webhooks/`: `notify` (was `lib/webhook`)

What several parts share stays in `lib/`, and what was repeated moved there:
`paging` (the page size, `page-number`, `last-page`), and `blank-p` and
`form-values` in `http`.

A page, a component or an action reads the request, calls into `features/` and
`lib/`, and draws or words the result. The toast's wording stays with it: a
feature answers with what happened (`apply-to-each` returns what was done,
skipped and failed; the page says it).

What only one page needs to draw -- its own URLs, a badge's class, the preview of
a value in a list cell, how a value reads on the history page -- stays in that
page's file. So do the small functions an action needs to read its request
(`read-state`, `requested-revision`).

`features/` never depends on `ui/` or `pages/`, and `lib/` on no feature.
`tests/` mirrors the move.

## Consequences

The admin API and the admin UI reach the same `features/` module for the same
thing, as the content service already did for writes.

A page file reads as what the page shows and what its buttons do. Something that
is neither is a candidate for `features/`, and the question to ask is whether it
would still make sense with no HTML around it.
