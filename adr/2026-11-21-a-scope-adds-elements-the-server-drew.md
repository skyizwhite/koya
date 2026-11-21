# A scope adds elements the server drew

*2026-11-21*

## Context

A Nomini scope shows, hides and changes the elements it is bound to, but makes
none. A list a field holds in the browser -- the chips of a many reference, the
thumbnails of many media -- was first drawn whole by the server, every element
it could ever show, and the scope showed or hid each one. That meant the page
carried every content of a target model for each reference field, and a list
could not be put in the order the editor wanted. The media list had already
moved to cloning a template; the reference cards, chosen from a picker that
pages through the contents, cannot be drawn ahead at all.

## Decision

- An element a scope adds is drawn by the server in a `<template>`, and the
  scope clones it: a field holds the template of its own entry, or a picker
  hands over a finished one with each item.
- The scope fills in values only -- those of the item picked, and the name of
  the field the entry is sent under. Its markup is the server's.

## Consequences

- The server draws what a field holds, not everything it could hold.
- An entry's markup lives in one Lisp component, used both for the page and for
  the template.
- A list is reordered by moving its elements; the form sends them in the order
  they stand.
