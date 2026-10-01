# Actions are guarded where they are mounted

*2026-10-01, restating a decision of 2026-09-25*

## Context

An action should do nothing about who is asking. Checking that in each action
would leave a hole wherever one forgot.

## Decision

`*mw-actions-auth*` guards every action where the actions are mounted, in this
order:

1. The request must come from the admin UI (`Koya-Request: true`), or it is
   answered 400.
2. It must carry the owner's session, or it is answered 401 with a
   `Koya-Redirect` to the login page, which then comes back to the page the
   request came from (its `Referer`).
3. Anything that writes must come from the same origin, or it is answered 403.

An action checks only what it is about, such as whether the space or content it
names exists.

## Consequences

- An action added later is guarded without doing anything.
- A link or a plain form post to an action is refused.
