# The log never holds a credential

*2026-11-21*

## Context

A log is read and kept by more than the owner: the container runtime, a log
service. What koya wrote before could hold credentials. lack-mw's recovery
logged an admin UI error with a backtrace whose frames print their arguments,
which can be the owner secret, a one-time code, a session or a key. The webhook
line printed the webhook's URL, which is the secret of some receivers, such as a
deploy hook. Lack's access log wrote each request's URL and Referer whole, and a
preview's `draftKey` travels in their query.

## Decision

A line never holds a credential, whatever it is about:

- An unhandled error is logged with the method, the path without its query, the
  condition and the name of each function it went through, never their
  arguments. koya captures the backtrace itself, where the error is signalled,
  and recovery logs nothing of its own.
- A webhook that fails is named by its label, with the status it answered or
  that it gave no answer. Neither its URL nor what the failure says, which can
  name the URL, is logged; the delivery log in the admin UI keeps them.
- A login says whether it was let in or why it was refused, never what was
  typed.
- The access log writes a request's URL and its Referer up to their query.

## Consequences

- An unhandled error still says where it happened, but its arguments are not
  there to say why: it is found by reproducing it.
- A condition's message, such as a type error on a value, is logged as it is.
  Nothing koya passes a credential through is expected to fail that way.
- The access log does not show which filters or page a request asked for.
