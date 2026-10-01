// What the admin UI's pages do in the browser. A part of a page that holds
// state is a Nomini scope made by one of these (nm-data="...koya.bulk(this)"),
// and its elements read and change that state with nm-bind. What needs no state
// but has to run on an element -- on the page and in whatever is swapped in --
// is called from the element's oninit. Talking to the server is koya-fetch.js.
//
// A scope's state is shallow: a list changes by being set again
// (chosen = [...chosen, id]), not by push. A scope does not see the one around
// it, so scopes that work together hold each other (the media field hands the
// picker what to do with a file).
{
  const koya = (window.koya ||= {});

  // Nomini writes a bind to the element after an await, so a change sent as the
  // state is set would find the element as it was: it is sent once the binds
  // have run
  const changed = (el) => setTimeout(() => el.dispatchEvent(new Event("change", { bubbles: true })));

  const picker = () => document.getElementById("media-picker")?.nmProxy;

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
                picker()?.open((item) => {
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
  // follows `chosen`. The server draws a chip and an "Add" option for every
  // content that can be chosen, and `chosen` shows one or the other. The select
  // is changed from script, which fires nothing; the editor form listens for the
  // change sent after.
  koya.references = (el) => ({
    chosen: Array.from(el.querySelector("select[multiple]").selectedOptions, (option) => option.value),
    has(id) {
      return this.chosen.includes(id);
    },
    add(select) {
      if (select.value && !this.has(select.value)) this.chosen = [...this.chosen, select.value];
      select.value = "";
      changed(this.$refs.select);
    },
    remove(id) {
      this.chosen = this.chosen.filter((chosen) => chosen !== id);
      changed(this.$refs.select);
    },
  });

  // Media picker: one <dialog id="media-picker"> per editor page. Its body is
  // fetched from its data-get as it opens. A card ([data-pick-id]) clicked hands
  // its file to whoever opened the picker: a :media field or a Quill editor.
  koya.mediaPicker = (dialog) => ({
    onpick: null,
    open(onpick) {
      this.onpick = onpick;
      koya.get(dialog, dialog.dataset.get);
      dialog.showModal();
    },
    close() {
      this.onpick = null;
      dialog.close();
    },
    pick(card) {
      const item = { id: card.pickId, url: card.pickUrl, alt: card.pickAlt, name: card.pickName };
      const onpick = this.onpick;
      this.close();
      onpick?.(item);
    },
  });

  // A :media field: the file it holds, drawn from its data-* and sent in its
  // hidden input.
  koya.mediaField = (data) => ({
    id: data.id,
    url: data.url,
    alt: data.alt,
    name: data.name,
    choose() {
      picker()?.open((item) => this.set(item));
    },
    clear() {
      this.set(null);
    },
    set(item) {
      this.id = item ? item.id : "";
      this.url = item ? item.url : "";
      this.alt = item ? item.alt : "";
      this.name = item ? item.name : "No image";
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
  // which of them are chosen. A box may sit outside the form it is sent with,
  // tied to it by its form attribute (the media grid does that), so the scope is
  // what holds both.
  koya.bulk = (el) => ({
    ids: Array.from(el.querySelectorAll("[data-bulk-item]"), (box) => box.value),
    chosen: [],
    count() {
      return this.chosen.length;
    },
    picked(id) {
      return this.chosen.includes(id);
    },
    pick(id, on) {
      this.chosen = on ? [...this.chosen, id] : this.chosen.filter((chosen) => chosen !== id);
    },
    all() {
      return this.ids.length > 0 && this.chosen.length === this.ids.length;
    },
    partly() {
      return this.chosen.length > 0 && this.chosen.length < this.ids.length;
    },
    pickAll(on) {
      this.chosen = on ? [...this.ids] : [];
    },
  });

  // The editor's Save draft is on only while the form holds something the content
  // does not: a draft that changes nothing is not saved (the server leaves it, or
  // drops the draft when the form is the published data again). What the form was
  // drawn with is the baseline, unless the server marks it data-unsaved -- a version
  // being restored, or what was sent and refused. Publish is always on: publishing
  // the same data again is a publish.
  koya.editor = (el) => {
    const form = el.querySelector("#editor-form");
    const snapshot = () => new URLSearchParams(new FormData(form)).toString();
    const drawn = snapshot();
    return {
      unsaved: "unsaved" in form.dataset,
      current: drawn,
      track() {
        this.current = snapshot();
      },
      unchanged() {
        return !this.unsaved && this.current === drawn;
      },
    };
  };

  // Type to confirm: the dialog's submit button is on only while its
  // [data-confirm-phrase] input holds that phrase exactly. The server checks it
  // again, so this is for the owner, not a guard. Closed, the dialog forgets the
  // phrase and the reason a refusal wrote, so it opens as new.
  koya.phrase = (dialog) => ({
    typed: "",
    phrase: dialog.querySelector("[data-confirm-phrase]").dataset.confirmPhrase,
    reset() {
      this.typed = "";
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
  // UI, as an action requires. The last answer names the page to go to in
  // Koya-Redirect, where the result waits as a toast.
  koya.importer = (form) => {
    const pieceBytes = Number(form.dataset.importPieceBytes);
    const post = async (url, body) => {
      const response = await fetch(url, {
        method: "POST",
        body,
        headers: { "Content-Type": "application/octet-stream", "Koya-Request": "true" },
      });
      const text = await response.text();
      if (!response.ok) throw new Error(new DOMParser().parseFromString(text, "text/html").body.textContent);
      return { text, response };
    };
    const megabytes = (n) => `${(n / 1048576).toFixed(1)} MB`;
    return {
      busy: false,
      sent: 0,
      total: 0,
      status: "",
      error: "",
      async start(event) {
        event.preventDefault();
        const file = this.$refs.file.files[0];
        if (!file || this.busy) return;
        this.error = "";
        this.total = file.size;
        this.sent = 0;
        this.busy = true;
        try {
          const id = (await post(form.dataset.importBegin)).text.trim();
          for (let offset = 0; offset < file.size; offset += pieceBytes) {
            this.status = `Uploading ${megabytes(offset)} of ${megabytes(file.size)}`;
            const url = `${form.dataset.importContinue}?id=${encodeURIComponent(id)}&offset=${offset}`;
            await post(url, file.slice(offset, offset + pieceBytes));
            this.sent = Math.min(offset + pieceBytes, file.size);
          }
          // the import itself is one step the server takes whole; the site waits
          // for it, and so does this bar
          this.$refs.bar.removeAttribute("value");
          this.status = "Making the space. The server answers nothing else until it is done.";
          const { response } = await post(`${form.dataset.importFinish}?id=${encodeURIComponent(id)}`);
          window.location.href = response.headers.get("Koya-Redirect") || "/";
        } catch (e) {
          this.error = e.message || "The import could not be sent.";
          this.busy = false;
        }
      },
    };
  };
}
