# Wrong two-factor codes are limited each time step

*2026-10-04*

## Context

The two-factor code was asked for after the secret and wrong ones were not
counted, as for the secret. That holds for 32 random characters, not for six
digits of which three are valid at any moment: once the secret has leaked,
guessing finds a code within minutes. The step a code was last used in was kept
in memory, so a restart let the same code in again.

## Decision

- Five wrong codes in one 30-second step close logging in until the next step,
  counted for the whole server rather than per address. While it is closed every
  attempt is refused the same way, with the right secret or a wrong one.
- Only an attempt with the right secret counts: one with a wrong secret is
  refused before any code is read.
- The last step a code was used in, and the count, are kept in `settings`, and
  turning two-factor off forgets both.

## Consequences

- With the secret, finding a valid code takes days of guessing, not minutes.
- Someone who has the secret can keep the owner out by spending the codes each
  step; the answer is a new secret, which ends every session as well.
- Someone who lacks it can neither fill the count nor learn from the refusal
  whether a secret was right.
- A code once used stays used across a restart. A code used to turn two-factor
  on cannot then log in, so logging in right after it waits for the next code.
- A new secret set up right after turning two-factor off takes its first code at
  once: the step the old one used is gone with it.
