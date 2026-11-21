# The server has one log that every layer writes to

*2026-11-21*

## Context

The server's messages were `format` calls, some to standard output and some to
standard error, with no time and no level. Lack's access log wrote to standard
output beside them. Something worth logging happens in every layer: the time
zone database in the domain, logins and deploys in the use cases, migrations in
infra, errors in the web.

## Decision

- The server logs through verbose to standard output, a line per event with its
  time, level and category (`:koya.auth`, `:koya.http`, `:koya.access` and so
  on).
- Every layer writes through `koya-server/log` (`log-info`, `log-warn`,
  `log-error`), a layer under all the others. It is the only layer that uses
  verbose. Only `main` sets verbose up: no colours, and the thread verbose writes
  from is stopped before the image is saved and started again when the
  executable runs. A package cannot nickname verbose, which package-inferred
  systems do not allow, nor import its `warn` and `error`, which are named as
  `cl:warn` and `cl:error` are.
- The access log is written through the log too, so one thread writes every
  line and no two lines run into each other.

## Consequences

- An access line carries the log's time and level in front of Lack's own line.
- What clack, Woo and ningle print by themselves is outside the log.
