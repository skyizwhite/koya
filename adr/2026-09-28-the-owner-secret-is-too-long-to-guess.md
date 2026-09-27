# The owner secret is too long to guess, and failed logins lock nobody out

*2026-09-28*

## Context

The login page is open to anyone and asks for the owner's secret. It used to
count failed logins per address and refuse an address after five, even with
the right secret. Behind a reverse proxy every client has the proxy's address,
so anyone could keep the owner from logging in by failing five times every few
minutes. Counting the address a proxy forwards would mean deciding which
proxies to trust, and a lock that the right secret passes stops no guessing.

## Decision

- `KOYA_SECRET` is at least 32 characters. It is set where the server runs, not
  remembered by a person, so a random one costs nothing.
- Failed logins are not counted, and no address is ever refused.

## Consequences

- Nobody can lock the owner out, whatever sits in front of the server.
- Guessing is limited by the secret's length alone: 32 random characters are
  out of reach at any rate the server can answer.
- A two-factor code, when it is on, is still asked for after the secret.
- Guesses still reach the server and cost it a comparison each.
