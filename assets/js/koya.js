// What the admin UI's pages do in the browser, on Nomini. An element asks the
// server with Nomini's own $get and $post, written in its nm-bind (web/lib/binds
// writes them), and Nomini swaps in each element of the answer by its id. A part
// of a page that holds state is a Nomini scope made by one of the factories here
// (nm-data="...koya.bulk(this)"); what needs no state but has to run on an
// element -- on the page and in whatever is swapped in -- is called from its
// oninit.
//
// A member of a scope here starts with _: Nomini sends every other member of
// the scope a request is made from, and calls each such function to do so.
// A scope's state is shallow: a list changes by being set again
// (_chosen = [..._chosen, id]), not by push. A scope does not see the one around
// it, so scopes that work together hold each other (the media field hands the
// picker what to do with a file).
//
// What Nomini leaves to this file:
// - A list goes as Nomini sends an array, comma-separated; koya.form makes a
//   form's fields into what $get and $post send.
// - A refused request (4xx) is drawn like any other answer: Nomini only reports
//   it (fetcherr, with the body in the error's message), so koya.refused hands
//   the body back to the scope's $fetch as a data: URL.
// - A file is sent by koya.upload's own fetch, and its answer drawn the same way.
// - An answer that moves the browser, or replaces the page's URL, is an element
//   swapped into #location, which does it as it is drawn (ui/elements).
{
  const koya = (window.koya ||= {});

  // Nomini writes a bind to the element after an await, so a change sent as the
  // state is set would find the element as it was: it is sent once the binds
  // have run
  const changed = (el) => setTimeout(() => el.dispatchEvent(new Event("change", { bubbles: true })));

  const picker = () => document.getElementById("media-picker")?.nmProxy;

  // a form's fields as $get and $post send them: a name given more than once
  // (a selection, a many field) is a list
  koya.form = (form) => {
    const data = new FormData(form);
    const fields = {};
    for (const name of new Set(data.keys())) {
      const values = data.getAll(name);
      fields[name] = values.length > 1 ? values : values[0];
    }
    return fields;
  };

  // a link followed in place, unless it is asked for in a tab or a window of
  // its own
  koya.follow = (event) => {
    if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return false;
    event.preventDefault();
    return true;
  };

  const drawable = (html) => {
    const template = document.createElement("template");
    template.innerHTML = html;
    return Array.from(template.content.children).some((el) => el.id);
  };

  const textOf = (html) => new DOMParser().parseFromString(html, "text/html").body.textContent.trim();

  // what has nothing to draw is said in the toast, as the layout's toast-failed
  // draws it
  const asToast = (message) => {
    const toast = document.getElementById("toast")?.cloneNode(false);
    const template = document.getElementById("toast-failed");
    if (!toast || !template) return "";
    const alert = template.content.firstElementChild.cloneNode(true);
    if (message) alert.textContent = message;
    toast.append(alert);
    return toast.outerHTML;
  };

  const dataUrl = (html) => {
    const answer = drawable(html) ? html : asToast(textOf(html));
    return answer && `data:text/html;charset=utf-8,${encodeURIComponent(answer)}`;
  };

  // Nomini's error for an answer that is not ok reads "<status text>: <body>";
  // one that never came is a TypeError, and one cut off by a newer request of
  // the same scope an AbortError, which has nothing to say
  koya.refused = (event, draw) => {
    const error = event.detail.err;
    if (error.name === "AbortError") return;
    const message = error instanceof TypeError ? "" : error.message;
    const url = dataUrl(message.slice(message.indexOf(": ") + 2));
    if (url) draw(url);
  };

  // A search form: what it asks goes as the typing stops or a select is picked,
  // and only when it would ask something new (a select fires input and change
  // both; a box fires change as it loses focus).
  koya.search = () => ({
    _asked: null,
    _ask(url, form, always) {
      const data = koya.form(form);
      const asked = `${url}?${new URLSearchParams(data)}`;
      if (!always && asked === this._asked) return;
      this._asked = asked;
      this.$get(url, data);
    },
  });

  // the element asks for what it stands for once it comes into view
  koya.reveal = (event) => {
    const el = event.target;
    const observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      el.dispatchEvent(new CustomEvent("revealed"));
    });
    observer.observe(el);
  };

  // An upload form's files go as they are chosen, checked first against its
  // <template data-upload-limit> (ui/media/grid): too large, the choice is
  // cleared and the template's toast shown.
  koya.upload = async (input, url, draw) => {
    if (input.type !== "file" || input.files.length === 0) return;
    const limit = input.form.querySelector("template[data-upload-limit]");
    const total = Array.from(input.files).reduce((sum, file) => sum + file.size, 0);
    if (limit && total > Number(limit.dataset.uploadLimit)) {
      input.value = "";
      document.getElementById("toast")?.replaceWith(limit.content.cloneNode(true));
      return;
    }
    const answer = await fetch(url, { method: "POST", body: new FormData(input.form), headers: { "nm-request": "true" } })
      .then((response) => response.text())
      .catch(() => "");
    const drawn = dataUrl(answer);
    if (drawn) draw(drawn);
  };

  // Rich text fields: a Quill editor per [data-quill-for] holder (every action on a
  // content draws its editor again). It writes HTML back into the hidden input as
  // the text changes -- unless the editor holds what it was opened with. Quill
  // rewrites HTML it did not write itself (drops ids and figures, adds rel to
  // links...), so writing back an untouched field would record a change nobody
  // made. The server stores the HTML as it arrives, so what the editor writes is
  // tidied here.
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

    koya.quill = (holder) => {
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
              image: () =>
                picker()?._open((item) => {
                  const range = quill.getSelection(true);
                  quill.insertEmbed(range.index, "image", new URL(item.url, location.href).pathname, "user");
                  quill.setSelection(range.index + 1);
                }),
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
        // a value set from script fires nothing; the editor form listens for this
        input.dispatchEvent(new Event("input", { bubbles: true }));
      });
    };
  }

  // Many-reference fields: the <select multiple> that is sent is hidden and
  // follows `_chosen`. The server draws a chip and an "Add" option for every
  // content that can be chosen, and `_chosen` shows one or the other. The select
  // is changed from script, which fires nothing; the editor form listens for the
  // change sent after.
  koya.references = (el) => ({
    _chosen: Array.from(el.querySelector("select[multiple]").selectedOptions, (option) => option.value),
    _has(id) {
      return this._chosen.includes(id);
    },
    _add(select) {
      if (select.value && !this._has(select.value)) this._chosen = [...this._chosen, select.value];
      select.value = "";
      changed(this.$refs.select);
    },
    _remove(id) {
      this._chosen = this._chosen.filter((chosen) => chosen !== id);
      changed(this.$refs.select);
    },
  });

  // Media picker: one <dialog id="media-picker"> per editor page. Its body is
  // fetched as it opens. A card ([data-pick-id]) clicked hands its file to
  // whoever opened the picker: a :media field or a Quill editor.
  koya.mediaPicker = (dialog, url) => ({
    _onpick: null,
    _open(onpick) {
      this._onpick = onpick;
      this.$get(url);
      dialog.showModal();
    },
    _close() {
      this._onpick = null;
      dialog.close();
    },
    _pick(card) {
      const item = { id: card.pickId, url: card.pickUrl, alt: card.pickAlt, name: card.pickName };
      const onpick = this._onpick;
      this._close();
      onpick?.(item);
    },
  });

  // A :media field: the file it holds, sent in its hidden input.
  koya.mediaField = (file) => ({
    _id: file.id,
    _url: file.url,
    _alt: file.alt,
    _name: file.name,
    _choose() {
      picker()?._open((item) => this._set(item));
    },
    _clear() {
      this._set(null);
    },
    _set(item) {
      this._id = item ? item.id : "";
      this._url = item ? item.url : "";
      this._alt = item ? item.alt : "";
      this._name = item ? item.name : "No image";
      changed(this.$refs.input);
    },
  });

  // Settings: draw a QR code for a [data-qr] element (the otpauth URI when
  // setting up two-factor login). qrcode.min.js is davidshimjs/qrcodejs (MIT).
  koya.qr = (el) => {
    if (typeof QRCode === "undefined") return;
    new QRCode(el, { text: el.dataset.qr, width: 192, height: 192, correctLevel: QRCode.CorrectLevel.M });
  };

  // Bulk selection: the ids of the [data-bulk-item] boxes in the scope, and
  // which of them are chosen. A box may sit outside the form it belongs to,
  // tied to it by its form attribute (the media grid does that), so the scope is
  // what holds both.
  koya.bulk = (el) => ({
    _ids: Array.from(el.querySelectorAll("[data-bulk-item]"), (box) => box.value),
    _chosen: [],
    _count() {
      return this._chosen.length;
    },
    _picked(id) {
      return this._chosen.includes(id);
    },
    _pick(id, on) {
      this._chosen = on ? [...this._chosen, id] : this._chosen.filter((chosen) => chosen !== id);
    },
    _all() {
      return this._ids.length > 0 && this._chosen.length === this._ids.length;
    },
    _partly() {
      return this._chosen.length > 0 && this._chosen.length < this._ids.length;
    },
    _pickAll(on) {
      this._chosen = on ? [...this._ids] : [];
    },
  });

  // The editor's Save draft is on only while the form holds something the content
  // does not: a draft that changes nothing is not saved (the server leaves it, or
  // drops the draft when the form is the published data again). What the form was
  // drawn with is the baseline, unless the server says it is unsaved -- a version
  // being restored, or what was sent and refused. Publish is always on: publishing
  // the same data again is a publish.
  koya.editor = (el, unsaved) => {
    const form = el.querySelector("#editor-form");
    const snapshot = () => new URLSearchParams(new FormData(form)).toString();
    const drawn = snapshot();
    return {
      _current: drawn,
      _track() {
        this._current = snapshot();
      },
      _unchanged() {
        return !unsaved && this._current === drawn;
      },
    };
  };

  // Type to confirm: the dialog's submit button is on only while its
  // [data-confirm-phrase] input holds that phrase exactly. The server checks it
  // again, so this is for the owner, not a guard. Closed, the dialog forgets the
  // phrase and the reason a refusal wrote, so it opens as new.
  koya.phrase = (dialog) => ({
    _typed: "",
    _phrase: dialog.querySelector("[data-confirm-phrase]").dataset.confirmPhrase,
    _reset() {
      this._typed = "";
      if (this.$refs.error) this.$refs.error.textContent = "";
    },
  });

  // History: rich text is drawn in a sandboxed iframe, which is as tall as its
  // document once that has loaded -- its stylesheet included.
  koya.fitContent = (frame) => {
    const fit = () => {
      const doc = frame.contentDocument;
      // the body, not the root: the root is never shorter than the frame itself
      if (doc && doc.body) frame.style.height = `${Math.ceil(doc.body.getBoundingClientRect().height)}px`;
    };
    const track = () => {
      const doc = frame.contentDocument;
      if (doc && doc.body) new ResizeObserver(fit).observe(doc.body);
    };
    frame.addEventListener("load", track);
    if (frame.contentDocument && frame.contentDocument.readyState === "complete") track();
  };

  // Import: the archive goes to the import actions in pieces, each a request of
  // its own that says where in the file it goes ([data-import-*] on the form).
  // However large the space, no request is larger than a piece, and the server
  // writes each one to the end of the upload. A piece is a body of its own, not
  // a form, so these are fetches of their own that say they are from the admin
  // UI, as an action requires. The last answer sends the browser to the page
  // where the result waits as a toast.
  koya.importer = (form) => {
    const pieceBytes = Number(form.dataset.importPieceBytes);
    const post = async (url, body) => {
      const response = await fetch(url, {
        method: "POST",
        body,
        headers: { "Content-Type": "application/octet-stream", "nm-request": "true" },
      });
      const text = await response.text();
      if (!response.ok) throw new Error(textOf(text));
      return text;
    };
    const megabytes = (n) => `${(n / 1048576).toFixed(1)} MB`;
    return {
      _busy: false,
      _sent: 0,
      _total: 0,
      _status: "",
      _error: "",
      async _start() {
        const file = this.$refs.file.files[0];
        if (!file || this._busy) return;
        this._error = "";
        this._total = file.size;
        this._sent = 0;
        this._busy = true;
        try {
          const id = (await post(form.dataset.importBegin)).trim();
          for (let offset = 0; offset < file.size; offset += pieceBytes) {
            this._status = `Uploading ${megabytes(offset)} of ${megabytes(file.size)}`;
            const url = `${form.dataset.importContinue}?id=${encodeURIComponent(id)}&offset=${offset}`;
            await post(url, file.slice(offset, offset + pieceBytes));
            this._sent = Math.min(offset + pieceBytes, file.size);
          }
          // the import itself is one step the server takes whole; the site waits
          // for it, and so does this bar
          this.$refs.bar.removeAttribute("value");
          this._status = "Making the space. The server answers nothing else until it is done.";
          this.$fetch(dataUrl(await post(`${form.dataset.importFinish}?id=${encodeURIComponent(id)}`)), "GET");
        } catch (e) {
          this._error = e.message || "The import could not be sent.";
          this._busy = false;
        }
      },
    };
  };
}
