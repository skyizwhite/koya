# A preview embeds only published references

*2026-10-04*

## Context

A draft key serves one content's draft, so a site can preview it. When the
preview names references in `include`, the contents it points at may be drafts
too: a new post that links a new tag, or a published author with unpublished
edits. Embedding their drafts would show the page as it would be once every
related draft is published. It would also let one content's draft key read the
drafts of every content it refers to.

A content can be published while it refers to a draft (only deleting or
unpublishing a referenced content is refused), and publishing it publishes
nothing else.

## Decision

A draft key opens its own content's draft and nothing more. What `include`
embeds is the published data of the referenced contents, in a preview as in any
other answer: one that has never been published, or has been unpublished, drops
out of a `many` field and is `null` in a single one, and one with a draft shows
what is live.

## Consequences

- A preview shows what publishing that one content would put on the site.
- A draft key reveals one content's draft, whatever it refers to.
- To preview a page with a new referenced content in it, that content is
  published first.
