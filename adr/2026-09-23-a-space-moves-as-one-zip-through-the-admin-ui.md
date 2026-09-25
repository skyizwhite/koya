# A space moves as one zip, through the admin UI

Superseded by adr/2026-09-25-a-space-has-no-size-limit-and-moves-in-pieces.md (how the archive is built and sent, and its size)

*2026-09-23*

## Context

There was no way to take a space out of koya as a whole. The delivery and admin
APIs read contents model by model and drafts one at a time, and the media are
files on the volume. That leaves no off-host copy short of the raw SQLite file,
no way to move a space to another server, and no way to seed a development
instance from production (#14). The volume backup (#7) is the operator's copy of
the whole instance; this is the portable copy of one space.

## Decision

**Export** on a space's page downloads a zip: `space.json` — the schema with its
webhooks, every content with its published data, its draft, its draft key, its
system timestamps and its history, the media rows, the delivery and management
keys and the webhook secret — plus every media file under `media/`. **Import**
on the spaces page takes that zip and makes the space again under the same
name, with the same ids.

- **Only in the admin UI.** There is no API for either. A management key reaches
  one space, and an import that makes the space would need a key for a space that
  does not exist yet; the owner is the one who can make spaces.
- **Only into a space that has nothing to meet.** The name must be free, or the
  space must be empty: no models (so no contents), no media and no keys. Its
  webhooks and webhook secret, which a new space has from the start, are
  replaced by the archive's. Anything else is refused and changes nothing:
  there is no merge by id, and no check that a deployed schema matches the
  archive's. The import owns the schema, webhooks included, and records it in
  the deploy log as a deploy by the owner. An existing media file is never
  replaced.
- **Keys and the secret move too.** Keys are stored as SHA-256 and travel as
  that, so the archive holds no key that can be used, and the site's `.env`
  keeps working against the new instance. The webhook secret is stored in
  plain text — it is sent with every call — and travels so, which with every
  draft already in the file makes the archive something to keep as privately
  as the database.
- **Nothing is sent to the webhooks** while importing: the contents are not being
  published, they are being put back.
- The ids are kept, so reference fields, media fields and the `/media/{space}/…`
  paths the editor writes into richtext all still point at the right things.
  Media ids are checked against the shape an upload makes and each file is
  sniffed as an upload is, because the ids become file names.

## Consequences

Moving a space to another server is Export, Import, and pointing the site at
the new instance; nothing about its keys or secret changes. Seeding a
development instance copies production's webhooks and secret too, so edits
there are sent to the production site, which only fetches from production
koya and so at most rebuilds for nothing; point the copy's webhooks elsewhere
with a deploy if that matters.

The import does not go through lack's multipart parsing, which would hold the
body in memory several times over — enough, for a large archive, to exhaust the
heap and take the server down. The form sends the file itself as an
`application/zip` body; the outermost middleware sets it aside unread, and
`/import` copies it to a temporary file once the owner and the origin are
checked, then reads the zip entry by entry. That body may be up to 512 MB; a
multipart body to `/import` keeps the ordinary limit. The export is still built
in memory, one copy of the archive, which suits spaces the size koya is for.

A schema that has moved on since an export does not stop the import, because
the import brings its own. Deploying the site's current schema afterwards is an
ordinary deploy.
