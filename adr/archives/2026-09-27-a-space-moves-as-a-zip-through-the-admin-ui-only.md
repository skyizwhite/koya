# A space moves as a zip, through the admin UI only

Superseded by adr/2026-09-27-a-space-is-exported-as-one-zip.md
Superseded by adr/2026-09-27-a-space-moves-through-the-admin-ui-only.md

*2026-09-27, restating a decision of 2026-09-23*

## Context

There was no way to take a space out of koya as a whole: no off-host copy short
of the raw SQLite file, no way to move a space to another server, and no way to
seed a development instance from production. A backup of the volume is the
operator's copy of the whole instance. This is the portable copy of one space.

## Decision

- **Export** on a space's page downloads a zip. It holds `space.json` (the
  schema with its webhooks, every content with its published data, draft, draft
  key, system timestamps and history, the media rows, the keys and the webhook
  secret) and every media file under `media/`.
- **Import** on the spaces page makes the space again from that zip, under the
  same name.
- **Neither has an API.** A management key reaches one space, and an import that
  makes a space would need a key for a space that does not exist yet. Only the
  owner can make spaces.

## Consequences

Moving a space to another server is Export, Import, and pointing the site at the
new instance.
