// Rich text fields: a Quill editor per [data-quill-for] holder, on the page and
// in whatever htmx swaps in (every action on a content draws its editor again).
// It writes HTML back into the hidden input as the text changes -- unless the
// editor holds what it was opened with. The buttons send the form with htmx,
// which fires no submit event, so the input has to be current all along. Quill rewrites HTML it did not
// write itself (drops ids and figures, adds rel to links...), so writing back
// an untouched field would record a change nobody made. The server stores the
// HTML as it arrives, so what the editor writes is tidied here.
//
// Two Quill quirks are worked around here:
// - pasted text has every whitespace character (including U+3000, the
//   ideographic space) collapsed to an ASCII space, so U+3000 is swapped for a
//   private-use placeholder before loading and restored on save;
// - getSemanticHTML() turns every ASCII space into &nbsp;, which is undone for
//   single spaces (runs of two or more are kept, they are deliberate).
{
  const IDEOGRAPHIC_SPACE = "　";
  const PLACEHOLDER = "";

  const protect = (html) => html.replaceAll(IDEOGRAPHIC_SPACE, PLACEHOLDER);
  const restore = (html) =>
    html
      .replaceAll(PLACEHOLDER, IDEOGRAPHIC_SPACE)
      .replace(/(^|[^;&])&nbsp;(?!&nbsp;)/g, "$1 ")
      .replace(/&nbsp;(?=\S)(?!&nbsp;)/g, " ");
  // an empty paragraph is a blank line the site should show; a line break after
  // every block keeps the stored source readable; this server's own media is
  // stored by path, which the delivery API makes absolute again
  const BLOCK_END = /(<\/(?:p|h[1-6]|ul|ol|li|blockquote|pre|table|thead|tbody|tr|figure)>|<hr\s*\/?>)\s*/g;
  const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const ownMedia = new RegExp(`(src|href)="${escapeRegExp(location.origin)}/media/`, "g");
  const tidy = (html) =>
    html
      .replace(/<p>\s*<\/p>/g, "<p><br></p>")
      .replace(BLOCK_END, "$1\n")
      .replace(ownMedia, '$1="/media/')
      .trim();

  htmx.onLoad((root) => root.querySelectorAll("[data-quill-for]").forEach((holder) => {
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
    const opened = tidy(restore(quill.getSemanticHTML()));
    const original = input.value;
    quill.on("text-change", () => {
      const html = tidy(restore(quill.getSemanticHTML()));
      input.value = html === opened ? original : html;
    });
  }));
}

