// Rich text fields: a Quill editor per [data-quill-for] holder, writing HTML
// back into the hidden input just before the form is submitted.
//
// Two Quill quirks are worked around here:
// - pasted text has every whitespace character (including U+3000, the
//   ideographic space) collapsed to an ASCII space, so U+3000 is swapped for a
//   private-use placeholder before loading and restored on save;
// - getSemanticHTML() turns every ASCII space into &nbsp;, which is undone for
//   single spaces (runs of two or more are kept, they are deliberate).
document.addEventListener("DOMContentLoaded", () => {
  const IDEOGRAPHIC_SPACE = "　";
  const PLACEHOLDER = "";
  const editors = [];

  const protect = (html) => html.replaceAll(IDEOGRAPHIC_SPACE, PLACEHOLDER);
  const restore = (html) =>
    html
      .replaceAll(PLACEHOLDER, IDEOGRAPHIC_SPACE)
      .replace(/(^|[^;&])&nbsp;(?!&nbsp;)/g, "$1 ")
      .replace(/&nbsp;(?=\S)(?!&nbsp;)/g, " ");

  document.querySelectorAll("[data-quill-for]").forEach((holder) => {
    const input = document.getElementById(holder.dataset.quillFor);
    if (!input || typeof Quill === "undefined") return;
    const quill = new Quill(holder, {
      theme: "snow",
      placeholder: "Write here...",
      modules: {
        toolbar: [
          [{ header: [2, 3, 4, false] }],
          ["bold", "italic", "underline", "strike", "code"],
          ["link", "blockquote", "code-block", "image"],
          [{ list: "ordered" }, { list: "bullet" }],
          ["clean"],
        ],
      },
    });
    if (input.value) quill.clipboard.dangerouslyPasteHTML(protect(input.value));
    editors.push({ quill, input });
  });

  document.querySelectorAll("form[data-editor-form]").forEach((form) => {
    form.addEventListener("submit", () => {
      editors.forEach(({ quill, input }) => {
        if (form.contains(input)) input.value = restore(quill.getSemanticHTML());
      });
    });
  });
});
