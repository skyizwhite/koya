# Structured data is read through access, at its measured cost

*2026-10-12, restating a decision of 2026-10-12*

## Context

Nested data, a content's data with its custom fields and repeater rows, or a
struct holding such data, is reached through several levels of plists, vectors
and structs. Written by hand, each level is its own call (`getf`, `aref`, an
accessor), and a path through a vector is a nest of them. The `access` library
reads and sets a path through plists, alists, vectors, hash tables and objects
in one call.

`access` checks each level's type at run time. Measured, a read of a content's
field through it takes about 125 ns, where `getf` takes a few. Delivering a list
of 100 contents with custom fields and repeater rows, and writing the answer,
read the data about 3,800 times, about 0.5 ms of an answer that took about
4 ms to make. Reading one level with `getf` and paths with `access` would save
that, at the price of two ways of reading data and of the cases where `getf`
cannot tell a key that is absent from one whose value is `nil`.

## Decision

- A value is found in a content's data by its key or path with `access` and
  `accesses`, and changed with `setf` on them, in `src/` and `spec/`, whether
  the path has one level or several. What looks at every entry of an object, in
  the order it holds them, walks the plist itself. A struct holding data is read
  with its accessors.
- A plist whose keys the code making it fixes, made where it is used, such as a
  deploy's change, a validation error or a media about to be stored, is a
  record rather than data, and is read with `getf`.
- A container is made before anything is put into it. `setf` through a level
  that is not there is not used, since `access` makes a list there, which is
  not the shape the data must have.
- Keys are keywords, strings or indexes, never other symbols: `access` calls a
  function named by a symbol key.

## Consequences

- A path reads as one call, whatever the levels are made of, and a value is
  found one way.
- Finding a value costs what is measured above. A content's fields are found
  through `field-value` and a row's custom field through `row-field-id`, which
  is most of that cost, so if it ever matters, those two are the first to
  change.
- `koya-core`, and so every site using the SDK, depends on `access`, which is
  BSD licensed.
