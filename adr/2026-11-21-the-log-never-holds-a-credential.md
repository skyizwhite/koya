# The log never holds a credential

*2026-11-21*

## Context

The server's messages were `format` calls to standard output or standard error,
with no time and no level, and an unhandled error was logged as its message
alone, or, from the admin UI, by lack-mw's recovery with a backtrace whose
frames print their arguments. Those arguments can be the owner secret, a
one-time code, a session or a key, and a webhook's URL, which the old webhook
line printed, is a token for some receivers (a deploy hook's URL is its
secret). A log is read and kept by more than the owner: the container runtime,
a log service.

## Decision

- The server logs through verbose, to standard output, one line per event with
  its time, level and category. Every layer may log, through `koya-server/log`
  (`log-info`, `log-warn`, `log-error`), so the setting up is in `main` alone
  and no package needs verbose's names, two of which are `cl:warn` and
  `cl:error`.
- There is no level setting: what is logged is what an owner looks for
  afterwards, at info and above, and verbose's level can be changed at the REPL.
- A line never holds a credential, whatever it is about:
  - an unhandled error is logged with the method, the path without its query,
    the condition and the name of each function it went through, never their
    arguments; koya captures the backtrace itself, where the error is signalled,
    and recovery logs nothing of its own;
  - a webhook that fails is named by its label, with the status it answered or
    that it gave no answer, never its URL nor what the failure says, which can
    name it; the delivery log in the admin UI keeps the rest;
  - a login says whether it was let in or why it was refused, never what was
    typed;
  - the access log, Lack's, is given koya's formatter: the request's URL and its
    Referer are written up to their query, which is where a preview's
    `draftKey` travels.

## Consequences

- An unhandled error still says where it happened, and its arguments are not
  there to say why: reproducing it is how it is found.
- A message from a condition, such as a type error on a value, is logged as it
  is; nothing koya passes a credential through is expected to fail that way.
- Neither log shows which filters or page a request asked for.
