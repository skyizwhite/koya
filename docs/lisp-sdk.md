# The Common Lisp SDK

For a site written in Common Lisp, this repository's `koya` system is to it what
[koya-ts-sdk](https://github.com/skyizwhite/koya-ts-sdk) is to a TypeScript
site. It holds three things:

- a **schema DSL** — `defmodel`, `defwebhooks`, `webhook` — that defines the
  space's models as code in the site's own repository;
- **`plan` / `deploy` / `pull`**, which compare that schema with the one the
  server stores and push it across;
- an **HTTP client** for reading published content, managing content, keys and
  media.

Everything is meant to be called from the REPL or from the site's own code; there
is no CLI. What the calls do on the server — queries, what comes back, errors,
webhooks — is in [API.md](API.md); the admin UI, which reads the deployed schema,
in [ADMIN-UI.md](ADMIN-UI.md).

- [Installing](#installing)
- [Configuration](#configuration)
- [Defining the schema](#defining-the-schema)
- [Field types and options](#field-types-and-options)
- [Webhooks](#webhooks)
- [Renaming a model or a field](#renaming-a-model-or-a-field)
- [Deploying the schema](#deploying-the-schema)
- [Reading content](#reading-content)
- [Managing content](#managing-content)
- [Delivery keys and the webhook secret](#delivery-keys-and-the-webhook-secret)
- [Media](#media)
- [Errors](#errors)
- [Lisp and JSON](#lisp-and-json)
- [The HTTP API underneath](#the-http-api-underneath)
- [License](#license)

## Installing

koya is not in Quicklisp; depend on the repository with qlot. In the site's
`qlfile`:

```
git koya https://github.com/skyizwhite/koya.git
```

then `qlot install` (and `qlot update koya` to pick up later changes). Add `koya`
to the site's `.asd` `:depends-on`, and `(ql:quickload :koya)` in the REPL.

All symbols below live in the `koya` package, which re-exports `koya/core`,
`koya/config` and `koya/client`. The server system (`koya-server`) is a separate
system; a site never loads it.

## Configuration

```lisp
(koya:configure :base-url "https://cms.example.com"
                :management-key "koya_mgmt_..."  ; schema, content and media calls
                :delivery-key "koya_..."  ; reading published content
                :space    "website")   ; the space every call works in
```

Each setting is a special variable with an environment-variable fallback, read at
call time:

| Variable | Environment | Used by |
|---|---|---|
| `koya:*base-url*` | `KOYA_URL` | everything |
| `koya:*management-key*` | `KOYA_MANAGEMENT_KEY` | `plan`, `deploy`, `pull`, content/keys/media management |
| `koya:*delivery-key*` | `KOYA_DELIVERY_KEY` | `get-list`, `get-item`, `get-object` |
| `koya:*space*` | `KOYA_SPACE` | the default for every `:space` argument |

**The space is made in the admin UI first**, and both keys are then made on its
*Keys* page. A management key belongs to that one space and reaches nothing else,
so a site's `.env` cannot touch another site's content; the owner secret
(`KOYA_SECRET`) only logs into the admin UI and is not accepted here. Note that
the server's own public URL is `KOYA_BASE_URL`; the client reads `KOYA_URL`, so
both can sit in one `.env` without colliding. A missing setting
signals an error naming what to set. Calls that take `:space` accept a symbol or
a string and downcase it, and default to `koya:*space*`.

## Defining the schema

A project defines the models of one space, so no definition names the space —
`koya:*space*` says which one a deploy goes to. Definitions are collected in an
in-memory registry; re-evaluating a form replaces the previous definition of the
same name, so the schema can be edited live from the REPL.

```lisp
;; every model of the space, on every event; :only narrows one -- see Webhooks below
(defwebhooks (webhook "revalidate" "https://example.com/api/revalidate")
             (webhook "preview-build" "https://preview.example/hook" :only 'blog))

(defmodel blog (:kind :list
                :label       title
                :public-url  "https://example.com/blog/{CONTENT_ID}"
                :preview-url "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}")
  (title   :text :required t)
  (slug    :slug :from title :unique t)
  (cover   :media)
  (content :richtext)
  (tags    :reference :model tag :many t))

(defmodel tag (:kind :list)
  (name :text :required t))

(defmodel about (:kind :object)
  (body :richtext))
```

- **`(defwebhooks &rest webhooks)`** — each form is evaluated and must produce a
  `(webhook label url &key only)`. Re-evaluating replaces the whole list.
- **`(defmodel name (&key kind preview-url public-url label was) &body fields)`** —
  `:kind` is required and is `:list` (many contents) or `:object` (exactly one).
  The URL templates are evaluated; each field form `(name type . options)` is
  taken literally. A model carries no webhooks: they all live in `defwebhooks`.
- **`:was`**, on the model or on a field, names what it used to be called, so
  that a deploy renames it instead of dropping it — see
  [Renaming a model or a field](#renaming-a-model-or-a-field).
- **`:preview-url` / `:public-url`** are templates for the editor's two links.
  `{CONTENT_ID}` and `{DRAFT_KEY}` are substituted.
- **`:label`** names the `:text` or `:slug` field whose value the admin UI shows
  for a content — in the list's reference previews, the reference dropdowns and
  the history. It is taken literally, like a field name (`:label title`).
  Without it a content is shown by its id; no field is guessed at.

Naming rules, checked as the schema is built:

| Name | Shape | Notes |
|---|---|---|
| model | `^[a-z][a-z0-9-]*` | it appears in URLs |
| field | `^[a-z][a-zA-Z0-9]*` | a kebab-case symbol is camelised: `(published-at :datetime)` becomes `publishedAt` |

`id`, `createdAt`, `updatedAt`, `publishedAt` and `revisedAt` are system fields
that every content already has; declaring one is an error.

Other helpers: `(koya:current-schema)` returns the validated schema built so far,
`(koya:clear-schema)` empties the registry, and `(koya:find-model name)` looks a
definition up.

## Field types and options

| Type | Options | Stored as |
|---|---|---|
| `:text` | `:required` `:max-length` `:pattern` `:unique` | string |
| `:textarea` | `:required` `:max-length` | string |
| `:richtext` | `:required` | HTML string |
| `:number` | `:required` `:min` `:max` `:integer` | number |
| `:boolean` | `:required` `:default` | true / false |
| `:date` | `:required` | `"YYYY-MM-DD"` |
| `:datetime` | `:required` | ISO 8601 with a zone, e.g. `"2026-09-20T10:00:00.000Z"` |
| `:select` | `:required` `:options` `:many` | one of `:options`, or an array of them |
| `:media` | `:required` | media id (expanded to an object by the delivery API) |
| `:reference` | `:required` `:model` `:many` | content id (embeddable with `include`) |
| `:slug` | `:required` `:from` `:unique` `:pattern` | lowercase-hyphen string |

- Every type also takes `:was`, which names the field this one was renamed from —
  see [Renaming a model or a field](#renaming-a-model-or-a-field).
- `:options` takes strings or symbols, which are downcased; `:model` and `:from`
  take a symbol or a string too.
- `:model` names another model of the same space; `:from` names a `:text` or
  `:textarea` field of the same model other than itself. Both are checked against
  the whole schema, so a typo fails before anything is sent.
- `:default t` on a `:boolean` sets the field to true on a new content that does
  not mention it (the editor starts with the box checked); an explicit `false` is
  kept.

What each type stores, what counts as blank, and how every option is enforced
(`:unique` across drafts and published data, `:pattern` as a `cl-ppcre` regex, a
blank `:slug` filled from `:from`, …) is specified in
[SCHEMA.md, "Content values"](SCHEMA.md#content-values).

## Webhooks

```lisp
(defwebhooks
  (webhook "revalidate" "https://example.com/api/revalidate")
  (webhook "preview-build" "https://preview.example/hook" :only 'blog)
  (webhook "reindex" "https://search.example/hook" :only '(blog tag)))
```

Every webhook belongs to the space and fires for **every model**. `:only` narrows
one to a model, or to a list of them; it takes symbols or strings, and each name
must be a model of the schema, so a typo fails before anything is sent. A webhook
without `:only` also covers models added later. Labels must be unique.

Every webhook is sent every event — `publish`, `unpublish`, `delete` and
`draft` — with the space's webhook secret in `X-KOYA-WEBHOOK-KEY`, which
`(koya:webhook-secret)` returns. The payload and when each event fires are in
[API.md, "Webhooks"](API.md#webhooks).

## Renaming a model or a field

Everything is matched by name, so renaming one in `defmodel` reads as a removal
and an addition: the model's contents go with it, and a renamed field's values
are left under the old key. `:was` says it is the same thing under a new name:

```lisp
(defmodel article (:kind :list :was post)   ; was (defmodel post ...)
  (title    :text :required t)
  (subtitle :text :was lede))               ; was (lede :text)
```

The deploy renames it and moves the content with it — the contents to the new
model, the key in every published object and draft — in the same transaction as
the schema write. Nothing is lost, so a rename is not destructive and needs no
`:force`; changing the type or tightening the options at the same time still is.

`:was` is an instruction to the deploy, not part of the schema: the server stores
the new name alone, so `pull` never brings one back. Leaving it in the source is
harmless, and so is deleting it — but only once **every space this schema goes
to** has had the rename. A space still at the old shape reads the version without
`:was` as a removal and an addition, and forcing that through takes its contents
with it.

What `:was` names must be something else: not the field or model itself, not a
system field, and not another field or model the schema still declares. The full
rules are in [SCHEMA.md, "Renames"](SCHEMA.md#renames).

## Deploying the schema

```lisp
(koya:plan)                ; the changes a deploy would apply; prints and returns them
(koya:deploy)              ; apply them
(koya:deploy :force t)     ; apply without asking about destructive changes
(koya:pull)                ; the schema the server currently stores, as a schema object
```

All four work on `koya:*space*`, or on the `:space` given to them. **The space
must already exist**: it is made in the admin UI, and a deploy to a name that has
none is refused with `404 not_found` rather than quietly making one, so a typo in
`KOYA_SPACE` cannot grow a second, empty space.

Both `plan` and `deploy` take `:schema` (defaulting to `(current-schema)`) and
`:stream`; `deploy` also takes `:confirm` (default `t`). When a deploy would
change something destructive the server refuses it; `deploy` then prints the
changes, marked with `!`, and asks — answering no returns `nil` and changes
nothing. With `:confirm nil` and no `:force` it gives up the same way, without
asking, so a script never applies a destructive change by accident.

Destructive means a change that can hide or invalidate content already stored:
removing a model or field, changing a kind or a field type, or tightening a
field's options. Deleting the space itself is not among them — that is done in
the admin UI, with its own confirmation. The exact list, and the shape of each
change, is in [SCHEMA.md, "Changes"](SCHEMA.md#changes). Apart from a rename
declared with `:was`, nothing migrates existing content: a deploy replaces the
stored schema, and rows that no longer fit it stay as they are.

Every deploy that changed something is recorded — what it changed, and the label
of the management key that sent it — and is read afterwards in the admin UI at
`/s/{space}/deploys`; see [ADMIN-UI.md](ADMIN-UI.md#schema-deploys).

## Reading content

These need a delivery key and return published data only.

```lisp
(koya:get-list 'blog)
(koya:get-list 'blog :query '(:limit 10 :orders "-publishedAt" :fields "id,title,publishedAt"))
(koya:get-list 'blog :query '(:include "tags"))          ; embed referenced contents
(koya:get-item 'blog "01J…")
(koya:get-item 'blog "01J…" :query '(:draft-key "…"))    ; preview a draft
(koya:get-object 'about)
```

Each takes `:space` to override the default. `get-list` returns a plist:

```lisp
(:contents ((:id "01J…" :title "…" :tags ("01J…") :published-at "2026-09-20T…Z" …) …)
 :total-count 42 :offset 0 :limit 10)
```

`get-item` and `get-object` return the content plist itself.

### Query options

The query parameters are the delivery API's, described in
[API.md, "Reading content"](API.md#reading-content); here is how to spell them.

`:query` is a kebab-case plist; keys are camelised and list values joined with
commas, so `:include '("tags" "author.team")` and `:include "tags,author.team"`
are the same.

| Key | Meaning |
|---|---|
| `:limit` | default 10, values above 100 are clamped to 100 |
| `:offset` | default 0 |
| `:orders` | comma-separated field names, `-` for descending; default newest published first |
| `:fields` | keys to keep in each content |
| `:filters` | see below |
| `:include` | reference fields to embed |
| `:draft-key` | with `get-item` / `get-object`, serves that content's draft |

`:filters` takes the delivery API's filter syntax as a string:

```lisp
(koya:get-list 'blog :query '(:filters "title[contains]lisp[and]publishedAt[exists]"))
```

### What comes back

The content objects of [API.md, "What comes back"](API.md#what-comes-back), as
plists (see [Lisp and JSON](#lisp-and-json)): references are ids unless
`:include`d, `:media` fields are expanded, and `:published-at` / `:revised-at`
are `nil` while a content is not published.

## Managing content

These use the management key and see drafts as well.

```lisp
(koya:list-contents 'blog :query '(:limit 100))   ; everything, drafts included
(koya:get-content 'blog "01J…")
(koya:create-content 'blog '(:title "Hello" :content "<p>…</p>"))            ; as a draft
(koya:create-content 'blog '(:title "Hello") :publish t)
(koya:update-content 'blog "01J…" '(:title "New title"))                     ; save a draft
(koya:publish-content 'blog "01J…")                                          ; publish the draft
(koya:publish-content 'blog "01J…" :data '(:title "…") :published-at "2026-09-20T10:00:00.000Z")
(koya:unpublish-content 'blog "01J…")
(koya:discard-draft 'blog "01J…")
(koya:delete-content 'blog "01J…")
(koya:draft-key 'blog "01J…")                     ; for a preview URL
```

- `list-contents` returns `(:contents (…) :total-count n :offset n :limit n)` where
  each content is `(:id … :status … :published {…} :draft {…} :draft-key … :created-at …)`.
  `status` is `"draft"`, `"published"` or `"published+draft"`.
- `update-content` **merges** the plist onto the current draft (or the published
  data when there is none); a key whose value is `nil` is removed. `publish-content`
  with `:data` replaces the data outright.
- `create-content` also takes `:id`, `:created-at`, `:updated-at`, `:published-at`
  and `:revised-at` — everything an import from another CMS needs to keep its ids
  and dates. Ids are 1–64 characters from `A-Za-z0-9_-`; without one a ULID is
  generated. A duplicate id is a 409.
- For an `:object` model, `create-content` updates the single existing content
  instead of adding one.
- Saving a draft issues a new draft key, so older preview links stop working.
- `discard-draft` needs a published content: there would be nothing left otherwise.

## Delivery keys and the webhook secret

```lisp
(koya:create-delivery-key :label "production site")  ; => (values "koya_…" "01J…"), shown once
(koya:list-delivery-keys)                            ; ((:id … :label … :created-at …) …)
(koya:delete-delivery-key "01J…")
(koya:webhook-secret)                            ; the X-KOYA-WEBHOOK-KEY of the space
```

Only a key's SHA-256 is stored, so a lost key cannot be read back — delete it and
create another. A key is valid for its space alone.

## Media

```lisp
(koya:upload-media #p"cover.png" :alt "Cover")
;; => (:id "01J…" :url "https://cms.example.com/media/website/01J….png" :filename "cover.png"
;;     :mime "image/png" :size 12345 :width 1200 :height 630 :alt "Cover" :created-at "…")
(koya:list-media :search "cover" :limit 60 :offset 0)   ; (:media (…) :total-count n :offset n :limit n)
(koya:get-media "01J…")                                 ; adds :references — how many contents use it
(koya:update-media "01J…" :alt "New alt text")
(koya:delete-media "01J…")
```

PNG, JPEG, GIF and WebP up to 20 MB each; the type is decided by reading the
file's leading bytes. `delete-media` refuses (409 `in_use`) while any content
still uses the file, as a `:media` value or inside rich text — `get-media`'s
`:references` is that count. Remove it from those contents first.

## Errors

Anything but a 2xx signals `koya:koya-error`, with readers
`koya-error-status`, `koya-error-code`, `koya-error-message` and
`koya-error-details`.

The status and code of every error each endpoint can return are listed in
[openapi.yaml](openapi.yaml). Two carry `details`: `422 validation_failed`, where
it is a list of `(:field … :code … :message …)` plists (codes in
[SCHEMA.md](SCHEMA.md#content-values)), and `409 destructive_changes` from
`deploy`, where it is the list of changes. A `500` only carries the underlying
message when the server runs with `KOYA_ENV=dev`.

```lisp
(handler-case (koya:create-content 'blog '(:title ""))
  (koya:koya-error (e)
    (when (= (koya:koya-error-status e) 422)
      (dolist (problem (koya:koya-error-details e))
        (format t "~a: ~a~%" (getf problem :field) (getf problem :message))))))
```

## Lisp and JSON

Arguments are converted to JSON and responses back to Lisp by the same rules:

| Lisp | JSON |
|---|---|
| plist starting with a keyword | object with camelCase keys |
| list or vector | array |
| `#()` | empty array |
| `t` | `true` |
| `nil` | `null` |
| string, number | as they are |

and coming back, an object becomes a kebab-case keyword plist, an array a list and
`null` `nil`. So `(getf item :published-at)` is `nil` for a draft, and
`:tags '("01J…" "01J…")` is an array of ids.

There is no Lisp spelling for JSON `false`: the server treats `null` and `false`
alike for booleans, so `nil` means "off". On `update-content`, which merges,
`nil` removes the key instead — send the whole data with `publish-content
:data …` when a value must be written rather than dropped.

Timestamps are ISO 8601 in UTC with milliseconds, e.g. `"2026-09-20T05:04:03.123Z"`.
`koya:now-iso`, `koya:format-iso` and `koya:parse-iso` are re-exported for
building them, and `koya:make-ulid` for generating ids.

## The HTTP API underneath

Every function above is one request to the server's JSON APIs:
[API.md](API.md) walks through them, [openapi.yaml](openapi.yaml) specifies them
(endpoints, parameters, response shapes, error codes) and [SCHEMA.md](SCHEMA.md)
the schema document `deploy` sends. `(koya:pull)` is the easiest way to see a real
schema document.

## License

The SDK — `koya.asd`, `src/main.lisp`, `src/client.lisp`, `src/config.lisp`,
`src/core.lisp` and `src/core/` — is under the [MIT License](../LICENSE-MIT), so a
site that declares its schema and reads its content with it is not bound by the
server's AGPL.
