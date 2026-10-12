# Structured data is read and changed through access

Superseded by adr/2026-10-12-structured-data-is-read-through-access-at-its-measured-cost.md

*2026-10-12*

## Context

Nested data, a content's data with its custom fields and repeater rows, or a
struct holding such data, is reached through several levels of plists, vectors
and structs. Written by hand, each level is its own call (`getf`, `aref`, an
accessor), and a path through a vector is a nest of them. The `access` library
reads and sets a path through plists, alists, vectors, hash tables and objects
in one call.

## Decision

- Structured data is read with `access` and `accesses`, and changed with
  `setf` on them, in `src/` and `spec/`.
- A container is made before anything is put into it. `setf` through a level
  that is not there is not used, since `access` makes a list there, which is
  not the shape the data must have.
- Keys are keywords, strings or indexes, never other symbols: `access` calls a
  function named by a symbol key.

## Consequences

- A path reads as one call, whatever the levels are made of.
- `access` checks each level's type at run time and is several times slower
  than a direct `getf`; at koya's sizes this is not measurable in a request.
- `koya-core`, and so every site using the SDK, depends on `access`, which is
  BSD licensed.
