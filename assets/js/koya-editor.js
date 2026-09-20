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
        toolbar: {
          container: [
            [{ header: [2, 3, 4, false] }],
            ["bold", "italic", "underline", "strike", "code"],
            ["link", "blockquote", "code-block", "image"],
            [{ list: "ordered" }, { list: "bullet" }],
            ["clean"],
          ],
          handlers: {
            // the image button opens the media picker instead of asking for a URL
            image: () => window.koyaMediaPicker && window.koyaMediaPicker.open({ kind: "quill", quill }),
          },
        },
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

// List rows: a [data-href] row opens its editor on click or Enter, unless the
// click landed on a real link or button inside it.
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-href]").forEach((row) => {
    const open = () => { window.location.href = row.dataset.href; };
    row.addEventListener("click", (event) => {
      if (event.target.closest("a, button, input, select")) return;
      open();
    });
    row.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && event.target === row) open();
    });
  });
});

// Many-reference fields: the <select multiple> keeps the submitted values but is
// hidden; the user sees the chosen contents as chips and adds more from an
// ordinary dropdown.
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("select[multiple][data-picker]").forEach((select) => {
    const wrap = document.createElement("div");
    wrap.className = "flex flex-wrap items-center gap-2";
    const chips = document.createElement("div");
    chips.className = "flex flex-wrap items-center gap-2";
    const picker = document.createElement("select");
    picker.setAttribute("aria-label", "Add");
    wrap.append(chips, picker);

    const render = () => {
      chips.replaceChildren();
      picker.replaceChildren(new Option("Add…", ""));
      Array.from(select.options).forEach((option) => {
        if (option.selected) {
          const chip = document.createElement("span");
          chip.className = "badge inline-flex items-center gap-1 bg-line text-fg";
          chip.append(option.text);
          const remove = document.createElement("button");
          remove.type = "button";
          remove.className = "text-muted hover:text-danger";
          remove.setAttribute("aria-label", `Remove ${option.text}`);
          remove.textContent = "×";
          remove.addEventListener("click", () => { option.selected = false; render(); });
          chip.append(remove);
          chips.append(chip);
        } else {
          picker.append(new Option(option.text, option.value));
        }
      });
      picker.value = "";
    };
    picker.addEventListener("change", () => {
      const option = Array.from(select.options).find((o) => o.value === picker.value);
      if (option) option.selected = true;
      render();
    });

    select.hidden = true;
    select.after(wrap);
    render();
  });
});

// Media picker: one <dialog id="media-picker"> per editor page. Its body is
// fetched with HTMX from data-picker-url when opened. A click on a card
// ([data-pick-id]) hands the file to whoever opened the picker: a :media field
// (hidden input + preview) or a Quill editor (inserts an <img>).
document.addEventListener("DOMContentLoaded", () => {
  const dialog = document.getElementById("media-picker");
  if (!dialog) return;
  let target = null;

  const picker = {
    open(t) {
      target = t;
      const body = dialog.querySelector("#media-picker-body");
      if (body && window.htmx) htmx.ajax("GET", dialog.dataset.pickerUrl, { target: body, swap: "outerHTML" });
      dialog.showModal();
    },
    close() {
      target = null;
      dialog.close();
    },
  };
  window.koyaMediaPicker = picker;

  const setField = (name, item) => {
    const wrap = document.querySelector(`[data-media-field="${name}"]`);
    if (!wrap) return;
    const input = wrap.querySelector("input[type=hidden]");
    const img = wrap.querySelector("[data-media-preview]");
    const label = wrap.querySelector("[data-media-name]");
    input.value = item ? item.id : "";
    if (item) {
      img.src = item.url;
      img.alt = item.alt;
      img.classList.remove("hidden");
      label.textContent = item.name;
    } else {
      img.removeAttribute("src");
      img.classList.add("hidden");
      label.textContent = "No image";
    }
  };

  document.querySelectorAll("[data-media-pick-for]").forEach((button) => {
    button.addEventListener("click", () => picker.open({ kind: "field", name: button.dataset.mediaPickFor }));
  });
  document.querySelectorAll("[data-media-clear-for]").forEach((button) => {
    button.addEventListener("click", () => setField(button.dataset.mediaClearFor, null));
  });
  dialog.querySelector("[data-dialog-close]").addEventListener("click", picker.close);
  dialog.addEventListener("click", (event) => {
    // a click on the backdrop lands on the dialog element itself
    if (event.target === dialog) picker.close();
  });

  dialog.addEventListener("click", (event) => {
    const card = event.target.closest("[data-pick-id]");
    if (!card || !target) return;
    const item = { id: card.dataset.pickId, url: card.dataset.pickUrl, alt: card.dataset.pickAlt, name: card.dataset.pickName };
    if (target.kind === "field") {
      setField(target.name, item);
    } else if (target.kind === "quill") {
      const quill = target.quill;
      const range = quill.getSelection(true);
      quill.insertEmbed(range.index, "image", item.url, "user");
      quill.setSelection(range.index + 1);
    }
    picker.close();
  });
});

// Image preview: [data-preview-src] buttons (the library thumbnails and their
// Preview buttons) show the image large in <dialog id="media-preview">.
document.addEventListener("DOMContentLoaded", () => {
  const dialog = document.getElementById("media-preview");
  if (!dialog) return;
  const image = dialog.querySelector("[data-preview-image]");
  const title = dialog.querySelector("[data-preview-title]");
  const caption = dialog.querySelector("[data-preview-caption]");
  const open = dialog.querySelector("[data-preview-open]");

  document.querySelectorAll("[data-preview-src]").forEach((button) => {
    button.addEventListener("click", () => {
      image.src = button.dataset.previewSrc;
      image.alt = button.dataset.previewAlt || "";
      title.textContent = button.dataset.previewName || "";
      caption.textContent = button.dataset.previewMeta || "";
      open.href = button.dataset.previewSrc;
      dialog.showModal();
    });
  });
  dialog.querySelector("[data-dialog-close]").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dialog.close();
  });
  dialog.addEventListener("close", () => image.removeAttribute("src"));
});

// Settings: draw a QR code for every [data-qr] element (the otpauth URI when
// setting up two-factor login). qrcode.min.js is davidshimjs/qrcodejs (MIT).
document.addEventListener("DOMContentLoaded", () => {
  if (typeof QRCode === "undefined") return;
  document.querySelectorAll("[data-qr]").forEach((el) => {
    new QRCode(el, { text: el.dataset.qr, width: 192, height: 192, correctLevel: QRCode.CorrectLevel.M });
  });
});

// Buttons with data-confirm ask before their form submits. The text lives in an
// attribute rather than an inline handler, so any file name is safe in it.
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-confirm]").forEach((button) => {
    button.addEventListener("click", (event) => {
      if (!window.confirm(button.dataset.confirm)) event.preventDefault();
    });
  });
});
