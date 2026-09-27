# A use-case package is one part of koya

Superseded by adr/2026-09-27-a-use-case-package-changes-for-one-reason.md

*2026-09-27*

## Context

`usecases/` had twenty-two packages in six directories: `contents/` alone was
eight (write, lookup, bulk, references, listing, labels, delivery, revisions),
and a directory such as `webhooks/` held a 79-line file and a 16-line one. In a
package-inferred system a file is a package, so the split was the size of the
files and not a boundary anyone had drawn. What it cost was paid by the callers.

- The editor imported from five `contents/` packages.
- Where a function belonged had no answer. Looking a space up was in
  `contents/lookup` (`resolve-space`) and in `spaces/lifecycle`
  (`find-space`), and the admin API's keys and media routes imported
  *contents*/lookup to find a space.

## Decision

A use-case package is one part of koya, in one file, and `usecases/` has no
directories but `ports/`. A part is what changes for one reason.

| Package | What it does | Was |
|---|---|---|
| `contents` | writes a content: create, draft, publish, unpublish, discard, destroy, in bulk; what refers to one; `resolve-content` | write, lookup, bulk, references |
| `listing` | the admin's reads: a page of contents searched and sorted, and the labels of what a reference points at | listing, labels |
| `delivery` | the delivery API's reads, as `delivered` | contents/delivery |
| `revisions` | a content's history, and data restored from it | contents/revisions |
| `spaces` | a space made, taken away, listed and found (`resolve-space`) | spaces/lifecycle |
| `schema` | a space's schema and models (`load-schema`, `find-model`, `resolve-model`) and deploys | schema/deploy, part of spaces/lifecycle |
| `archive` | a space exported and imported | spaces/archive |
| `media` | the library, and the file a media URL names | media/library, media/delivery |
| `webhooks` | a space's webhooks, calling them, and the log | webhooks/notify, webhooks/log |
| `settings` | the display time zone and the second factor | settings/timezone, settings/two-factor |

`actor`, `auth`, `keys` and `system` stay as they were.

Contents are split by who reads and who writes: a write, the admin's reading of
a list, the delivery API's reading, and the history each change for their own
reasons, and each is a file of a few hundred lines at most. The archive is apart
from the spaces because it is an import and an export format, most of the old
`spaces/` and none of a space's lifecycle. The models are the schema's, since a
deploy is what changes them.

## Consequences

- A route imports one package per part it uses.
- The use cases depend on each other in one direction:
  - `contents` uses `delivery`, `webhooks` and `schema`
  - `schema` uses `spaces`
  - `spaces` uses `media`
  - `archive` uses `schema`
  - `auth` uses `settings`
- Tests mirror the files: `tests/server/usecases/contents.lisp` and so on.
- A part that grows past what one file reads well is split along another
  reason to change, as contents was, not by size alone.
