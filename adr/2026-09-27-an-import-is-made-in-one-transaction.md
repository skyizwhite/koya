# An import is made in one transaction

*2026-09-27, restating a decision of 2026-09-25*

## Context

Once the whole archive is uploaded, its schema, keys, media and contents with
their history have to be written. An import that stopped half way would leave a
space that is neither empty nor what was exported.

## Decision

A last action imports the upload in one transaction, so an import is all or
nothing.

## Consequences

While an import is made, the instance answers nothing else, the delivery API
included, because the transaction holds the store. It is kept that way because
moving a space is rare.
