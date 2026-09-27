# JSON keys are camelCase

*2026-09-27, restating a decision of 2026-09-20*

## Context

koya's APIs are read mostly from TypeScript, where keys are camelCase, and also
from Lisp, where they are kebab-case keywords.

## Decision

- Every JSON key koya writes or reads is camelCase.
- The Lisp client converts them to kebab-case keywords and back.

## Consequences

A TypeScript site uses the JSON as it comes. A Lisp site never sees a camelCase
key.
