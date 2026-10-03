# The HTTP APIs

A koya server has two JSON APIs:

- the **delivery API** (`/api/v1/{space}/…`), which reads published content with
  a **delivery key**;
- the **admin API** (`/admin/api/…`), which deploys the schema and manages
  contents, keys and media with a **management key**.

[koya-ts-sdk](https://github.com/skyizwhite/koya-ts-sdk) wraps both, with types
generated from your schema; this page is what it does underneath, for reading
the SDK's results or calling the APIs with plain `fetch`. Every endpoint,
parameter and response shape is specified in [openapi.yaml](openapi.yaml).

- [Spaces and keys](#spaces-and-keys)
- [Reading content](#reading-content)
- [What comes back](#what-comes-back)
- [Managing content](#managing-content)
- [Media](#media)
- [Errors](#errors)
- [Webhooks](#webhooks)

## Spaces and keys

A **space** is one site's content: its models, contents, media and keys. It is
made in the admin UI and named by a slug (`website`), which is in every URL. Its
**Keys** page makes both kinds of key:

| Key | Sent as | Reaches |
|---|---|---|
| delivery key `koya_…` | `X-KOYA-DELIVERY-KEY: koya_…` | published content of its space, and drafts by their draft key |
| management key `koya_mgmt_…` | `Authorization: Bearer koya_mgmt_…` | everything in its space: schema, contents, keys, media |

A key sent to another space's URL is refused with `403`. The management key can
change everything in its space: keep it on a server and out of anything shipped
to a browser. The owner secret (`KOYA_SECRET`) only logs into the admin UI and
is not accepted by either API.

The delivery API answers browsers on any origin: it replies to the preflight
`OPTIONS` (`Access-Control-Allow-Origin: *`, `GET`, the `X-KOYA-DELIVERY-KEY`
header, cached for a day), and every answer, errors included, carries
`Access-Control-Allow-Origin: *`. So a delivery key can be used from a page's
own scripts as well as from a server. Anyone who loads the page can read the
key and use it; it reaches only what is published, and a draft only with its
draft key, so show a draft key only on a preview page. Every answer is
`no-store`, so reading from the server side, where the site can cache, keeps the
load on koya lower. The admin API answers no cross-origin request.

## Reading content

```
GET /api/v1/{space}/{model}          a page of a list model, or an object model's content
GET /api/v1/{space}/{model}/{id}     one content of a list model
```

```ts
const res = await fetch(
  "https://cms.example.com/api/v1/website/blog?limit=10&orders=-publishedAt&include=tags",
  { headers: { "X-KOYA-DELIVERY-KEY": process.env.KOYA_DELIVERY_KEY! } },
);
const { contents, totalCount, offset, limit } = await res.json();
```

| Parameter | Meaning |
|---|---|
| `limit` | default 10; above 100 is clamped to 100 |
| `offset` | default 0; above 2^63−1 answers `400 bad_query` |
| `orders` | comma-separated field names, `-` for descending: `-publishedAt,title`. Default: newest published first |
| `filters` | see below |
| `include` | reference fields to embed, dotted for nesting: `tags,author.team` |
| `fields` | keys to keep in each content: `id,title` |
| `draftKey` | on one content, serves its draft instead — for previews |

`limit`, `offset`, `orders` and `filters` apply to list models; an object model
has one content and ignores them.

**Filters** are `field[operator]value` terms joined with `[and]` and `[or]`;
`[or]` separates groups of `[and]` terms:

```
title[contains]hello[and]publishedAt[exists]
category[equals]tech[or]category[equals]life
```

| Operator | |
|---|---|
| `equals` `not_equals` | the value is / is not this |
| `contains` `not_contains` | the text contains / does not contain this |
| `begins_with` | the text starts with this |
| `less_than` `greater_than` | for numbers and dates |
| `exists` `not_exists` | the field has a value / is blank (takes no value); a boolean always has one, `false` when missing |

On a `many` field, `equals` and `contains` mean "has this value". A value for a
`number` field is a decimal of at most 64 characters, such as `42`, `-2.5` or
`1e3`. An unknown field in `filters`, `orders` or `include`, or a number field
given anything else, is `400 bad_query`.

**Previews.** A content's draft is served by the delivery API to whoever has its
draft key. The editor's *Preview draft* link opens the model's `previewUrl` with
`{CONTENT_ID}` and `{DRAFT_KEY}` filled in; the preview page passes the key on as
`draftKey`. Saving the draft again issues a new key, so an old link stops
working.

## What comes back

A content is its fields plus the system fields:

```json
{
  "id": "01J8Q0Z5X2W3V4U5T6S7R8Q9P0",
  "title": "Hello",
  "slug": "hello",
  "cover": {
    "id": "01J8Q0Z5X2W3V4U5T6S7R8Q9P1",
    "url": "https://cms.example.com/media/website/01J8Q0Z5X2W3V4U5T6S7R8Q9P1.png",
    "filename": "cover.png", "mime": "image/png", "size": 12345,
    "width": 1200, "height": 630, "alt": "Cover", "createdAt": "2026-09-20T05:04:03.123Z"
  },
  "tags": ["01J8Q0Z5X2W3V4U5T6S7R8Q9P2"],
  "createdAt": "2026-09-20T05:04:03.123Z",
  "updatedAt": "2026-09-20T05:04:03.123Z",
  "publishedAt": "2026-09-20T05:04:03.123Z",
  "revisedAt": "2026-09-20T05:04:03.123Z"
}
```

- **References** are ids unless named in `include`. `include=tags,author.team`
  embeds `tags`, `author`, and `team` inside each `author`. Only reference
  fields can be included. A referenced content that is missing or unpublished
  drops out of a `many` field and becomes `null` in a single one.
- **Media** fields are always expanded to the media object, with an absolute
  `url`; one whose file is gone is `null`.
- **Rich text** is HTML whose `/media/` sources are rewritten to absolute URLs,
  so it renders on any site.
- **`fields`** applies last, after embedding and expansion, and drops system
  fields it does not name too.
- `publishedAt` is the first publish, `revisedAt` the latest; both are `null`
  while a content is not published. Timestamps are ISO 8601 in UTC with
  milliseconds.
- A field the content has no value for is absent or `null`. What each type holds
  is in [SCHEMA.md, "Content values"](SCHEMA.md#content-values).

## Managing content

The admin API sees drafts as well, and returns contents in their stored shape:
both versions, with references and media as ids.

```
GET    /admin/api/contents/{space}/{model}                   every content, drafts included
POST   /admin/api/contents/{space}/{model}                   create (a draft, unless "publish": true)
GET    /admin/api/contents/{space}/{model}/{id}
PATCH  /admin/api/contents/{space}/{model}/{id}              save a draft
DELETE /admin/api/contents/{space}/{model}/{id}
POST   /admin/api/contents/{space}/{model}/{id}/publish
POST   /admin/api/contents/{space}/{model}/{id}/unpublish
POST   /admin/api/contents/{space}/{model}/{id}/discard-draft
POST   /admin/api/contents/{space}/{model}/{id}/draft-key    the key for a preview URL
```

```json
{
  "id": "01J…",
  "status": "published+draft",
  "published": { "title": "Hello" },
  "draft": { "title": "Hello, again" },
  "draftKey": "3f1c…",
  "createdAt": "…", "updatedAt": "…", "publishedAt": "…", "revisedAt": "…"
}
```

- `status` is `draft`, `published` or `published+draft`, and decides what can
  be done to the content and what it becomes. Anything else is refused with
  `409` and nothing is written:

  | `status` | save a draft | publish | unpublish | discard-draft | delete |
  |---|---|---|---|---|---|
  | `draft` | `draft` | `published` | `not_published` | `not_published` | gone |
  | `published` | `published+draft` | `published` | `draft` | `no_draft` | gone |
  | `published+draft` | `published+draft` | `published` | `draft` | `published` | gone |

- Saving a draft (`PATCH`, `{"data": {…}}`) **merges** onto the current draft, or
  the published data when there is none: keys given replace, `null` removes a key.
  When the result is what the content holds already, nothing is written (no
  revision, no webhook); when it is the published data again, the draft is
  dropped, as `discard-draft` would.
- Publishing takes `data` when given, else the draft, else re-publishes.
- Creating may give `id` and the four timestamps, for imports that keep another
  system's ids and dates. A timestamp needs a date, a time and an offset or
  `Z`, and is stored in UTC with milliseconds. An object model holds one content: once it has it,
  creating another is refused (`409 object_exists`), and that one is changed
  through its id.
- A content another content refers to, in its published data or its draft,
  through a `reference` field of the current schema, cannot be deleted, nor
  unpublished while it is published (`409 in_use`, naming how many). Take the
  reference out of those contents — and publish them, when it is in their
  published data — first. An id left in a field a deploy removed does not count.

The schema itself is deployed with `PUT /admin/api/schema/{space}` and previewed
with `POST /admin/api/schema/{space}/plan`: see [SCHEMA.md](SCHEMA.md), and
`koya plan` / `koya deploy` in koya-ts-sdk.

## Media

`POST /admin/api/media/{space}` takes `multipart/form-data` with one or more
`file` parts and an optional `alt`: PNG, JPEG, GIF or WebP, up to 20 MB each and
20 MB together, the type decided by the file's leading bytes. The answer is
`{"media": [...]}`; put a media object's `id` in a `media` field. A media still
used by a content, in a `media` or `richtext` field of the current schema, cannot
be deleted (`409 in_use`); a value left in a field a deploy removed does not
count.

## Errors

Anything but a 2xx is the object below, except for a request body over 21 MB:
that is answered with `413` and a plain-text body before koya reads it.

```json
{ "error": { "code": "validation_failed", "message": "Content is invalid", "details": [ … ] } }
```

| Status | `code` | |
|---|---|---|
| 400 | `bad_request` `bad_json` `bad_query` `invalid_schema` | the request is malformed |
| 401 | `unauthorized` | no key, or a wrong one |
| 403 | `forbidden` | a key of another space |
| 404 | `not_found` | no such space, model, content or media |
| 409 | `conflict` `destructive_changes` `in_use` `not_published` `no_draft` `object_exists` | refused as things stand |
| 413 | `too_large` | images over 20 MB, alone or together |
| 422 | `validation_failed` `empty_file` `unsupported_type` | the content or file is not acceptable |
| 500 | `internal_error` | the message is only detailed with `KOYA_ENV=dev` |
| 503 | `unavailable` | `/health` only: the database cannot be read |

Two codes carry `details`: `validation_failed` lists
`{"field", "code", "message"}` for each problem (the codes are in
[SCHEMA.md](SCHEMA.md#content-values)), and `destructive_changes` lists the
changes a deploy refused.

## Webhooks

Webhooks are part of the schema (`webhooks` in [SCHEMA.md](SCHEMA.md#webhook)).
Every webhook is POSTed **every event** of every model — or only of the models
its `only` names — and the payload says which:

```json
{
  "space": "website",
  "model": "blog",
  "id": "01J…",
  "event": "publish",
  "contents": { "old": null, "new": { … } }
}
```

| `event` | When | `old` / `new` |
|---|---|---|
| `publish` | a content is published, first time or again | the previous published data or `null` / the new |
| `unpublish` | a published content is taken off the delivery API | the published data / `null` |
| `delete` | a published content is deleted | the published data / `null` |
| `draft` | a draft is saved or created | the published data or `null` / the draft |
| `discard` | a draft is discarded, or saved back to the published data | the draft / the published data |
| `discard` | a content that is only a draft is deleted | the draft / `null` |
| `deploy` | a deploy changes what the delivery API serves of a model | `null` / `null` |

Each entry a content's history keeps is sent as its kind. Deleting a content
is sent as what it changes: `delete` when it was published, `discard` when it
was only a draft. A write that changes nothing sends nothing, and neither does
importing a space. The bodies have the delivery API's shape. `draft` and
`discard` change only a draft; the others change what the delivery API serves.
What to act on is up to the receiver.

A deploy is sent once for every model it changes the delivery API's answers of:
one renamed, removed or turned from `list` to `object` or back, or one with a
field renamed, removed or given another type. `id` is `null`, and `changes`
lists that model's changes in the shape of a plan (see
[SCHEMA.md](SCHEMA.md#changes)). A removed model is sent to the
webhooks that covered it. A deploy that only adds, or changes options, sends
nothing, and neither does a plan:

```json
{
  "space": "website",
  "model": "blog",
  "id": null,
  "event": "deploy",
  "contents": { "old": null, "new": null },
  "changes": [{ "op": "remove_field", "path": "blog.summary", "destructive": true, "description": "! - blog.summary (text)" }]
}
```

Every call carries the space's webhook secret, from its **Keys** page, in
`X-KOYA-WEBHOOK-KEY`; check it before acting:

```ts
// e.g. a Next.js route handler
import { revalidateTag } from "next/cache";

export async function POST(req: Request) {
  if (req.headers.get("x-koya-webhook-key") !== process.env.KOYA_WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 403 });
  }
  const { model } = await req.json();
  revalidateTag(model);
  return new Response(null, { status: 204 });
}
```

Delivery is fire-and-forget: koya does not retry, and follows no redirect; a
3xx is logged with its `Location`. What each call answered — its status and
body, or the error when it never arrived — is kept for the space's newest 200
deliveries and shown in the admin UI; the body only from a public address (see
[SCHEMA.md](SCHEMA.md#webhook)). See
[ADMIN-UI.md](ADMIN-UI.md#the-webhook-delivery-log).
