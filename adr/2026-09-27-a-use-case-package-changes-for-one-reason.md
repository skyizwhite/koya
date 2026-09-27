# A use-case package is one part of koya, which changes for one reason

*2026-09-27*

## Context

`usecases/` had grown directories whose files split one part of koya by the
steps it took, so a change to one behaviour touched several packages, and a
package held things that changed for different reasons.

## Decision

- A use-case package is one part of koya, in one file.
- A part is what changes for one reason. Writing a content, the admin's reading
  of a list, the delivery API's reading and a content's history are four parts,
  because each changes for its own reasons.
- `usecases/` has no directories but `ports/`.

## Consequences

A change to one behaviour of koya is a change to one use-case package.
