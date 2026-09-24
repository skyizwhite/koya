# Lists are read in place, and the URL follows

*2026-09-25*

## Context

`adr/2026-09-25-pages-answer-get-and-every-change-is-an-action.md` kept
whatever lives in the query string -- a list's search, filters, sort and page,
the history's tabs -- as page loads, so that a list as it is being read stays a
link. That cost a whole page for every page turned and every filter picked, and
a search had to wait for a button.

htmx 4 lets the server replace the URL without a navigation (`HX-Replace-Url`),
and on the back button it asks the server for the whole page at that URL again
rather than restoring a snapshot. A page whose GET draws from its query string
therefore comes back as it was left, however its state got there.

## Decision

Searching, filtering, sorting and paging -- the content list, the media library,
the webhook log, the deploy log and a content's history -- are actions. Each
draws again the part of the page it changes and answers `HX-Replace-Url` with the
page's own URL for the new state. The page's GET still reads that state from the
query string, so a reload, a bookmark or a shared link shows the same.

A search goes as the typing stops (`input changed delay:300ms`), a select as it
is picked; there is no button to apply them. The box and the selects sit outside
what is drawn, so typing keeps its focus; what they cannot see -- the count, the
sort a header chose -- comes back out of band.

The URL is replaced, not pushed: the steps inside one list are not history
entries of their own.

## Consequences

The back button leaves the list for the page before it, not for the previous
filter. Coming back to the list from another page shows it as it was left.

A link inside a list keeps its `href` to the page's URL for that state, next to
the `hx-get` that is followed, so opening it in a new tab still works.
