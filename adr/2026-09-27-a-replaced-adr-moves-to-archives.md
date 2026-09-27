# A replaced ADR moves to adr/archives/

*2026-09-27*

## Context

A replaced ADR stayed in `adr/` beside the one that replaced it, with a
`Superseded by` line under its title. An AI agent that searched `adr/` found
both, and had to work out which one still held. Many were replaced in part, so
half of an old ADR was true and half was not.

## Decision

- When an ADR is replaced, it moves to `adr/archives/`. Its `Superseded by`
  lines stay under its title and name the ADRs that replaced it.
- `.ignore` lists `adr/archives/`, so ripgrep and the tools built on it leave it
  out of a search. An agent reads it only when asked to.
- Where an ADR's Context names one in `adr/archives/`, that is history: the
  decision reads without it, and an agent does not follow it unless asked. A
  new ADR restates what it needs rather than pointing there.

## Consequences

- `adr/` holds only what is decided now, and the reasons for it.
- The history is still in `adr/archives/` and in git, for a person who asks how
  koya came to be this way.
