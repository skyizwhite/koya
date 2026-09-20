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
  ;; fires for every model; events default to publish, unpublish and delete
  :webhooks (list (webhook "revalidate" "https://example.com/api/revalidate")))

(defmodel (website blog) (:kind :list
                          :public-url "https://example.com/blog/{CONTENT_ID}"
                          :preview-url "https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}"
                          ;; this model only, on draft saves as well
                          :webhooks (list (webhook "preview-build" "https://preview.example/hook" :events '(:draft))))
  (title    :text :required t)
  (slug     :slug :from title :unique t)
  (cover    :media)
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
(koya:get-list 'blog :query '(:include "tags"))   ; embed referenced contents (ids by default)
(koya:get-item 'blog "01J...")
(koya:get-object 'about)
```

The delivery API is a microCMS-compatible subset:

```
GET /api/v1/{space}/{model}?limit=&offset=&orders=&fields=&filters=&include=&draftKey=
GET /api/v1/{space}/{model}/{id}
X-KOYA-API-KEY: koya_...   (X-MICROCMS-API-KEY is accepted too)
```

## Media

Images (PNG, JPEG, GIF, WebP) live in a per-space library under `KOYA_MEDIA_DIR` and are served by koya at `/media/{space}/{id}.{ext}`. Upload from the admin UI (`/s/{space}/media`, or the picker in the editor and in Quill's image button), or from Lisp:

```lisp
(koya:upload-media #p"cover.png" :alt "Cover")   ; => (:id "..." :url "https://cms.example.com/media/website/....png" ...)
(koya:list-media :search "cover")
(koya:delete-media "01J...")
```

A `:media` field stores the id and the delivery API returns `{id, url, width, height, alt, ...}`.

## Tests

```sh
just test
```

## Deployment

The `Dockerfile` builds a single image (Woo on port 3000) with SQLite and media under `/data`.

Health check: `GET /health` (no auth).

Environment variables: `KOYA_SECRET` (required), `KOYA_TOTP_SECRET` (optional second factor), `KOYA_DB_PATH`, `KOYA_MEDIA_DIR`, `KOYA_BASE_URL`, `KOYA_PORT`, `KOYA_ENV`.

### Two-factor login

Open **Settings** in the admin UI and set it up: scan the QR code with an authenticator app and confirm with a code. From then on the login form asks for the code as well as the secret. To configure it outside the database instead, `(koya-server:totp-setup)` prints a `KOYA_TOTP_SECRET` value; when that variable is set it takes precedence.
