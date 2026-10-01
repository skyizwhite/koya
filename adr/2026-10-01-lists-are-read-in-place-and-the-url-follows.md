# Lists are read in place, and the URL follows

*2026-10-01, restating a decision of 2026-09-25*

## Context

A list's search, filters, sort and page live in the query string, so that a
list as it is being read stays a link. Loading the whole page for every page
turned and every filter picked cost a page each time, and a search had to wait
for a button.

## Decision

Searching, filtering, sorting and paging -- the content list, the media library,
the webhook log, the deploy log and a content's history -- are actions. Each
draws again the part of the page it changes and answers `Koya-Replace-Url` with
the page's own URL for the new state, which the page puts in place of its URL.
The page's GET still reads that state from the query string, so a reload, a
bookmark or a shared link shows the same.

A search goes as the typing stops (300 ms), a select as it is picked; there is no
button to apply them, and nothing is sent that would ask what was asked last.
The box and the selects sit outside what is drawn, so typing keeps its focus;
what they cannot see -- the count, the sort a header chose -- comes back beside
the list.

The URL is replaced, not pushed: the steps inside one list are not history
entries of their own.

## Consequences

The back button leaves the list for the page before it, not for the previous
filter. A page is not kept by the browser (`no-store`), so coming back to the
list asks the server for it at the URL it was left at, and it shows as it was
left.

A link inside a list keeps its `href` to the page's URL for that state, next to
the `data-get` that is followed, so opening it in a new tab still works.
