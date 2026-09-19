// Rich text fields: a Quill editor per [data-quill-for] holder, writing HTML
// back into the hidden input just before the form is submitted.
document.addEventListener("DOMContentLoaded", () => {
  const editors = [];
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
    if (input.value) quill.clipboard.dangerouslyPasteHTML(input.value);
    editors.push({ quill, input });
  });
  document.querySelectorAll("form[data-editor-form]").forEach((form) => {
    form.addEventListener("submit", () => {
      editors.forEach(({ quill, input }) => {
        if (form.contains(input)) input.value = quill.getSemanticHTML();
      });
    });
  });
});