// Many-reference fields: the <select multiple> keeps the submitted values but is
// hidden; the user sees the chosen contents as chips and adds more from an
// ordinary dropdown. Built for whatever htmx swaps in, as the rich text is.
htmx.onLoad((root) => {
  root.querySelectorAll("select[multiple][data-picker]").forEach((select) => {
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
      const content = dialog.querySelector("#media-picker-content");
      if (content && window.htmx) htmx.ajax("GET", dialog.dataset.pickerUrl, { target: content, swap: "innerHTML" });
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

  // listened for on the document: the editor is drawn again by every action on it
  document.addEventListener("click", (event) => {
    const pick = event.target.closest("[data-media-pick-for]");
    const clear = event.target.closest("[data-media-clear-for]");
    if (pick) picker.open({ kind: "field", name: pick.dataset.mediaPickFor });
    if (clear) setField(clear.dataset.mediaClearFor, null);
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
      quill.insertEmbed(range.index, "image", new URL(item.url, location.href).pathname, "user");
      quill.setSelection(range.index + 1);
    }
    picker.close();
  });
});

// A <dialog data-show-modal> that htmx swaps in opens itself as a modal: the
// server draws a dialog's contents for what it shows (the media preview), and an
// element swapped in cannot be opened by the button that asked for it.
htmx.onLoad((root) => {
  const dialogs = root.matches?.("dialog[data-show-modal]") ? [root] : root.querySelectorAll("dialog[data-show-modal]");
  dialogs.forEach((dialog) => { if (!dialog.open) dialog.showModal(); });
});

// Settings: draw a QR code for every [data-qr] element (the otpauth URI when
// setting up two-factor login), on the page and in whatever htmx swaps in --
// setting up is answered in place. qrcode.min.js is davidshimjs/qrcodejs (MIT).
const drawQrCodes = (root) => {
  if (typeof QRCode === "undefined") return;
  root.querySelectorAll("[data-qr]").forEach((el) => {
    new QRCode(el, { text: el.dataset.qr, width: 192, height: 192, correctLevel: QRCode.CorrectLevel.M });
  });
};
if (window.htmx) htmx.onLoad(drawQrCodes);
else document.addEventListener("DOMContentLoaded", () => drawQrCodes(document));

// Bulk selection: inside a [data-bulk] form, ticking a [data-bulk-item] box shows
// the [data-bulk-bar] and counts into [data-bulk-count]. [data-bulk-all] selects
// and clears the page.
// The bar starts hidden, so bulk actions need this file. Bound for whatever htmx
// swaps in as well: the media library draws its selection again after each action.
htmx.onLoad((root) => {
  root.querySelectorAll("form[data-bulk]").forEach((form) => {
    // form.elements, not querySelectorAll: a box may sit outside the form, tied
    // to it by its form attribute (the media grid does that)
    const controls = () => Array.from(form.elements);
    const boxes = () => controls().filter((el) => el.matches("[data-bulk-item]"));
    const bar = form.querySelector("[data-bulk-bar]");
    const all = controls().find((el) => el.matches("[data-bulk-all]"));
    const count = form.querySelector("[data-bulk-count]");
    const render = () => {
      const items = boxes();
      const n = items.filter((box) => box.checked).length;
      if (bar) bar.hidden = n === 0;
      if (count) count.textContent = `${n} selected`;
      if (all) {
        all.checked = n > 0 && n === items.length;
        all.indeterminate = n > 0 && n < items.length;
      }
    };
    boxes().forEach((box) => box.addEventListener("change", render));
    if (all) {
      all.addEventListener("change", () => {
        boxes().forEach((box) => { box.checked = all.checked; });
        render();
      });
    }
    render();
  });
});

// History: rich text is drawn in a sandboxed [data-fit-content] iframe, which
// is as tall as its document once that has loaded -- its stylesheet included.
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("iframe[data-fit-content]").forEach((frame) => {
    const fit = () => {
      const doc = frame.contentDocument;
      // the body, not the root: the root is never shorter than the frame itself
      if (doc && doc.body) frame.style.height = `${doc.body.scrollHeight}px`;
    };
    frame.addEventListener("load", fit);
    if (frame.contentDocument && frame.contentDocument.readyState === "complete") fit();
  });
});

// Import: the archive goes to the import action ([data-import]) as the request
// body itself, not as a multipart form, so the server can copy it to disk instead
// of holding it in memory. htmx sends forms only, so this is a fetch that says it
// is htmx, as an action requires. The answer names the page to go to in
// HX-Redirect, where the result waits as a flash.
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("form[data-import]").forEach((form) => {
    const error = form.querySelector("[data-import-error]");
    const submit = form.querySelector("button[type=submit]");
    const label = submit.innerHTML;
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const file = form.querySelector("input[type=file]").files[0];
      if (!file) return;
      submit.disabled = true;
      submit.textContent = "Importing…";
      error.classList.add("hidden");
      try {
        const response = await fetch(form.dataset.import, {
          method: "POST",
          body: file,
          headers: { "Content-Type": "application/zip", "HX-Request": "true" },
        });
        const text = await response.text();
        if (!response.ok) throw new Error(new DOMParser().parseFromString(text, "text/html").body.textContent);
        window.location.href = response.headers.get("HX-Redirect") || "/";
      } catch (e) {
        error.textContent = e.message || "The import could not be sent.";
        error.classList.remove("hidden");
        submit.disabled = false;
        submit.innerHTML = label;
      }
    });
  });
});
