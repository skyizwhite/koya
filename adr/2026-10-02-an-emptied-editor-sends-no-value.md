# An emptied editor sends no value; blank is the same for every type

*2026-10-02*

## Context

Quill never gives back an empty string: a document with nothing in it is
`<p><br></p>`. Rich text was made blank when it held only empty paragraphs,
whoever sent it, so that a required rich text field could not be saved emptied.
That put one editor's markup into the rule for blank, and every reader of blank
had to know it: `required`, the form, and the `exists` filter, which runs in SQL
and cannot use the same pattern.

## Decision

- Blank is `null`, a whitespace-only string, or `[]` on a `many` field, for
  every type. Rich text has no rule of its own.
- An editor's way of writing "nothing" is turned into no value where the editor
  is: `koya.js` sends an emptied Quill document as an empty string, which the
  form reads as no value, as it does for every field.

## Consequences

- `required`, the form and the `exists` filter read blank the same way.
- Markup sent through the admin API is a value, even if it shows nothing:
  `<p></p>` satisfies `required`. What a client sends is what it meant.
- Another editor, if one is added, owns its own empty document in the same way.
