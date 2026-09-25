# A space has no size limit, and its archive moves in pieces

Superseded by adr/2026-09-25-woo-holds-a-body-to-the-body-limit.md (Woo's own limit)

*2026-09-25*

## Context

A space's Export built its zip in memory, and after the media files began to
be read through the media port, that held about twice the archive at once. A
space's media have no total limit, so a large enough space ran the process out
of heap on Export, and SBCL stops rather than signals when that happens: every
space went down with it.

Import took the zip as one request body, up to 512 MB. That was a limit on the
size of a space that could move, and it could not simply be raised: Woo reads a
whole body before any middleware sees it, spilling it to a file past a
megabyte, up to smart-buffer's disk limit (1 GB by default), for any request,
signed in or not.

A limit on the size of a space was considered. It would make every space
movable, but it would be a product limit set by how archives were built, and
counting contents and their history against it would refuse writes.

## Decision

- **A space has no size limit.**
- **The zip is written and read by infra** (`ports/archives`). zippy copies an
  entry from its file and unpacks one on demand, a few kilobytes at a time;
  what is held in memory is `space.json` and one media file. The use case
  builds `space.json`, checks what is imported, and never sees a path.
- **An export is sent from a file and deleted once the server has it.** The
  page answers with the file and a header, `+temporary-file-header+`, and
  `*temporary-file-middleware*` hands the file to the server in a delayed answer
  and deletes it when the server returns: Woo has opened it by then and sends
  from what it opened, and Hunchentoot has sent it. The archive holds the
  webhook secret and every draft, so it does not stay on the disk.
- **An import is uploaded in pieces.** The dialog cuts the file into pieces of
  16 MB and sends each to an action that adds it to the end of an upload, at
  the offset it names; one that does not follow is refused with where the
  upload stands. A last action imports the upload in one transaction, as
  before, and a bar shows the upload and then that the server is at work.
- **Every request body is under the ordinary limit.** The special route for an
  import body, `archive-path`, is gone. Woo's own limit stays smart-buffer's
  gigabyte: past it Woo signals an error it does not catch, which stops the
  server, so lowering it to ours would let any request of 21 MB do that.
- **Archives are kept in `archives/` beside the database**, on the volume, since
  one is as large as a space. What an export or an upload leaves behind a day or
  more ago is deleted when the next one starts.

## Consequences

- Any space can be moved through the admin UI, and the memory an export or an
  import needs does not grow with it.
- While an import is made, the instance answers nothing else, the delivery API
  included: it is one transaction, which holds the store. It is kept that way so
  that an import is all or nothing; moving a space is rare.
- An import interrupted by a restart starts again: action URLs change with the
  process. The upload it left is deleted a day later.
- `archives/` may be left out of backups.
