# The schema format

A koya schema is the JSON document that `(koya:deploy)` sends to
`PUT /admin/api/schema/{space}` and that `GET /admin/api/schema/{space}` returns.
It describes **one space**: the space itself is made in the admin UI and named by
the URL, so the document carries neither its name nor anything else about it. The
server stores it as is and generates the admin UI's forms, the delivery API's
shapes and content validation from it. This page specifies that document, version
`koyaSchema: 1`, for anyone producing or consuming it without the Lisp library —
the Lisp DSL that produces it is in [CLIENT.md](CLIENT.md), the endpoints in
[openapi.yaml](openapi.yaml).

Keys are camelCase. Names are checked with the rules below; a document that
breaks any of them is rejected whole with `400 invalid_schema` and a message
naming the problem.

- [Document](#document)
- [Webhook](#webhook)
- [Model](#model)
- [Field](#field)
- [Renames](#renames)
- [Content values](#content-values)
- [Changes](#changes)
- [Example](#example)

## Document

```
{
  "koyaSchema": 1,
  "webhooks": [ …webhook… ],
  "models": [ …model… ]
}
```

| Key | Type | Rules |
|---|---|---|
| `koyaSchema` | integer | must be `1` |
| `webhooks` | array of [webhook](#webhook) | optional; labels unique |
| `models` | array of [model](#model) | optional; names unique |

The `models` order is the order the admin UI shows. A deploy to a space that does
not exist is refused with `404 not_found`; it never makes one.

## Webhook

```json
{
  "label": "revalidate",
  "url": "https://example.com/api/revalidate",
  "only": ["blog", "about"]
}
```

| Key | Type | Rules |
|---|---|---|
| `label` | string | non-empty; defaults to `url` when absent on input |
| `url` | string | non-empty; receives the POST |
| `only` | array of string | optional; model names, each one a model of this schema, no duplicates |

Every webhook belongs to the space and fires for **every model**, unless `only`
narrows it to the models it names. Absent, empty or missing `only` means every
model, including models added later.

Every webhook is sent every event -- `publish`, `unpublish`, `delete` and
`draft` -- and the payload names the event; there is nothing to subscribe to.
Any other key on input (older schemas carried an `events` list) is ignored.
The payload is described in [CLIENT.md](CLIENT.md#webhooks).

## Model

```
{
  "name": "blog",
  "kind": "list",
  "previewUrl": "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}",
  "publicUrl": "https://example.com/blog/{CONTENT_ID}",
  "fields": [ …field… ]
}
```

| Key | Type | Rules |
|---|---|---|
| `name` | string | `^[a-z][a-z0-9-]*$` |
| `kind` | string | `list` (any number of contents) or `object` (exactly one) |
| `fields` | array of [field](#field) | optional; names unique within the model |
| `previewUrl` | string | optional; template for the editor's *Preview draft* link |
| `publicUrl` | string | optional; template for the editor's *Published page* link |
| `was` | string | optional; the name this model had, see [Renames](#renames) |

The URL templates substitute `{CONTENT_ID}` and `{DRAFT_KEY}`. Optional keys are
omitted from the output when they have no value. A model carries no webhooks of
its own: a `webhooks` key here, which schemas written before they all moved to
the space had, is ignored on input.

## Field

```json
{
  "name": "tags",
  "type": "reference",
  "model": "tag",
  "many": true
}
```

| Key | Type | Rules |
|---|---|---|
| `name` | string | `^[a-z][a-zA-Z0-9]*$`; not one of the system fields |
| `type` | string | one of the types below |
| *options* | | any other key must be an option allowed for `type`, or `was`, which every type takes |

`id`, `createdAt`, `updatedAt`, `publishedAt` and `revisedAt` are **system
fields**: every content has them, the server manages them, and a field may not
take their names.

| Type | Allowed options |
|---|---|
| `text` | `required` `maxLength` `pattern` `unique` |
| `textarea` | `required` `maxLength` |
| `richtext` | `required` |
| `number` | `required` `min` `max` `integer` |
| `boolean` | `required` `default` |
| `date` | `required` |
| `datetime` | `required` |
| `select` | `required` `options` `many` |
| `media` | `required` |
| `reference` | `required` `model` `many` |
| `slug` | `required` `from` `unique` `pattern` |

| Option | Type | Rules |
|---|---|---|
| `required` `unique` `integer` `many` `default` | boolean | |
| `maxLength` | integer | positive |
| `min` `max` | number | |
| `pattern` | string | a valid `cl-ppcre` (Perl-style) regular expression |
| `options` | array of string | non-empty, no duplicates; **required** on `select` |
| `model` | string | a model name; **required** on `reference`, and the model must exist in the same space |
| `from` | string | a field name; **required** on `slug`, and must name a `text` or `textarea` field of the same model other than the slug itself |
| `was` | string | a field name other than this one and not a system field, see [Renames](#renames) |

`default: true` on a `boolean` field sets it to `true` on a new content whose
`data` does not mention it; an explicit `false` is kept. On output the
options of a field are written in alphabetical key order, so two equal fields
serialize identically.

## Renames

A model or a field is matched by its name, so renaming one reads as a removal and
an addition: the model's contents go with it, and a renamed field's values are
left under the old key, where the editor cannot see them.

`was` says it is the same thing under a new name:

```json
{
  "name": "article",
  "kind": "list",
  "was": "post",
  "fields": [{"name": "subtitle", "type": "text", "was": "lede"}]
}
```

The deploy renames it and moves the stored content with it — the contents to the
new model name, the key in every published object and draft — in the same
transaction as the schema write. Nothing is lost, so a rename is **not**
destructive and needs no `force`; changing the type or tightening the options at
the same time still is, and is reported as its own change.

`was` is an instruction to the deploy, not part of the shape:

- The server stores the model and the field without it, so `GET
  /admin/api/schema/{space}` never returns one and `pull` never brings one back.
  Leaving it in the source is harmless, and so is dropping it once **every space
  the schema is deployed to** has had the rename — a space still at the old shape
  reads the document without `was` as a removal and an addition.
- It must name something else: not the field or model itself, not a system field,
  and not another field or model the schema still declares. Two fields cannot be
  renamed from the same one.
- If the new name already exists in the deployed schema, the deploy falls back to
  a removal and an addition, which needs `force`.

## Content values

The schema also fixes what a content's `data` object may hold. Every key must be
a field of the model (`unknown_field` otherwise); a value that is `null`, a
whitespace-only string, or `[]` on a `many` field counts as **blank**, and
`required` rejects blank (`required`). Booleans are exempt: a missing or `null`
boolean is `false`. Otherwise:

| Type | Value | Checks (error `code`) |
|---|---|---|
| `text` `textarea` `richtext` | string | `maxLength` (`max_length`), `pattern` (`pattern`) |
| `slug` | string `^[a-z0-9]+(-[a-z0-9]+)*$` (`slug`) | as `text` |
| `number` | number | `integer` (`integer`), `min` (`min`), `max` (`max`) |
| `boolean` | `true` / `false` | |
| `date` | `"YYYY-MM-DD"`, a real calendar date | |
| `datetime` | ISO 8601 with seconds optional and an explicit zone: `2026-09-20T10:00:00.000Z`, `2026-09-20T19:00+09:00` | |
| `select` | one of `options` (`option`) | |
| `media` `reference` | an id: `^[A-Za-z0-9_-]{1,64}$` | |

A `many` field takes an array of such values (`type` when not an array). A wrong
type is `type`. `unique` is checked by the server against both the draft and the
published data of the model's other contents (`unique`). A blank `slug` is filled
from its `from` field before validation.

Validation failures come back as `422 validation_failed` with
`details: [{"field", "code", "message"}, …]`.

## Changes

`POST /admin/api/schema/{space}/plan` and `PUT /admin/api/schema/{space}` describe
the difference between the space's stored schema and the one sent as a list of
**changes**:

```json
{
  "op": "remove_field",
  "path": "blog.summary",
  "destructive": true,
  "description": "! - blog.summary (text)"
}
```

| `op` | Meaning | Destructive |
|---|---|---|
| `add_model` `add_field` | something new | no |
| `remove_model` `remove_field` | something gone | **yes** |
| `rename_model` `rename_field` | a `was` was matched, see [Renames](#renames) | no |
| `change_kind` | a model's `kind` changed | **yes** |
| `change_field_type` | a field's `type` changed | **yes** |
| `change_field_options` | a field's options changed | yes when tightened, see below |
| `change_model_options` | `previewUrl` / `publicUrl` changed | no |
| `change_webhooks` | the space's webhooks changed | no |

Options are **tightened** when they can reject content the old ones accepted:
`required`, `unique` or `integer` turned on, `many` switched either way,
`maxLength` or `max` lowered, `min` raised, `pattern` changed, or a value dropped
from `options`.

`path` is `webhooks` (the space's own), `model` or `model.field`. A `PUT` whose changes
include a destructive one is refused with `409 destructive_changes` (the changes
in `details`) unless `?force=true` is given. Applying a schema touches stored
content only to carry a rename through; otherwise rows that no longer fit stay as
they are.

## Example

```json
{
  "koyaSchema": 1,
  "webhooks": [
    {"label": "revalidate", "url": "https://example.com/api/revalidate"},
    {"label": "preview-build", "url": "https://preview.example/hook", "only": ["blog"]}
  ],
  "models": [
    {
      "name": "blog",
      "kind": "list",
      "publicUrl": "https://example.com/blog/{CONTENT_ID}",
      "previewUrl": "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}",
      "fields": [
        {"name": "title",   "type": "text", "required": true},
        {"name": "slug",    "type": "slug", "from": "title", "unique": true},
        {"name": "cover",   "type": "media"},
        {"name": "content", "type": "richtext"},
        {"name": "tags",    "type": "reference", "many": true, "model": "tag"}
      ]
    },
    {
      "name": "tag",
      "kind": "list",
      "fields": [{"name": "name", "type": "text", "required": true}]
    },
    {
      "name": "about",
      "kind": "object",
      "fields": [{"name": "body", "type": "richtext"}]
    }
  ]
}
```
