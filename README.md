# koya

A small, self-hosted headless CMS written in Common Lisp.

- **Server** (`koya-server`): admin UI (hsx + htmx + Quill + Tailwind), delivery API, admin API, SQLite.
- **Library** (`koya`): schema DSL (`defspace` / `defmodel`), `plan` / `deploy` / `pull`, and an HTTP client.

Design notes live in [docs/DESIGN.md](docs/DESIGN.md).

## Quick start (development)

```sh
just install          # Tailwind binary + qlot dependencies
cp .env.example .env  # set KOYA_SECRET
just build            # CSS
just dev              # http://localhost:3000 (Hunchentoot)
```

Or from a REPL:

```lisp
(ql:quickload :koya-server)
(koya-server:start)            ; connects the DB, applies migrations, serves on :3000
```

## Defining content models

In your own project (which depends on `koya`):

```lisp
(defspace website
  :webhooks '("https://example.com/api/revalidate"))

(defmodel (website blog) (:kind :list
                          :public-url "https://example.com/blog/{CONTENT_ID}"
                          :preview-url "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}")
  (title    :text :required t)
  (slug     :slug :from title :unique t)
  (content  :richtext)
  (tags     :reference :model tag :many t))

(defmodel (website tag) ()
  (name :text :required t))

(defmodel (website about) (:kind :object)
  (body :richtext))
```

Then, from the REPL:

```lisp
(koya:configure :base-url "https://cms.example.com" :secret "..." :space "website")
(koya:plan)     ; show the diff against the server
(koya:deploy)   ; apply it (asks before destructive changes)
(koya:pull)     ; the schema currently on the server
```

## Reading content

```lisp
(koya:configure :api-key "koya_...")
(koya:get-list 'blog :query '(:limit 10 :orders "-publishedAt" :fields "id,title,publishedAt"))
(koya:get-item 'blog "01J...")
(koya:get-object 'about)
```

The delivery API is a microCMS-compatible subset:

```
GET /api/v1/{space}/{model}?limit=&offset=&orders=&fields=&filters=&depth=&draftKey=
GET /api/v1/{space}/{model}/{id}
X-KOYA-API-KEY: koya_...   (X-MICROCMS-API-KEY is accepted too)
```

## Tests

```sh
just test
```

## Deployment

The `Dockerfile` builds a single image (Woo on port 3000) with SQLite and media under `/data`.

Health check: `GET /health` (no auth).

Environment variables: `KOYA_SECRET` (required), `KOYA_DB_PATH`, `KOYA_MEDIA_DIR`, `KOYA_BASE_URL`, `KOYA_PORT`, `KOYA_ENV`.
