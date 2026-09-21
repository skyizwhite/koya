# The schema format

A koya schema is the JSON document that `(koya:deploy)` sends to
`PUT /admin/api/schema` and that `GET /admin/api/schema` returns. The server
stores it as is and generates the admin UI's forms, the delivery API's shapes and
content validation from it. This page specifies that document, version
`koyaSchema: 1`, for anyone producing or consuming it without the Lisp library —
the Lisp DSL that produces it is in [CLIENT.md](CLIENT.md), the endpoints in
[openapi.yaml](openapi.yaml).

Keys are camelCase. Names are checked with the rules below; a document that
breaks any of them is rejected whole with `400 invalid_schema` and a message
naming the problem.

- [Document](#document)
- [Space](#space)
- [Webhook](#webhook)
- [Model](#model)
- [Field](#field)
- [Content values](#content-values)
- [Changes](#changes)
- [Example](#example)

## Document

```json
{"koyaSchema": 1, "spaces": [ …space… ]}
```

| Key | Type | Rules |
|---|---|---|
| `koyaSchema` | integer | must be `1` |
| `spaces` | array of [space](#space) | may be empty or absent; names unique |

The array order is the order the admin UI shows.

## Space

```json
{"name": "website", "webhooks": [ …webhook… ], "models": [ …model… ]}
```

| Key | Type | Rules |
|---|---|---|
| `name` | string | `^[a-z][a-z0-9-]*$`; used in URLs |
| `webhooks` | array of [webhook](#webhook) | optional; fire for every model of the space; labels unique |
| `models` | array of [model](#model) | optional; names unique within the space |

## Webhook

```json
{"label": "revalidate", "url": "https://example.com/api/revalidate", "events": ["publish", "unpublish", "delete"]}
```

| Key | Type | Rules |
|---|---|---|
| `label` | string | non-empty; defaults to `url` when absent on input |
| `url` | string | non-empty; receives the POST |
| `events` | array of string | subset of `publish`, `unpublish`, `delete`, `draft`; at least one; defaults to all but `draft` when absent |

On input a webhook may also be a bare URL string, which stands for
`{"label": url, "url": url}` with the default events. On output `events` is always
present, without duplicates and in the canonical order above.

What each event means, and the payload a webhook receives, is described in
[CLIENT.md](CLIENT.md#webhooks).

## Model

```json
{"name": "blog", "kind": "list",
 "previewUrl": "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}",
 "publicUrl": "https://example.com/blog/{CONTENT_ID}",
 "webhooks": [ … ],
 "fields": [ …field… ]}
```

| Key | Type | Rules |
|---|---|---|
| `name` | string | `^[a-z][a-z0-9-]*$` |
| `kind` | string | `list` (any number of contents) or `object` (exactly one) |
| `fields` | array of [field](#field) | optional; names unique within the model |
| `previewUrl` | string | optional; template for the editor's *Preview draft* link |
| `publicUrl` | string | optional; template for the editor's *Published page* link |
| `webhooks` | array of [webhook](#webhook) | optional; added to the space's for this model only |

The URL templates substitute `{CONTENT_ID}` and `{DRAFT_KEY}`. Optional keys are
omitted from the output when they have no value.

## Field

```json
{"name": "tags", "type": "reference", "model": "tag", "many": true}
```

| Key | Type | Rules |
|---|---|---|
| `name` | string | `^[a-z][a-zA-Z0-9]*$`; not one of the system fields |
| `type` | string | one of the types below |
| *options* | | any other key must be an option allowed for `type` |

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

`default` is accepted but not applied by the current server. On output the
options of a field are written in alphabetical key order, so two equal fields
serialize identically.

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

`POST /admin/api/schema/plan` and `PUT /admin/api/schema` describe the difference
between the stored schema and the one sent as a list of **changes**:

```json
{"op": "remove_field", "path": "website.blog.summary", "destructive": true,
 "description": "! - website.blog.summary (text)"}
```

| `op` | Meaning | Destructive |
|---|---|---|
| `add_space` `add_model` `add_field` | something new | no |
| `remove_space` `remove_model` `remove_field` | something gone | **yes** |
| `change_kind` | a model's `kind` changed | **yes** |
| `change_field_type` | a field's `type` changed | **yes** |
| `change_field_options` | a field's options changed | yes when tightened, see below |
| `change_model_options` | `previewUrl` / `publicUrl` changed | no |
| `change_webhooks` `change_model_webhooks` | a space's / a model's webhooks changed | no |

Options are **tightened** when they can reject content the old ones accepted:
`required`, `unique` or `integer` turned on, `many` switched either way,
`maxLength` or `max` lowered, `min` raised, `pattern` changed, or a value dropped
from `options`.

`path` is `space`, `space.model` or `space.model.field`. A `PUT` whose changes
include a destructive one is refused with `409 destructive_changes` (the changes
in `details`) unless `?force=true` is given. Applying a schema never touches
stored content: rows that no longer fit stay as they are.

## Example

```json
{
  "koyaSchema": 1,
  "spaces": [
    {
      "name": "website",
      "webhooks": [
        {"label": "revalidate", "url": "https://example.com/api/revalidate",
         "events": ["publish", "unpublish", "delete"]}
      ],
      "models": [
        {
          "name": "blog",
          "kind": "list",
          "publicUrl": "https://example.com/blog/{CONTENT_ID}",
          "previewUrl": "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}",
          "webhooks": [
            {"label": "preview-build", "url": "https://preview.example/hook", "events": ["draft"]}
          ],
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
  ]
}
```
