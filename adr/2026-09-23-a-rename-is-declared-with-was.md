# A rename is declared with `:was`

*2026-09-23*

## Context

Models and fields are matched by name, so renaming one and deploying read as a
removal and an addition. A renamed field left its values under the old key,
invisible to the editor and dropped by the next save; a renamed model was worse,
because contents reference `models(space, name)` with `ON DELETE CASCADE`, so
the deploy deleted every content of it.

## Decision

`:was` on a model or a field names what it used to be called. The diff turns it
into `rename_model` / `rename_field`, and `save-schema` carries it through to
the stored content in the same transaction as the schema write.

Nothing is lost, so a rename is not a destructive change and needs no `force`.

`:was` is an instruction to the deploy, not part of the shape: the server stores
the new name alone, so `pull` never brings one back, and leaving it in the
source is a no-op once applied.

## Consequences

Renaming is a thing that can be done. It must be declared — silence still means
removal and addition — which is the right default: the server cannot tell a
rename from a deletion and a new field by looking.

A `:was` must be dropped only once every space the schema is deployed to has had
the rename, or those spaces read the version without it as a removal.
