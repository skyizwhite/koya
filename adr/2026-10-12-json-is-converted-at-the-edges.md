# JSON is converted at the edges

*2026-10-12*

## Context

koya reads JSON from requests, from SQLite columns and from archives, and
writes it back to the same places. The parsed form, jzon's hash tables with
string keys, a `null` symbol and vectors, travels on through the domain and the
use cases, which build and read it with JSON helpers (`jobject`, `jget`,
`json-null`). What the domain decides is then written in the wire format's
terms, and a change to how something is stored or answered reaches code that
only decides.

## Decision

- JSON is parsed and written only at the edges: `web/` for requests and
  answers, `infra/` for what SQLite and archives hold, and the SDK's client for
  what it sends and receives.
- An edge converts JSON into Lisp data before handing it inward, and Lisp data
  into JSON on the way out. The domain and the use cases hold and return Lisp
  data: structs and plists for what has a fixed shape, such as a schema, a
  webhook, the settings, a deploy's changes or an archive's document, and the
  data of a content as
  [its own decision](2026-10-12-content-data-is-a-plist.md) describes.
- The conversions of a schema are shared by the SDK and the server, so they stay
  in `koya-core`, in a module that only an edge uses.

## Consequences

- What a use case decides reads the same whatever format carries it, and the
  format can change at its edge alone.
- Every edge has a conversion each way, written once for each kind of data.
- `spec/server/layers.lisp` can check that no package inside the edges uses the
  JSON library or the conversions.
