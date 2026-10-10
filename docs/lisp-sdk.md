# The Common Lisp SDK

For a site written in Common Lisp, this repository's `koya-sdk` system is to it
what [koya-ts-sdk](https://github.com/skyizwhite/koya-ts-sdk) is to a TypeScript
site. It holds three things:

- a **schema DSL** — `defmodel`, `defcustomfield`, `defwebhooks`, `webhook` —
  that defines the space's models as code in the site's own repository;
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

then `qlot install` (and `qlot update koya` to pick up later changes). Add
`koya-sdk` to the site's `.asd` `:depends-on`, and `(ql:quickload :koya-sdk)` in
the REPL.

All symbols below live in the `koya-sdk` package, and it exports nothing else.
Each one has a docstring, so `describe` shows it at the REPL. The server (`koya-server`) is a
separate system; a site never loads it.

## Configuration

```lisp
(koya-sdk:configure :base-url "https://cms.example.com"
                    :management-key "koya_mgmt_..."  ; schema, content and media calls
                    :delivery-key "koya_..."  ; reading published content
                    :space    "website")   ; the space every call works in
```

Each setting is a special variable with an environment-variable fallback, read at
call time:

| Variable | Environment | Used by |
|---|---|---|
| `koya-sdk:*base-url*` | `KOYA_URL` | everything |
| `koya-sdk:*management-key*` | `KOYA_MANAGEMENT_KEY` | `plan`, `deploy`, `pull`, content/keys/media management |
| `koya-sdk:*delivery-key*` | `KOYA_DELIVERY_KEY` | `get-list`, `get-list-content`, `get-object` |
| `koya-sdk:*space*` | `KOYA_SPACE` | the default for every `:space` argument |

**The space is made in the admin UI first**, and both keys are then made on its
*Keys* page. A management key belongs to that one space and reaches nothing else,
so a site's `.env` cannot touch another site's content; the owner secret
(`KOYA_SECRET`) only logs into the admin UI and is not accepted here. Note that
the server's own public URL is `KOYA_BASE_URL`; the client reads `KOYA_URL`, so
both can sit in one `.env` without colliding. A missing setting
signals an error naming what to set. Calls that take `:space` accept a symbol or
a string and downcase it, and default to `koya-sdk:*space*`.

## Defining the schema

A project defines the models of one space, so no definition names the space —
`koya-sdk:*space*` says which one a deploy goes to. Definitions are collected in
an in-memory registry; re-evaluating a form replaces the previous definition of
the same name, so the schema can be edited live from the REPL.

```lisp
;; every model of the space, on every event; :only narrows one -- see Webhooks below
(defwebhooks (webhook "revalidate" "https://example.com/api/revalidate")
             (webhook "preview-build" "https://preview.example/hook" :only 'blog))

(defmodel blog (:kind :list
                :label       title
                :public-url  "https://example.com/blog/{CONTENT_SLUG}"
                :preview-url "https://example.com/blog/{CONTENT_SLUG}?draft-key={DRAFT_KEY}")
  (title   :text :required t)
  (slug    :slug :required t)
  (cover   :media)
  (content :richtext)
  (tags    :reference :model tag :many t)
  (meta    :custom :custom-field seo))

(defcustomfield seo
  (title :text :max-length 60)
  (image :media :help "1200x630"))

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
- **`(defcustomfield name &body fields)`** — a set of fields a model uses as one
  field of type `:custom`, its value an object of these fields, or as the rows of
  a `:repeater`. The fields are written as in `defmodel`, but none is a `:slug`,
  a `:custom` or a `:repeater`, nor `:unique` or `:was`, and none is named
  `fieldId`. Its name follows the field rule below.
- **`:was`**, on the model or on a field, names what it used to be called, so
  that a deploy renames it instead of dropping it — see
  [Renaming a model or a field](#renaming-a-model-or-a-field).
- **`:preview-url` / `:public-url`** are templates for the editor's two links.
  They start with `http://` or `https://`, and `{CONTENT_ID}`, `{CONTENT_SLUG}`
  and `{DRAFT_KEY}` are substituted. `{CONTENT_SLUG}` is the model's `:slug`
  field, the published value in `:public-url` and the draft's in
  `:preview-url`; a template using it needs the model to have one, and the link
  is not shown while it is blank.
- **`:label`** names the `:text` or `:slug` field whose value the admin UI shows
  for a content — in the list's reference previews, the reference dropdowns and
  the history. It is taken literally, like a field name (`:label title`).
  Without it a content is shown by its id; no field is guessed at. It cannot name
  a field inside a custom field.

Naming rules, checked as the schema is built:

| Name | Shape | Notes |
|---|---|---|
| model | `^[a-z][a-z0-9-]*` | it appears in URLs |
| field | `^[a-z][a-zA-Z0-9]*` | a kebab-case symbol is camelised: `(published-at :datetime)` becomes `publishedAt` |

`id`, `createdAt`, `updatedAt`, `publishedAt` and `revisedAt` are system fields
that every content already has; declaring one is an error.

Other helpers: `(koya-sdk:current-schema)` returns the validated schema built so
far, models and custom fields, `(koya-sdk:clear-schema)` empties the registry, and
`(koya-sdk:find-model name)` looks a definition up.

## Field types and options

| Type | Options | Stored as |
|---|---|---|
| `:text` | `:required` `:max-length` `:pattern` `:unique` | string |
| `:textarea` | `:required` `:max-length` | string |
| `:richtext` | `:required` | HTML string |
| `:number` | `:required` `:min` `:max` `:integer` | number |
| `:boolean` | `:required` `:default` | true / false |
| `:date` | `:required` | `"YYYY-MM-DD"` |
| `:datetime` | `:required` | ISO 8601 with a zone, e.g. `"2026-09-20T10:00:00.000Z"`, kept to the minute in UTC |
| `:select` | `:required` `:options` `:many` | one of `:options`, or an array of them |
| `:media` | `:required` `:many` | media id, or an array of them with `:many` (expanded to objects by the delivery API) |
| `:reference` | `:required` `:model` `:many` | content id (embeddable with `include`) |
| `:slug` | `:required` `:pattern` | lowercase-hyphen string, unique within the model; a list model has one at most, an object model none |
| `:custom` | `:required` `:custom-field` | an object of the custom field's fields |
| `:repeater` | `:required` `:custom-fields` | an array of rows, each naming its custom field in `fieldId` beside that custom field's fields |

- Every type also takes `:was`, which names the field this one was renamed from —
  see [Renaming a model or a field](#renaming-a-model-or-a-field).
- Every type also takes `:help`, a non-empty string the editor shows under the
  field's name to say what it expects, e.g. `(cover :media :help "1200x630")`.
  Changing it changes nothing stored.
- `:options` takes strings or symbols, which are downcased; `:model` and
  `:custom-field` take a symbol or a string too.
- `:model` names another model of the same space; `:custom-field` names a
  `defcustomfield`. Both are checked against the whole schema, so a typo fails
  before anything is sent.
- `:custom-fields` is a non-empty list of `defcustomfield` names, without
  duplicates, taken literally and camelised like field names:
  `(blocks :repeater :custom-fields (heading body))`. A `:repeater` sits only in
  a `defmodel`.
- `:default t` on a `:boolean` sets the field to true on a new content that does
  not mention it (the editor starts with the box checked); an explicit `false` is
  kept.

What each type stores, what counts as blank, and how every option is enforced
(`:unique` across drafts and published data, `:pattern` as a `cl-ppcre` regex,
…) is specified in
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

Every webhook is sent every event — `publish`, `unpublish`, `delete`, `draft`
and `discard` — with the space's webhook secret in `X-KOYA-WEBHOOK-KEY`, which
`(koya-sdk:webhook-secret)` returns. The payload and when each event fires are
in [API.md, "Webhooks"](API.md#webhooks).

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
`:force`; changing the type at the same time still is, and tightening the options
is checked against the stored content.

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
(koya-sdk:plan)                ; the changes a deploy would apply; prints and returns them
(koya-sdk:deploy)              ; apply them
(koya-sdk:deploy :force t)     ; apply without asking about destructive changes
(koya-sdk:pull)                ; the schema the server currently stores, as a schema object
```

All four work on `koya-sdk:*space*`, or on the `:space` given to them. **The
space must already exist**: it is made in the admin UI, and a deploy to a name
that has none is refused with `404 not_found` rather than quietly making one, so
a typo in `KOYA_SPACE` cannot grow a second, empty space.

Both `plan` and `deploy` take `:schema` (defaulting to `(current-schema)`) and
`:stream`; `deploy` also takes `:confirm` (default `t`). When a deploy would
change something destructive the server refuses it; `deploy` then prints the
changes, marked with `!`, and asks — answering no returns `nil` and changes
nothing. With `:confirm nil` and no `:force` it gives up the same way, without
asking, so a script never applies a destructive change by accident.

Destructive means a change that can hide or invalidate content already stored:
removing a model or field, changing a kind or a field type (for a reference,
the model it points at). Deleting the space
itself is not among them — that is done in the admin UI, with its own
confirmation. The exact list, and the shape of each change, is in
[SCHEMA.md, "Changes"](SCHEMA.md#changes). A rename declared with `:was` carries
existing content through, and removing a field or changing its type or target
model takes its values out of every published object, draft and revision;
changing a model's kind deletes its contents, as removing it would.

Tightening a field's options, or adding a `:required` field to a model that has
contents, is not destructive but is checked: `plan` lists under the change every
content whose stored value does not fit, and `deploy` is refused with
`contents_do_not_fit`, `:force` or not, until they are changed to fit.

Every deploy that changed something is recorded — what it changed, and the label
of the management key that sent it — and is read afterwards in the admin UI at
`/s/{space}/deploys`; see [ADMIN-UI.md](ADMIN-UI.md#schema-deploys).

## Reading content

These need a delivery key and return published data only. A `:list` model is a
list of list contents; an `:object` model's one content is its object.

```lisp
(koya-sdk:get-list 'blog)
(koya-sdk:get-list 'blog :query '(:limit 10 :orders "-publishedAt" :fields "title"))
(koya-sdk:get-list 'blog :query '(:include "tags"))                  ; embed referenced contents
(koya-sdk:get-list-content 'blog "k3x9m2qa7t0b")
(koya-sdk:get-list-content 'blog "k3x9m2qa7t0b" :query '(:draft-key "…"))    ; preview a draft
(koya-sdk:get-object 'about)
```

Each takes `:space` to override the default. `get-list` returns a plist:

```lisp
(:contents ((:id "k3x9m2qa7t0b" :title "…" :tags ("p8f2w6zc1n4d") :published-at "2026-09-20T…Z" …) …)
 :total-count 42 :offset 0 :limit 10)
```

`get-list-content` and `get-object` return the content plist itself.

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
| `:fields` | fields to keep in each content; the system fields are always kept |
| `:filters` | see below |
| `:q` | search the text fields, as the delivery API's `q` |
| `:include` | reference fields to embed |
| `:draft-key` | with `get-list-content` / `get-object`, serves that content's draft |

`:filters` takes the delivery API's filter syntax as a string:

```lisp
(koya-sdk:get-list 'blog :query '(:filters "title[contains]lisp[and]publishedAt[exists]"))
```

### What comes back

The content objects of [API.md, "What comes back"](API.md#what-comes-back), as
plists (see [Lisp and JSON](#lisp-and-json)): references are ids unless
`:include`d, `:media` fields are expanded, and `:published-at` / `:revised-at`
are `nil` while a content is not published.

## Managing content

These use the management key and see drafts as well. Their names start with
`admin-`.

```lisp
(koya-sdk:admin-get-list 'blog :query '(:limit 100))   ; every list content, drafts included
(koya-sdk:admin-get-list-content 'blog "k3x9m2qa7t0b")
(koya-sdk:admin-create-list-content 'blog '(:title "Hello" :content "<p>…</p>"))   ; as a draft
(koya-sdk:admin-create-list-content 'blog '(:title "Hello") :publish t)
(koya-sdk:admin-update-list-content 'blog "k3x9m2qa7t0b" '(:title "New title"))            ; save a draft
(koya-sdk:admin-publish-list-content 'blog "k3x9m2qa7t0b")                                 ; publish the draft
(koya-sdk:admin-publish-list-content 'blog "k3x9m2qa7t0b" :data '(:title "…") :published-at "2026-09-20T10:00:00.000Z")
(koya-sdk:admin-unpublish-list-content 'blog "k3x9m2qa7t0b")
(koya-sdk:admin-discard-list-content-draft 'blog "k3x9m2qa7t0b")
(koya-sdk:admin-delete-list-content 'blog "k3x9m2qa7t0b")
(koya-sdk:admin-list-content-draft-key 'blog "k3x9m2qa7t0b")   ; for a preview URL
```

An object is reached through its model, with no id:

```lisp
(koya-sdk:admin-get-object 'about)
(koya-sdk:admin-update-object 'about '(:body "<p>…</p>"))   ; save a draft; the first one makes the object
(koya-sdk:admin-publish-object 'about)
(koya-sdk:admin-publish-object 'about :data '(:body "…"))
(koya-sdk:admin-unpublish-object 'about)
(koya-sdk:admin-discard-object-draft 'about)
(koya-sdk:admin-object-draft-key 'about)
```

- `admin-get-list` returns `(:contents (…) :total-count n :offset n :limit n)` where
  each content is `(:id … :status … :published {…} :draft {…} :draft-key … :created-at …)`.
  `status` is `"draft"`, `"published"` or `"published+draft"`.
- `admin-update-list-content` and `admin-update-object` **merge** the plist onto
  the current draft (or the published data when there is none); a key whose
  value is `nil` is removed. Publishing with `:data` replaces the data outright.
- `admin-create-list-content` also takes `:created-at`, `:updated-at`, `:published-at`
  and `:revised-at`, for an import from another CMS that keeps its dates. The
  server makes the id: 12 lowercase letters and digits.
- An `:object` model's object is made by its first `admin-update-object`, or an
  `admin-publish-object` with `:data`; `admin-create-list-content` answers 404
  for it, as do the other functions that take an id. It has no delete: it goes
  with its model.
- Saving a draft issues a new draft key, so older preview links stop working.
- What a content's `status` cannot do is refused with a 409 and changes nothing:
  unpublishing needs a published content (`not_published`), and discarding a
  draft a published content with a draft (`not_published`, `no_draft`).
  The table is in [API.md](API.md#managing-content).

## Delivery keys and the webhook secret

```lisp
(koya-sdk:create-delivery-key :label "production site")  ; => (values "koya_…" "01J…"), shown once
(koya-sdk:list-delivery-keys)                            ; ((:id … :label … :created-at …) …)
(koya-sdk:delete-delivery-key "01J…")
(koya-sdk:webhook-secret)                            ; the X-KOYA-WEBHOOK-KEY of the space
```

Only a key's SHA-256 is stored, so a lost key cannot be read back — delete it and
create another. A key is valid for its space alone.

## Media

```lisp
(koya-sdk:upload-media #p"cover.png" :alt "Cover")
;; => (:id "01J…" :url "https://cms.example.com/media/website/01J….png" :filename "cover.png"
;;     :mime "image/png" :size 12345 :width 1200 :height 630 :alt "Cover" :created-at "…")
(koya-sdk:list-media :search "cover" :limit 60 :offset 0)   ; (:media (…) :total-count n :offset n :limit n)
(koya-sdk:get-media "01J…")                                 ; adds :references — how many contents use it
(koya-sdk:update-media "01J…" :alt "New alt text")
(koya-sdk:delete-media "01J…")
```

PNG, JPEG, GIF and WebP up to 20 MB each; the type is decided by reading the
file's leading bytes. `delete-media` refuses (409 `in_use`) while any content
still uses the file, as a `:media` value or inside rich text — `get-media`'s
`:references` is that count. Remove it from those contents first.

## Errors

Anything but a 2xx signals `koya-sdk:koya-error`, with readers
`koya-error-status`, `koya-error-code`, `koya-error-message` and
`koya-error-details`.

The status and code of every error each endpoint can return are listed in
[openapi.yaml](openapi.yaml). Two carry `details`: `422 validation_failed`, where
it is a list of `(:field … :code … :message …)` plists (codes in
[SCHEMA.md](SCHEMA.md#content-values)), and `409 destructive_changes` and
`409 contents_do_not_fit` from `deploy`, where it is the list of changes, each
with its `:misfits`. A `500` only carries the underlying
message when the server runs with `KOYA_ENV=dev`.

```lisp
(handler-case (koya-sdk:admin-create-list-content 'blog '(:title ""))
  (koya-sdk:koya-error (e)
    (when (= (koya-sdk:koya-error-status e) 422)
      (dolist (problem (koya-sdk:koya-error-details e))
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
`:tags '("k3x9m2qa7t0b" "p8f2w6zc1n4d")` is an array of ids.

There is no Lisp spelling for JSON `false`: the server treats `null` and `false`
alike for booleans, so `nil` means "off". On `admin-update-list-content` and
`admin-update-object`, which merge, `nil` removes the key instead — send the
whole data when publishing with `:data …` when a value must be written rather
than dropped.

Timestamps are ISO 8601 in UTC with milliseconds, e.g.
`"2026-09-20T05:04:03.123Z"`. `koya-sdk:now-iso`, `koya-sdk:format-iso` and
`koya-sdk:parse-iso` are exported for building them, and `koya-sdk:make-ulid`
for generating ids.

## The HTTP API underneath

Every function above is one request to the server's JSON APIs: [API.md](API.md)
walks through them, [openapi.yaml](openapi.yaml) specifies them (endpoints,
parameters, response shapes, error codes) and [SCHEMA.md](SCHEMA.md) the schema
document `deploy` sends. `(koya-sdk:pull)` is the easiest way to see a real
schema document.

## License

The SDK and the core it uses — `koya-sdk.asd`, `koya-core.asd`, `src/sdk/` and
`src/core/` — are under the [MIT License](../LICENSE-MIT), so a site that declares
its schema and reads its content with them is not bound by the server's AGPL.
