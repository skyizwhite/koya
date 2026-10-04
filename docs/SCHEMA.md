# The schema format

A koya schema is the JSON document that `koya deploy` sends to
`PUT /admin/api/{space}/schema` and that `GET /admin/api/{space}/schema` returns.
It describes **one space**: the space itself is made in the admin UI and named by
the URL, so the document carries neither its name nor anything else about it. The
server stores it as is and generates the admin UI's forms, the delivery API's
shapes and content validation from it. This page specifies that document, version
`koyaSchema: 1`. In a TypeScript site it is what `defineSchema` in
`koya.config.ts` holds, typed field by field — see
[koya-ts-sdk](https://github.com/skyizwhite/koya-ts-sdk); the endpoints are in
[API.md](API.md) and [openapi.yaml](openapi.yaml).

Keys are camelCase. Names are checked with the rules below; a document that
breaks any of them is rejected whole with `400 invalid_schema` and a message
naming the problem.

- [Document](#document)
- [Webhook](#webhook)
- [Model](#model)
- [Field](#field)
- [Custom field](#custom-field)
- [Renames](#renames)
- [Content values](#content-values)
- [Changes](#changes)
- [Example](#example)

## Document

```
{
  "koyaSchema": 1,
  "webhooks": [ …webhook… ],
  "models": [ …model… ],
  "customFields": [ …custom field… ]
}
```

| Key | Type | Rules |
|---|---|---|
| `koyaSchema` | integer | must be `1` |
| `webhooks` | array of [webhook](#webhook) | optional; labels unique |
| `models` | array of [model](#model) | optional; names unique |
| `customFields` | array of [custom field](#custom-field) | optional; names unique; omitted from the output when empty |

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
| `url` | string | starts with `http://` or `https://`; receives the POST |
| `only` | array of string | optional; model names, each one a model of this schema, no duplicates |

Every webhook belongs to the space and fires for **every model**, unless `only`
narrows it to the models it names. Absent, empty or missing `only` means every
model, including models added later.

Every webhook is sent every event -- `publish`, `unpublish`, `delete`, `draft`,
`discard` and `deploy` -- and the payload names the event; there is nothing to
subscribe to.
Any other key on input (older schemas carried an `events` list) is ignored.
The payload is described in [API.md](API.md#webhooks).

Where a webhook is sent is checked each time, on the addresses its host resolves
to:

- A link-local, multicast, unspecified or reserved address — such as a cloud's
  metadata address, `169.254.169.254` — is never sent to, nor are the metadata
  addresses outside those ranges (`100.100.100.200`, `168.63.129.16`,
  `fd00:ec2::254`); the call is logged as one that never arrived. An IPv4
  address carried in IPv6 (`::ffff:0:0/96`, NAT64 `64:ff9b::/96` and
  `64:ff9b:1::/48`, 6to4 `2002::/16`) is judged as itself.
- A loopback or private address (`127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`,
  `192.168.0.0/16`, `100.64.0.0/10`, `::1`, `fc00::/7`), such as a site's
  container beside the server, is sent to, and only the status of its answer is
  kept, not the body.
- A plain `http` call goes to the address that was checked, with the host in
  `Host`; an `https` call goes by name, for its certificate.
- A redirect is not followed: it is logged as a refusal, with the address it
  pointed to, so the webhook's URL can be changed to go there.

## Model

```
{
  "name": "blog",
  "kind": "list",
  "previewUrl": "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}",
  "publicUrl": "https://example.com/blog/{CONTENT_ID}",
  "label": "title",
  "fields": [ …field… ]
}
```

| Key | Type | Rules |
|---|---|---|
| `name` | string | `^[a-z][a-z0-9-]*$` |
| `kind` | string | `list` (any number of contents) or `object` (exactly one) |
| `fields` | array of [field](#field) | optional; names unique within the model |
| `previewUrl` | string | optional; template for the editor's *Preview draft* link, starting with `http://` or `https://` |
| `publicUrl` | string | optional; template for the editor's *Published page* link, starting with `http://` or `https://` |
| `label` | string | optional; a `text` or `slug` field of this model (not one inside a custom field), whose value the admin UI shows for a content. Without it a content is shown by its id |
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
| *options* | | any other key must be an option allowed for `type`, or `was` or `help`, which every type takes |

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
| `custom` | `required` `customField` |

| Option | Type | Rules |
|---|---|---|
| `required` `unique` `integer` `many` `default` | boolean | |
| `maxLength` | integer | positive |
| `min` `max` | number | |
| `pattern` | string | a Perl-style regular expression, checked when the schema is deployed |
| `options` | array of string | non-empty, no duplicates, no commas in an option (checked when the schema is deployed); **required** on `select` |
| `model` | string | a model name; **required** on `reference`, and the model must exist in the same space |
| `from` | string | a field name; **required** on `slug`, and must name a `text` or `textarea` field of the same model other than the slug itself |
| `customField` | string | a custom field name; **required** on `custom`, and must name a [custom field](#custom-field) of the same schema |
| `was` | string | a field name other than this one and not a system field, see [Renames](#renames) |
| `help` | string | non-empty; shown under the field's name in the editor, to say what the field expects |

`default: true` on a `boolean` field sets it to `true` on a new content whose
`data` does not mention it; an explicit `false` is kept. On output the
options of a field are written in alphabetical key order, so two equal fields
serialize identically.

## Custom field

A custom field is a group of fields defined once in the document's
`customFields` and used by any number of models through a field of type
`custom`:

```json
{
  "name": "seo",
  "fields": [
    {"name": "title", "type": "text", "maxLength": 60},
    {"name": "image", "type": "media", "help": "1200x630"}
  ]
}
```

| Key | Type | Rules |
|---|---|---|
| `name` | string | `^[a-z][a-zA-Z0-9]*$` |
| `fields` | array of [field](#field) | at least one, and not booleans alone; names unique within the custom field |

Its fields are written as a model's, with every type and its options except
`slug` and `custom`, and without `unique` or `was`: renaming a custom field, or a
field inside one, is a removal and an addition.

A model uses it by name, and its field JSON holds only that name; the fields come
from the definition:

```json
{"name": "meta", "type": "custom", "customField": "seo"}
```

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
destructive and needs no `force`; changing the type at the same time still is,
and tightening the options is checked against the stored content (see
[Changes](#changes)). Either is reported as its own change.

`was` is an instruction to the deploy, not part of the shape:

- The server stores the model and the field without it, so `GET
  /admin/api/{space}/schema` never returns one and `pull` never brings one back.
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
| `datetime` | ISO 8601 with seconds optional and an explicit zone: `2026-09-20T10:00:00.000Z`, `2026-09-20T19:00+09:00`. Stored to the minute in UTC: seconds are dropped, so the second example is kept as `2026-09-20T10:00:00.000Z` | |
| `select` | one of `options` (`option`) | |
| `media` `reference` | an id: `^[A-Za-z0-9_-]{1,64}$` | |
| `custom` | an object of its fields' values, each checked as above; an error names the path, such as `meta.title`, and a key that is not one of its fields is `unknown_field` | |

A `many` field takes an array of such values (`type` when not an array). A wrong
type is `type`. `unique` is checked by the server against both the draft and the
published data of the model's other contents (`unique`). A blank `slug` is filled
from its `from` field before validation.

A `custom` value is blank itself when every field inside but its booleans is
blank: a box checked alone gives it no value. A `required` field inside a custom
field is required only once the object has a value, and a `boolean` field's `default` inside applies when the object is
given.

Validation failures come back as `422 validation_failed` with
`details: [{"field", "code", "message"}, …]`.

## Changes

`POST /admin/api/{space}/schema/plan` and `PUT /admin/api/{space}/schema` describe
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
| `change_kind` | a model's `kind` changed; its contents are deleted | **yes** |
| `change_field_type` | a field's `type` changed, the `model` a `reference` points at, or the `customField` a `custom` field uses | **yes** |
| `change_field_options` | a field's options changed | no; when tightened, refused while stored content does not fit, see below |
| `change_model_options` | `previewUrl` / `publicUrl` / `label` changed | no |
| `change_webhooks` | the space's webhooks changed | no |
| `change_custom_fields` | the definitions in `customFields` changed | no |

Options are **tightened** when they can reject content the old ones accepted:
`required`, `unique` or `integer` turned on, `many` switched either way,
`maxLength` or `max` lowered, `min` raised, `pattern` changed, or a value dropped
from `options`.

A custom field's definition is kept as deployed, used by a model or not. For
every field that uses a changed custom field, the changes to the fields inside
are listed too, as `add_field`, `remove_field`, `change_field_type` or
`change_field_options` with the path `model.field.subfield`, and judged as at the
top.

A tightened option, or a `required` field added to a model that has contents, is
checked against every stored published object and draft of the model (not the
history), unless the same deploy changes the model's `kind`, which deletes them. A value that does not fit it is listed under the change, as
`"misfits": [{"id", "field", "version", "message"}]` with `version` `published`
or `draft`, and its description ends with how many contents do not fit. A deploy
with any is refused with `409 contents_do_not_fit`, `force` or not and before
`destructive_changes` is, and the
changes in `details`: change those contents under the schema as it is, then
deploy again. Stored content always fits the schema it is stored under. A
tightened option that every stored value fits is applied without `force`.

`path` is `webhooks` (the space's own), `customFields`, `model`, `model.field`
or, inside a custom field, `model.field.subfield`, where a misfit's `field` is
`field.subfield`, such as `card.title`. A `PUT` whose changes
include a destructive one is refused with `409 destructive_changes` (the changes
in `details`) unless `?force=true` is given. Applying a schema carries a rename
through the stored content, and takes the values of a removed field, or of one
whose type or target model changed (inside a custom field too), out of every published object, draft and
revision, in the same transaction. Changing a model's `kind` makes it anew: its
contents and their history are deleted, as if the model were removed and added
again under the same name. A field added later under that name starts
empty.

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
      "label": "title",
      "previewUrl": "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}",
      "fields": [
        {"name": "title",   "type": "text", "required": true},
        {"name": "slug",    "type": "slug", "from": "title", "unique": true},
        {"name": "cover",   "type": "media"},
        {"name": "content", "type": "richtext"},
        {"name": "tags",    "type": "reference", "many": true, "model": "tag"},
        {"name": "meta",    "type": "custom", "customField": "seo"}
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
  ],
  "customFields": [
    {
      "name": "seo",
      "fields": [
        {"name": "title", "type": "text", "maxLength": 60},
        {"name": "image", "type": "media"}
      ]
    }
  ]
}
```
