<p align="center">
  <img src="assets/icon.svg" alt="" width="160" height="160">
</p>

# koya

[![CI](https://github.com/skyizwhite/koya/actions/workflows/ci.yml/badge.svg)](https://github.com/skyizwhite/koya/actions/workflows/ci.yml)

A small, self-hosted headless CMS for one owner and any number of sites.

- **Your schema is code.** Models live in your site's repository, typed, and are
  deployed from an npm script — with a plan first, and a question before anything
  destructive.
- **An admin UI built from it.** List pages and an editor for every model: rich
  text, media, references, drafts, previews and the history of every version.
- **A typed client.** [koya-ts-sdk](https://github.com/skyizwhite/koya-ts-sdk)
  reads content with types generated from your schema, references embedded on
  request.
- **Webhooks** on every publish, unpublish, delete and draft, to revalidate or
  rebuild your site.
- **One Docker image**, one volume. No database server to run.

## Quick start

### 1. Run the server

```sh
docker run -d --name koya \
  -p 3100:3100 \
  -v koya-data:/data \
  -e KOYA_SECRET=change-me \
  -e KOYA_BASE_URL=http://localhost:3100 \
  ghcr.io/skyizwhite/koya:latest
```

or, next to your site in a compose file:

```yaml
services:
  koya:
    image: ghcr.io/skyizwhite/koya:latest
    ports: ["3100:3100"]
    volumes: ["koya-data:/data"]
    environment:
      KOYA_SECRET: change-me
      KOYA_BASE_URL: http://localhost:3100
volumes:
  koya-data:
```

### 2. Make a space and its keys

Open <http://localhost:3100>, log in with `KOYA_SECRET`, and make a **space** —
one per site, e.g. `website`. On its **Keys** page, make

- a **delivery key** (`koya_…`), which reads published content, and
- a **management key** (`koya_mgmt_…`), which deploys the schema and manages
  content. Keep it on the server side.

```sh
# your site's .env
KOYA_URL=http://localhost:3100
KOYA_SPACE=website
KOYA_DELIVERY_KEY=koya_…
KOYA_MANAGEMENT_KEY=koya_mgmt_…
```

### 3. Define your models

```sh
npm install github:skyizwhite/koya-ts-sdk#v0.1.0
```

```ts
// koya.config.ts
import { defineConfig, defineSchema } from "koya-ts-sdk";

export default defineConfig({
  schema: defineSchema({
    webhooks: [{ label: "revalidate", url: "https://example.com/api/revalidate" }],
    models: [
      {
        name: "blog",
        kind: "list",
        label: "title",
        previewUrl: "https://example.com/blog/{CONTENT_ID}?draftKey={DRAFT_KEY}",
        fields: [
          { name: "title", type: "text", required: true },
          { name: "slug", type: "slug", from: "title", unique: true },
          { name: "cover", type: "media" },
          { name: "body", type: "richtext" },
          { name: "tags", type: "reference", model: "tag", many: true },
        ],
      },
      { name: "tag", kind: "list", fields: [{ name: "name", type: "text", required: true }] },
      { name: "about", kind: "object", fields: [{ name: "body", type: "richtext" }] },
    ],
  }),
  types: { out: "src/koya.gen.ts" },
});
```

```json
{
  "scripts": {
    "koya:plan": "koya plan",
    "koya:deploy": "koya deploy",
    "koya:types": "koya types"
  }
}
```

```sh
npm run koya:plan     # what the deploy would change
npm run koya:deploy   # apply it; the editor now has these models
npm run koya:types    # src/koya.gen.ts: a type per model
```

Field types are `text`, `textarea`, `richtext`, `number`, `boolean`, `date`,
`datetime`, `select`, `media`, `reference` and `slug`; their options and rules
are in [docs/SCHEMA.md](docs/SCHEMA.md). A `list` model has any number of
contents, an `object` model exactly one.

### 4. Fetch content

```ts
import { createClient } from "koya-ts-sdk";
import type { KoyaModels } from "./koya.gen.ts";

const koya = createClient<KoyaModels>({
  baseUrl: process.env.KOYA_URL!,
  space: process.env.KOYA_SPACE!,
  deliveryKey: process.env.KOYA_DELIVERY_KEY!,
});

const { contents, totalCount } = await koya.getList("blog", {
  limit: 10,
  orders: ["-publishedAt"],
  filters: "title[contains]hello",
  include: ["tags"], // tags come back as tag contents, not ids
});

const post = await koya.getItem("blog", id);                     // one content
const preview = await koya.getItem("blog", id, { draftKey });    // its draft, for a preview page
const about = await koya.getObject("about");
```

Each content is typed by its model — `post.cover?.url`, and
`post.tags?.[0]?.name` with `include` — and carries the system fields `id`,
`createdAt`, `updatedAt`, `publishedAt` and `revisedAt`.

Read from the server side — server rendering, build time, an API route: the
delivery API does not yet answer cross-origin requests from a browser
([#16](https://github.com/skyizwhite/koya/issues/16)).

Writing content from code, uploading media and more are in the
[koya-ts-sdk README](https://github.com/skyizwhite/koya-ts-sdk#readme).

### 5. Revalidate on publish

Every webhook of the space is POSTed on every event, with the space's webhook
secret (on its **Keys** page) in `X-KOYA-WEBHOOK-KEY`:

```json
{ "space": "website", "model": "blog", "id": "01J…", "event": "publish", "contents": { "old": null, "new": { … } } }
```

`event` is `publish`, `unpublish`, `delete` or `draft` — ignore `draft`, which
comes on every save, when you revalidate. See
[docs/API.md](docs/API.md#webhooks).

## Documentation

| | |
|---|---|
| [koya-ts-sdk](https://github.com/skyizwhite/koya-ts-sdk) | the TypeScript client and the `koya` CLI |
| [docs/ADMIN-UI.md](docs/ADMIN-UI.md) | the admin UI: writing and publishing, previews, media, keys, settings |
| [docs/SCHEMA.md](docs/SCHEMA.md) | models and fields, the rules content values meet, what a deploy changes |
| [docs/API.md](docs/API.md) | the delivery and admin APIs: queries, what comes back, errors, webhooks |
| [docs/openapi.yaml](docs/openapi.yaml) | the same, as an OpenAPI 3.1 document |
| [docs/lisp-sdk.md](docs/lisp-sdk.md) | the Common Lisp SDK |
| [CONTRIBUTING.md](CONTRIBUTING.md) | working on koya itself |

## Running it

The image is `ghcr.io/skyizwhite/koya` for `linux/amd64` and `linux/arm64`:
`latest` and `X.Y.Z` / `X.Y` are releases, `edge` follows `master`. It serves on
port 3100 and keeps everything under `/data`; mount a persistent volume there.

| Variable | Required | Meaning |
|---|---|---|
| `KOYA_SECRET` | yes | the admin UI's login password |
| `KOYA_BASE_URL` | yes | the server's public URL, e.g. `https://cms.example.com`: media URLs, the same-origin check and the Secure cookie flag use it |
| `KOYA_PORT` | no | listen port, default `3100` |
| `KOYA_DB_PATH`, `KOYA_MEDIA_DIR` | no | default `/data/koya.db` and `/data/media` |
| `KOYA_ENV` | no | `production` (default) hides error details; `dev` shows them |

`GET /health` answers without a key, and the image declares it as its
`HEALTHCHECK`. The server starts in about a second and stops cleanly on
`docker stop`; migrations apply themselves at startup.

**Back up the whole `/data` directory**: it holds the database and the uploaded
media. To move one space to another server, use **Export** on its page and
**Import** on the new server's spaces page; its keys come along, so the site's
`.env` keeps working.

## License

- **The server** is under the [GNU Affero General Public License v3.0 or
  later](LICENSE): running a modified server for others means offering them its
  source, which the admin UI's footer links to.
- **The SDKs** are under the MIT License, so a site that uses them is not bound
  by the AGPL: [koya-ts-sdk](https://github.com/skyizwhite/koya-ts-sdk), and the
  SDK files of this repository listed in
  [docs/lisp-sdk.md](docs/lisp-sdk.md#license) ([LICENSE-MIT](LICENSE-MIT)).
