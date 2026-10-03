# The owner secret is too long to guess, and wrong secrets are not counted

*2026-10-04*

## Context

The login page is open to anyone and asks for the owner's secret. It used to
count failed logins per address and refuse an address after five, even with
the right secret. Behind a reverse proxy every client has the proxy's address,
so anyone could keep the owner from logging in by failing five times every few
minutes. Counting for the whole server instead would hand that to anyone at
all, and a lock that the right secret passes stops no guessing.

## Decision

- `KOYA_SECRET` is at least 32 characters. It is set where the server runs, not
  remembered by a person, so a random one costs nothing.
- Wrong secrets are not counted, and no address is ever refused.

## Consequences

- Nobody who lacks the secret can lock the owner out, whatever sits in front of
  the server.
- Guessing is limited by the secret's length alone: 32 random characters are
  out of reach at any rate the server can answer. A secret that is long but not
  random is not refused, and is weaker than its length.
- The two-factor code is short enough to guess and is counted
  (`adr/2026-10-04-wrong-two-factor-codes-are-limited-each-step.md`); only
  someone with the secret reaches it.
- Guesses still reach the server and cost it a comparison each; limiting their
  rate belongs to what sits in front of it.
