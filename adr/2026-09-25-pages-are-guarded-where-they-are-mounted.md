# Pages are guarded where they are mounted, as the admin API and the actions are

*2026-09-25*

## Context

The admin API and the actions are guarded by a middleware where they are
mounted. Both deny by default: a route added later is covered without doing
anything, and what is open names itself with `public-path`.

Pages were the exception. Each page wrapped its handler in `with-owner`, and a
page without it answered anyone. Every page that needed the wrapper had it, so
there was no hole. But that held only because each page remembered, and
nothing would have noticed one that forgot.

## Decision

- **Pages are guarded by `*pages-auth-middleware*`.** It is installed where the
  pages are served, inside everything mounted before them. A request without the
  owner's session is sent to `/login?next=…`, which comes back to the page after
  the login, as `with-owner` did.
- **What is open says so where it is defined.** `/login` and `/health` declare
  themselves with `public-path`, the mechanism the actions already use. The guard
  also lets through `/assets/`, which the login page is drawn with, and
  `/actions/…`, which its own guard answers.
- **`with-owner` is gone.** A page handler does nothing about who is asking.
- **A path that is no page is a redirect to the login page too**, for anyone
  without a session. Only the owner is told that it does not exist.

## Consequences

- A page added later is the owner's without doing anything. The test registers
  a page that does nothing, and checks that it is sent to the login page without
  a session and answered with one.
- Whether a path exists is no longer something a visitor without a session can
  find out.
