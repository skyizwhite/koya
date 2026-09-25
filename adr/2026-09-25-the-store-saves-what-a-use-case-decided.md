# The store saves what a use case decided, and decides nothing itself

*2026-09-25*

## Context

`adr/2026-09-25-the-server-is-layered-and-depends-inward.md` put what koya
does in `usecases/` and left `infra/` to keep its promises. The schema deploy
did not follow: `save-schema` in `infra/db/schema-store` checked the schema,
diffed it against the stored one, applied the renames the diff found, wrote
the deploy log and stored the models. The use case computed the same diff to
decide whether the deploy was destructive, then threw it away and called
`save-schema` with the schema alone, which diffed again.

So the deploy -- what it compares, in what order renames are carried through,
what goes in the log -- was infra's, and could be read and tested only through
SQLite. `usecases/schema/deploy` was a guard in front of it.

## Decision

- **A use case computes the changes and hands them to the store.**
  `save-schema` takes `(space schema changes &key by)`: it stores the schema,
  carries the renames in `changes` through to the content, and logs `changes`
  as a deploy, all in one transaction. It checks nothing and compares nothing.
- **`usecases/schema/deploy` owns the deploy.** `deploy` checks the schema,
  finds the changes, refuses the destructive ones unless forced, and saves.
  `replace-schema` does the same without refusing: what a deploy does once it
  is allowed to, and what an import does to a space with nothing to lose.
  Tests set a space's schema through it too, rather than through the port.
- **The same rule holds for every port.** A port promises what it keeps, not
  what it decides. Where the store still makes a decision that is koya's --
  which is the case for a content's status, its draft key and its history --
  the decision moves out as it is touched.

## Consequences

- One diff per deploy, computed where its result is judged.
- The deploy can be read in one file, and a test of what a rename does to the
  content needs the store, but a test of what is refused does not.
- `save-schema` trusts its caller: given changes that do not match the schema
  it is handed, it will rename what the changes say and store what the schema
  says. The port's documentation says so.
