# The admin UI sends each image on its own

*2026-11-27*

## Context

The library and the media picker sent the images chosen together in one
request, so they could add up to no more than one upload, 20 MB, however many
there were. That limit is the request body limit, which holds for every request
on every path, signed in or not, on the disk and in memory
(`adr/2026-09-27-a-request-body-is-limited-to-an-upload.md`,
`adr/2026-09-25-woo-holds-a-body-to-the-body-limit.md`). Raising it to let more
images go together would raise what anyone can make the server hold.

Nagi's `$post` gives nothing to wait on, so a page cannot send the files one
after another with it.

## Decision

- The admin UI sends each image it is given in a request of its own, one after
  another, to one action, `upload-media`, which the library and the picker
  share. The action stores the one file it is sent and answers nothing to draw;
  a request of several files, or of none, is refused.
- `koya.uploader` in `koya.js` sends them with a fetch of its own, as the import
  sends its pieces, and does not send a file over the upload limit.
- How far the sending is shows in a dialog, as an import's does. When every file
  is added it closes and the toast says so. Otherwise it stays open and lists
  each file that was not added and why. A file the action refuses (413, 422)
  does not stop the rest; any other answer, or none, stops the sending, and the
  dialog says the rest were not sent.
- Once the sending ends, the part of the page that lists the files is asked for
  again for what its search box says: the library at its first page, or the
  picker's grid. The upload form is outside that part, so its dialog stays.
- The Admin API's upload still takes several files in one request, up to 20 MB
  in all; a client of it sends its own requests.

## Consequences

- Any number of images go at once, each up to 20 MB, and the request body limit
  stays 21 MB.
- Files added before a refusal or a stop stay added.
- After an upload the library is at its first page, where the new files are,
  rather than at the page it was on.
- Closing the dialog hides it and does not stop the sending.
