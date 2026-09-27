# A space is exported as one zip

*2026-09-27, restating a decision of 2026-09-23*

## Context

There was no way to take a space out of koya as a whole: no off-host copy short
of the raw SQLite file, no way to move a space to another server, and no way to
seed a development instance from production. A backup of the volume is the
operator's copy of the whole instance. This is the portable copy of one space.

## Decision

- An export is one zip. It holds `space.json` and every media file under
  `media/`.
- `space.json` holds the schema with its webhooks, every content with its
  published data, draft, draft key, system timestamps and history, the media
  rows, the keys and the webhook secret.
- An import makes the space again from that zip, under the same name.

## Consequences

Moving a space to another server is exporting it, importing it there, and
pointing the site at the new instance.
