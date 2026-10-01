# Requests go through a wrapper, and Nomini swaps what comes back

*2026-10-01*

## Context

Nomini's `$fetch` sends a scope's data as a query string built from an object
and reads only the body of a 2xx answer. A form cannot go as it is: a name given
twice (a selection, a many-reference field) and a file do not survive, an
answer cannot send the browser elsewhere or say the page's URL, and a refusal is
not drawn. Nomini itself is not to be changed.

Wrapping `window.fetch` to read Nomini's requests would leave the body as Nomini
made it. Building swaps without Nomini would leave what is swapped in unbound,
since only Nomini's own swap starts its scopes and binds.

## Decision

- `assets/js/koya-fetch.js` sends every request a page makes: a form as its
  `FormData` (`multipart/form-data` when the form says so), a link or a
  placeholder by its `data-get`. It says it comes from the admin UI with
  `Koya-Request: true`.
- The answer is read there: `Koya-Redirect` sends the browser to another page,
  `Koya-Replace-Url` replaces the page's URL, and a body of elements with ids is
  handed to Nomini whatever the status. A body with nothing to draw is shown in
  the toast.
- The body reaches Nomini's swap through `$fetch` of a `data:` URL, on the
  body's scope, one at a time. The body's scope holds nothing: `$fetch` calls
  every function of the scope it is called on to collect what it sends.

## Consequences

- Elements ask with `nm-bind` and `data-get`, `data-post` and `data-confirm`,
  where they asked with `hx-*` before.
- koya depends on how Nomini's `$fetch` treats a `data:` URL; a new Nomini is
  checked against that before it is taken.
- A Content-Security-Policy, if one is added, has to let the page fetch `data:`.
