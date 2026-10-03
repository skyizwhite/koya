# A bad base URL or port stops the server before it starts

*2026-10-04*

## Context

A missing `KOYA_BASE_URL` quietly became `http://localhost:<port>`, so on a real
host the media URLs pointed at localhost and the session cookie lost its Secure
flag, with nothing to say why. A `KOYA_PORT` that was not a number ended the
process with a backtrace that did not name the variable. A short secret, by
contrast, turns logging in off and leaves the server running
(`adr/2026-10-04-a-short-secret-turns-logging-in-off.md`).

## Decision

- Without `KOYA_BASE_URL`, or with one that is not an http or https URL, the
  server does not start. Nor does it with a `KOYA_PORT` that is not a number
  from 1 to 65535.
- Every such setting is checked before anything is opened. `main` prints one
  line for each and exits 1; `start` at the REPL signals `setting-error`.

## Consequences

- A short secret harms logging in only, and the server goes on serving the
  sites; a wrong base URL would serve them wrong answers, and a bad port cannot
  be listened on, so these two stop it.
- An instance that relied on the localhost default no longer starts until the
  variable is set, as the README has always asked.
