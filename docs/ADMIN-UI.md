# The admin UI

koya's admin UI is the web app the server serves at its own root: one owner, any
number of spaces. It is where content is written, published and previewed, where
images live, and where a space's API keys are made.

What it does **not** do is edit the schema. Spaces, models and fields come from
the `defspace` / `defmodel` definitions in a site's own repository and reach the
server with `(koya:deploy)` — see [CLIENT.md](CLIENT.md). The admin UI reads that
schema and builds its lists and forms from it.

- [Logging in](#logging-in)
- [Spaces](#spaces)
- [A space](#a-space)
- [Contents of a model](#contents-of-a-model)
- [The editor](#the-editor)
- [Drafts, publishing and previews](#drafts-publishing-and-previews)
- [Media](#media)
- [API keys](#api-keys)
- [Settings: time zone and two-factor login](#settings-time-zone-and-two-factor-login)
- [Reference](#reference)

## Logging in

`GET /login` asks for the owner secret — the value of `KOYA_SECRET` — and, when
two-factor login is on, for the current code from an authenticator app. There are
no user accounts: whoever knows the secret is the owner.

- Five failed attempts from the same address within five minutes lock that
  address out for the rest of the window. The message never says which of the two
  factors was wrong.
- A session lasts 24 hours and is stored in the database, so a server restart or
  a redeploy does not log the owner out. The cookie is `HttpOnly`, `SameSite=Lax`
  and, when `KOYA_BASE_URL` is an `https://` URL, `Secure`.
- Every page has **Log out** in the header; form submissions from another origin
  are rejected.

## Spaces

`/` lists the spaces of the deployed schema with the number of models in each.
Until a schema has been deployed the page is empty and says so.

![A space: its models and webhooks](img/space.png)

## A space

`/s/{space}` lists the space's models — a stacked-rows icon for a `:list` model,
braces for an `:object` model — with the number of contents in each list model,
and links to **Media** and **API keys**.

Underneath, **Webhooks** shows every webhook that can fire for this space: the
space's own (marked *all models*) and each model's (*`{model}` only*), with the
label, the URL and the events it subscribes to. Webhooks are part of the schema,
so they are read-only here; change them in `defspace` / `defmodel` and deploy.

## Contents of a model

`/s/{space}/m/{model}` is a table: a status badge, then one column per field of
the model, then a chevron. Clicking anywhere in a row (or pressing Enter on it)
opens the editor.

![Contents of a list model](img/model.png)

- Every field gets a preview, clamped to two lines: rich text is stripped to
  plain text, a datetime is shown as `YYYY-MM-DD HH:MM UTC`, a reference shows the
  referenced content's label, a `:many` field shows its values comma-separated,
  and an empty field shows `—`. Column widths are bounded per field type, so a
  wide model scrolls sideways rather than squeezing every column thin.
- A row shows its **draft** data when it has one, so the table reflects what is
  being worked on rather than what is live.
- Contents are listed newest-created first, and the page shows up to 100 of them.
  There is no paging yet, and no filtering or sorting from the UI.
- **New content** opens an empty editor at `/s/{space}/m/{model}/new`.

For an `:object` model this URL redirects straight to its single content (or to a
`new` editor when it has none): an object model holds exactly one content.

## The editor

`/s/{space}/m/{model}/{id}` generates a form from the model. Each field is
labelled with its name, its type and, when required, a red `*`.

![Editing a content](img/editor.png)

| Field type | Control |
|---|---|
| `:text`, `:slug` | text input — a blank `:slug` is generated from its `:from` field on save |
| `:textarea` | five-row textarea |
| `:richtext` | Quill editor; its image button opens the media picker |
| `:number` | number input (any step) |
| `:boolean` | checkbox — unchecked means `false`, never "unset" |
| `:date` | date input |
| `:datetime` | datetime-local input, in the zone chosen under **Settings**; stored as UTC |
| `:select` | dropdown, or checkboxes when `:many` |
| `:reference` | dropdown, or chips plus a dropdown when `:many` |
| `:media` | thumbnail with **Choose…** (opens the media picker) and **Clear** |

Notes on the generated controls:

- A reference dropdown lists up to 1000 contents of the target model, drafts
  included, labelled by the content's first non-empty `:text` or `:slug` field and
  falling back to its id. An id that no longer resolves is kept and shown as
  `{id} (missing)`, so a save never drops it silently.
- Rich text is stored as HTML. Images inserted from the picker are stored as
  `/media/...` paths and made absolute again by the delivery API, so the HTML is
  safe to render on another site.
- When validation fails the page comes back with a summary at the top and the
  message under each offending field; nothing is saved.

The sticky bar at the top of the editor carries the title, the status badge and
the created/updated times, then:

| Button | What it does |
|---|---|
| **Preview draft** | opens the model's `:preview-url` with `{CONTENT_ID}` and `{DRAFT_KEY}` filled in — shown only while a draft with a key exists |
| **Published page** | opens the model's `:public-url` — shown only while the content is published |
| **Discard draft** | throws the draft away and goes back to the published version (published contents only) |
| **Save draft** | saves the form as a draft, leaving what is published untouched |
| **Publish** | validates and publishes the form as it stands |

At the bottom, the **Danger zone** holds **Unpublish** (takes the content off the
delivery API, keeping its data as a draft) and **Delete** (removes it for good;
for an object model it starts the single content over). Both ask first.

## Drafts, publishing and previews

A content is in one of three states, shown as its badge:

| Status | Meaning |
|---|---|
| `draft` | never published, or unpublished; invisible to the delivery API |
| `published` | live, with no unpublished edits |
| `published+draft` | live, with newer draft edits alongside it |

- Saving a draft issues a **new draft key**, so previously shared preview links
  stop working.
- Publishing clears the draft, sets `revisedAt`, and keeps the original
  `publishedAt` on later publishes.
- Unpublishing keeps the data as a draft and clears `publishedAt`.
- Publishing, unpublishing and deleting fire the matching webhooks; saving a
  draft fires `:draft` webhooks; discarding a draft fires none, since what is
  published did not change.

## Media

`/s/{space}/media` is the space's image library.

![The media library](img/media.png)

- **Upload** takes PNG, JPEG, GIF and WebP, several at once, up to 20 MB each.
  The type is decided by reading the file's leading bytes, not by what the browser
  claims. Files are stored under `KOYA_MEDIA_DIR/{space}/` and served at
  `/media/{space}/{id}.{ext}` with a long immutable cache.
- The grid is thumbnails only, 48 per page, with paging underneath. The search box
  matches file names.
- Clicking a thumbnail opens a preview dialog with the file's name, dimensions,
  size and upload time, an **alt text** box to save, and **Delete**. Deleting asks
  first and says how many contents use the file; contents that referenced it keep
  a dangling id, which the delivery API then returns as `null`.
- The same library opens as a picker inside the editor — from a `:media` field's
  **Choose…** button and from Quill's image button. The picker searches and
  uploads too, so an image can go straight from the desktop into a content.

## API keys

`/s/{space}/keys` manages the keys sites use to read this space through the
delivery API.

- **Create key** takes an optional label and shows the key (`koya_…`) once. Only
  its SHA-256 is stored, so a lost key cannot be recovered — delete it and make
  another.
- A key belongs to one space; it is rejected on any other.
- The **Webhook secret** section shows the value koya sends as the
  `X-KOYA-WEBHOOK-KEY` header with every webhook of the space, and can rotate it.
  Verify it on the receiving end.

## Settings: time zone and two-factor login

`/settings` holds the two instance-wide settings.

**Time zone** is the zone every page shows times in — created and updated at,
the list previews, and `:datetime` fields, which are also entered in it. Type an
IANA name (`Asia/Tokyo`, `Europe/Berlin`; the box offers the zones the server
knows) and save; the line underneath shows the current time in it as a check.
The default is UTC. Storage and the delivery API are not affected: they stay UTC.

**Two-factor login** turns the second factor on: **Set up two-factor login** shows a QR
code, the Base32 secret and the `otpauth://` URI; scanning it and entering a
current code stores the secret and starts asking for a code at login. The secret
is only kept once the app has proved it has it.

Disabling asks for a current code as well. A code can only be used once.

To keep the secret out of the database, run `(koya-server:totp-setup)` in the
server's REPL and set the `KOYA_TOTP_SECRET` it prints; the environment variable
takes precedence and the settings page then only reports that it is in force.

## Reference

### URLs

| Path | Page |
|---|---|
| `/` | spaces |
| `/login`, `/logout` | log in, log out |
| `/settings` | instance settings (time zone, two-factor login) |
| `/s/{space}` | a space: models and webhooks |
| `/s/{space}/m/{model}` | contents of a model (object models redirect to their content) |
| `/s/{space}/m/{model}/{id}` | the editor; `new` for a new content |
| `/s/{space}/media` | media library |
| `/s/{space}/keys` | API keys and the webhook secret |
| `/health` | unauthenticated health check (verifies the database answers) |

### Limits worth knowing

| Thing | Value |
|---|---|
| Contents listed on a model page | 100, newest created first, no paging |
| Contents offered in a reference field | 1000 |
| Media per library page / per picker page | 48 / 24 |
| Upload size and types | 20 MB; PNG, JPEG, GIF, WebP |
| Session lifetime | 24 hours, stored in the database |
| Login lockout | 5 failures per address per 5 minutes |

### What the UI deliberately leaves out

- Editing the schema: it belongs to the site's repository (see [CLIENT.md](CLIENT.md)).
- User accounts and roles: there is one owner.
- Revision history: a content has one published version and one draft.

For the reasoning behind these, see [DESIGN.md](DESIGN.md).
