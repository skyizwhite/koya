# The deploy log names the sender as the server knew it

*2026-09-27, restating a decision of 2026-09-23*

## Context

A deploy is sent by the owner or with a management key. A row could store the
words a page shows for that, or what the server knew about the caller.

## Decision

- Who sent a deploy is stored as `owner` or `key:<label>`.
- The wording a page puts around it is the page's.

## Consequences

A page can be reworded later without the rows already written keeping the old
words.
