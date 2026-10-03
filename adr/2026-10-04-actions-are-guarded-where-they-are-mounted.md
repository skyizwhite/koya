# Actions are guarded where they are mounted

*2026-10-04, restating a decision of 2026-10-01*

## Context

An action should do nothing about who is asking. Checking that in each action
would leave a hole wherever one forgot.

An action asked without a session used to send the browser to the login page,
which came back to the page afterwards. Whatever was typed into that page, such
as a content in the editor, was gone, since what the action carried is not
replayed after a login.

## Decision

`*mw-actions-auth*` guards every action where the actions are mounted, in this
order:

1. The request must come from the admin UI (`nm-request: true`), or it is
   answered 400.
2. It must carry the owner's session, or it is answered 401 with a toast that
   says the session has ended and links to the login page in a new tab, which
   comes back there to the page the request came from (its `Referer`). The page
   it was asked from stays as it is.
3. Anything that writes must come from the same origin, or it is answered 403.

An action checks only what it is about, such as whether the space or content it
names exists.

## Consequences

- An action added later is guarded without doing anything.
- A link or a plain form post to an action is refused.
- Nothing typed is lost to a session that ended: the owner logs in in the other
  tab, the session cookie is the browser's, and the same button works again.
- What was asked is still not replayed by itself; it is asked again by hand.
