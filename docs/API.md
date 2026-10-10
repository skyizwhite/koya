# The HTTP APIs

A koya server has two JSON APIs:

- the **delivery API** (`/api/v1/{space}/…`), which reads published content with
  a **delivery key**;
- the **admin API** (`/admin/api/{space}/…`), which deploys the schema and
  manages contents, keys and media with a **management key**.

Both name the two kinds of model apart. A `list` model is a **list**, and its
contents are **list contents**, reached under `lists/{model}`. An `object`
model's one content is its **object**, reached under `objects/{model}` with no id.

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
GET /api/v1/{space}/lists/{model}                a page of a list
GET /api/v1/{space}/lists/{model}/{id}           one list content
GET /api/v1/{space}/lists/{model}/slugs/{slug}   one list content, by its slug
GET /api/v1/{space}/objects/{model}              an object
```

```ts
const res = await fetch(
  "https://cms.example.com/api/v1/website/lists/blog?limit=10&orders=-publishedAt&include=tags",
  { headers: { "X-KOYA-DELIVERY-KEY": process.env.KOYA_DELIVERY_KEY! } },
);
const { contents, totalCount, offset, limit } = await res.json();
```

| Parameter | Meaning |
|---|---|
| `limit` | default 10; above 100 is clamped to 100 |
| `offset` | default 0; above 2^63−1 answers `400 bad_query` |
| `orders` | comma-separated field names, `-` for descending: `-publishedAt,title`. Default: newest published first. `id` orders by the ids' text, not by when the contents were made; `createdAt` by its value, which an import may have given |
| `filters` | see below |
| `q` | search: the text of the model's `text`, `textarea`, `slug` and `richtext` fields, those inside a custom field or a repeater's rows included, contains it, or it is a content's whole id. Combined with `filters`, both apply |
| `include` | reference fields to embed, dotted for nesting and to reach into a custom field or a repeater's rows: `tags,author.team,meta.author,blocks.by` |
| `fields` | top-level keys to keep in each content: `id,title` |
| `draftKey` | on one list content or an object, serves its draft instead — for previews |

`limit`, `offset`, `orders`, `filters` and `q` apply to a list; an object ignores
them. A list model is not found under `objects/` nor an object model under
`lists/` (`404`).

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

On a `many` field, `equals` and `contains` mean "has this value", and
`not_equals` and `not_contains` "does not have this value". On a
`richtext` field, `contains`, `not_contains` and `begins_with` read the text
without its tags, with `&amp;` and the like as the characters they stand for, as
`q` does. On a `custom` field only `contains` and `not_contains` work:
`contains` matches when one of its `text`, `textarea`, `slug` or `richtext`
fields contains the value, `not_contains` when none does; any other operator,
or `orders` on it, is `400 bad_query`. One of those fields is named through
its custom field, as `meta.title[contains]x`, and takes only `contains` and
`not_contains`. A `repeater` field is the same as a custom field, over the
fields of every row. A value for a
`number` field is a decimal of at most 64 characters, such as `42`, `-2.5` or
`1e3`. An unknown field in `filters`, `orders` or `include`, or a number field
given anything else, is `400 bad_query`.

**By slug.** A list model with a `slug` field (see
[SCHEMA.md](SCHEMA.md#field)) reaches a content at its slug as well as at its
id, and the reply is the same. The slug found is the published one; with the
content's `draftKey`, its draft's slug finds it too. A key that is not the
content's finds it by its published slug only, so a draft's slug is not given
away. Nothing found, a model without a slug field, or a slug two contents hold
(only contents stored before slugs were unique can) is `404`.

**Previews.** A content's draft is served by the delivery API to whoever has its
draft key. The editor's *Preview draft* link opens the model's `previewUrl` with
`{CONTENT_ID}`, `{CONTENT_SLUG}` and `{DRAFT_KEY}` filled in; the preview page
passes the key on as `draftKey`. Saving the draft again issues a new key, so an
old link stops working. The key opens only its own content's draft: the
references it embeds are published data, as publishing that one content would
show them, so a new content it links is published first to appear in the
preview.

## What comes back

A content is its fields plus the system fields:

```json
{
  "id": "k3x9m2qa7t0b",
  "title": "Hello",
  "slug": "hello",
  "cover": {
    "id": "01J8Q0Z5X2W3V4U5T6S7R8Q9P1",
    "url": "https://cms.example.com/media/website/01J8Q0Z5X2W3V4U5T6S7R8Q9P1.png",
    "filename": "cover.png", "mime": "image/png", "size": 12345,
    "width": 1200, "height": 630, "alt": "Cover", "createdAt": "2026-09-20T05:04:03.123Z"
  },
  "tags": ["p8f2w6zc1n4d"],
  "createdAt": "2026-09-20T05:04:03.123Z",
  "updatedAt": "2026-09-20T05:04:03.123Z",
  "publishedAt": "2026-09-20T05:04:03.123Z",
  "revisedAt": "2026-09-20T05:04:03.123Z"
}
```

- **References** are ids unless named in `include`. `include=tags,author.team`
  embeds `tags`, `author`, and `team` inside each `author`. Only reference
  fields can be included; a reference inside a custom field is named through it,
  as `meta.author`, and a path that ends at the custom field or at anything else
  inside it is `400 bad_query`. A reference in a repeater's rows is named
  through the repeater, as `blocks.by`, and embedded in each row whose custom
  field has a reference named `by`; the other rows are left as they are, and a
  path that reaches no reference is `400 bad_query`. What is embedded is the published data, even
  when the request carries a `draftKey`; an embedded content carries no draft
  key. A referenced content that is missing or unpublished drops out
  of a `many` field and becomes `null` in a single one.
- **Media** fields are always expanded to the media object, with an absolute
  `url`; one whose file is gone is `null`, and drops out of a `many` field, whose
  media keep their order.
- **Rich text** is HTML whose `/media/` sources are rewritten to absolute URLs,
  so it renders on any site.
- A **custom field** is an object of its fields' values, and the rules above
  apply to the fields inside it.
- A **repeater** is an array of rows, each an object naming its custom field in
  `fieldId` beside that custom field's fields, to which the rules above apply.
- **`fields`** applies last, after embedding and expansion, and narrows the
  content's own fields, a custom field or a repeater whole; the system fields (`id`,
  `createdAt`, `updatedAt`, `publishedAt`, `revisedAt`) are always there.
- `publishedAt` is the first publish, `revisedAt` the latest; both are `null`
  while a content is not published. Timestamps are ISO 8601 in UTC with
  milliseconds.
- A field the content has no value for is absent or `null`. What each type holds
  is in [SCHEMA.md, "Content values"](SCHEMA.md#content-values).

## Managing content

The admin API sees drafts as well, and returns contents in their stored shape:
both versions, with references and media as ids.

List contents are reached through their ids:

```
GET    /admin/api/{space}/lists/{model}                   every list content, drafts included
POST   /admin/api/{space}/lists/{model}                   create (a draft, unless "publish": true)
GET    /admin/api/{space}/lists/{model}/{id}
PATCH  /admin/api/{space}/lists/{model}/{id}              save a draft
DELETE /admin/api/{space}/lists/{model}/{id}
POST   /admin/api/{space}/lists/{model}/{id}/publish
POST   /admin/api/{space}/lists/{model}/{id}/unpublish
POST   /admin/api/{space}/lists/{model}/{id}/discard-draft
POST   /admin/api/{space}/lists/{model}/{id}/draft-key    the key for a preview URL
```

A list content is also read, saved and deleted at its slug, found by its
published slug or its draft's; the rest is done at its id:

```
GET    /admin/api/{space}/lists/{model}/slugs/{slug}
PATCH  /admin/api/{space}/lists/{model}/slugs/{slug}      save a draft
DELETE /admin/api/{space}/lists/{model}/slugs/{slug}
```

An object is part of its model, and is reached through the model:

```
GET    /admin/api/{space}/objects/{model}                 the object
PATCH  /admin/api/{space}/objects/{model}                 save a draft
POST   /admin/api/{space}/objects/{model}/publish
POST   /admin/api/{space}/objects/{model}/unpublish
POST   /admin/api/{space}/objects/{model}/discard-draft
POST   /admin/api/{space}/objects/{model}/draft-key       the key for a preview URL
```

Until its first write an object model has no object, and `GET` is a `404`. The
first `PATCH`, or a `publish` with `data`, makes it; it is not created with
`POST`. It is never deleted: it goes when its model does. Its id does not reach
it — an object model is not found under `lists/` — and a list model is not found
under `objects/` (`404`).

```json
{
  "id": "k3x9m2qa7t0b",
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

  An object has no delete.

- Saving a draft (`PATCH`, `{"data": {…}}`) **merges** onto the current draft, or
  the published data when there is none: keys given replace, `null` removes a key.
  When the result is what the content holds already, nothing is written (no
  revision, no webhook); when it is the published data again, the draft is
  dropped, as `discard-draft` would.
- Publishing takes `data` when given, else the draft, else re-publishes.
- A content's id is made by the server: 12 lowercase letters and digits, drawn
  at random. Ids from before stay as they were: 26-character ULIDs, or up to 64
  letters, digits, `-` and `_` when the content was created with its own.
  Creating a list content cannot give `id` (`400`; `null` is as absent), but
  may give the four timestamps, for imports that keep another system's dates. An id is the space's own: another
  space may hold a content of the same id. A timestamp needs a date, a time and
  an offset or `Z`, and is stored in UTC with milliseconds.
- An object model holds one object. Two first writes at once make only one: the
  other is refused (`409 object_exists`).
- A content another content refers to, in its published data or its draft,
  through a `reference` field of the current schema (one inside a custom field
  or a repeater's rows too), cannot be deleted, nor
  unpublished while it is published (`409 in_use`, naming how many). Take the
  reference out of those contents — and publish them, when it is in their
  published data — first. An id left in a field a deploy removed does not count.

The schema itself is deployed with `PUT /admin/api/{space}/schema` and previewed
with `POST /admin/api/{space}/schema/plan`: see [SCHEMA.md](SCHEMA.md), and
`koya plan` / `koya deploy` in koya-ts-sdk.

## Media

`POST /admin/api/{space}/media` takes `multipart/form-data` with one or more
`file` parts and an optional `alt`: PNG, JPEG, GIF or WebP, up to 20 MB each and
20 MB together, the type decided by the file's leading bytes. A JPEG, PNG or
WebP is stored without its metadata (EXIF, XMP, text): the camera, the time and
the GPS position are gone, and only the orientation and the colour profile stay.
The pixels are not touched. The answer is `{"media": [...]}`; put a media object's `id` in a `media` field. A media still
used by a content, in a `media` or `richtext` field of the current schema (one
inside a custom field or a repeater's rows too), cannot be deleted (`409 in_use`); a value left in a
field a deploy removed does not count.

## Errors

Anything but a 2xx is the object below. A request body over 21 MB, on any
route, is answered with `413 too_large` before koya reads it.

```json
{ "error": { "code": "validation_failed", "message": "Content is invalid", "details": [ … ] } }
```

| Status | `code` | |
|---|---|---|
| 400 | `bad_request` `bad_json` `bad_query` `invalid_schema` | the request is malformed |
| 401 | `unauthorized` | no key, or a wrong one |
| 403 | `forbidden` | a key of another space; a space that does not exist is another space too |
| 404 | `not_found` | no such model, content or media |
| 409 | `conflict` `destructive_changes` `contents_do_not_fit` `in_use` `not_published` `no_draft` `object_exists` | refused as things stand |
| 413 | `too_large` | images over 20 MB, alone or together, or a request body over 21 MB |
| 422 | `validation_failed` `empty_file` `unsupported_type` | the content or file is not acceptable |
| 500 | `internal_error` | the message is only detailed with `KOYA_ENV=dev` |
| 503 | `unavailable` | `/health` only: the database cannot be read |

Three codes carry `details`: `validation_failed` lists
`{"field", "code", "message"}` for each problem (the codes are in
[SCHEMA.md](SCHEMA.md#content-values)), and `destructive_changes` and
`contents_do_not_fit` list the changes a deploy refused, the latter with the
contents that do not fit them (see [SCHEMA.md](SCHEMA.md#changes)).

## Webhooks

Webhooks are part of the schema (`webhooks` in [SCHEMA.md](SCHEMA.md#webhook)).
Every webhook is POSTed **every event** of every model — or only of the models
its `only` names — and the payload says which:

```json
{
  "space": "website",
  "model": "blog",
  "id": "k3x9m2qa7t0b",
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
