{
  const koya = (window.koya ||= {});

  const fetchWhole = window.fetch;
  window.fetch = async (input, init) => {
    const response = await fetchWhole(input, init);
    if (!init?.headers?.["nm-request"]) return response;
    return new Response(await response.arrayBuffer(), {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
    });
  };

  const changed = (el) => setTimeout(() => el.dispatchEvent(new Event("change", { bubbles: true })));

  const pickMedia = (onpick) =>
    document.getElementById("media-picker")?.dispatchEvent(new CustomEvent("openpicker", { detail: onpick }));

  koya.form = (form) => {
    const data = new FormData(form);
    const fields = {};
    for (const name of new Set(data.keys())) {
      const values = data.getAll(name);
      fields[name] = values.length > 1 ? values : values[0];
    }
    return fields;
  };

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

  koya.refused = (event, draw) => {
    const error = event.detail.err;
    if (error.name === "AbortError") return;
    const message = error instanceof TypeError ? "" : error.message;
    const url = dataUrl(message.slice(message.indexOf(": ") + 2));
    if (url) draw(url);
  };

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

  koya.reveal = (event) => {
    const el = event.target;
    const observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      el.dispatchEvent(new CustomEvent("revealed"));
    });
    observer.observe(el);
  };

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

  {
    const IDEOGRAPHIC_SPACE = "　";
    const PLACEHOLDER = "";

    const protect = (html) => {
      const template = document.createElement("template");
      template.innerHTML = html;
      const walker = document.createTreeWalker(template.content, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        node.data = node.data.replaceAll(IDEOGRAPHIC_SPACE, PLACEHOLDER);
      }
      return template.innerHTML;
    };
    const restore = (html) =>
      html
        .replace(/(^|[^;&])&nbsp;(?!&nbsp;)/g, "$1 ")
        .replace(/&nbsp;(?=\S)(?!&nbsp;)/g, " ");
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
              image: () =>
                pickMedia((item) => {
                  const range = quill.getSelection(true);
                  quill.insertEmbed(range.index, "image", item.url, "user");
                  quill.setSelection(range.index + 1);
                }),
            },
          },
        },
      });
      const settle = () => {
        let index = 0;
        for (const op of quill.getContents().ops) {
          if (typeof op.insert !== "string") {
            index += 1;
            continue;
          }
          for (let at = op.insert.indexOf(PLACEHOLDER); at !== -1; at = op.insert.indexOf(PLACEHOLDER, at + 1)) {
            quill.updateContents(
              [{ retain: index + at }, { delete: 1 }, { insert: IDEOGRAPHIC_SPACE, attributes: op.attributes }],
              "silent",
            );
          }
          index += op.insert.length;
        }
      };
      if (input.value) {
        quill.clipboard.dangerouslyPasteHTML(protect(input.value));
        settle();
      }
      const opened = tidy(restore(quill.getSemanticHTML()));
      const original = input.value;
      const write = () => {
        const html = tidy(restore(quill.getSemanticHTML()));
        input.value = html === opened ? original : html;
        input.dispatchEvent(new Event("input", { bubbles: true }));
      };
      quill.on("text-change", write);
      const paste = quill.clipboard.onPaste.bind(quill.clipboard);
      quill.clipboard.onPaste = (range, { text, html }) => {
        paste(range, { text, html: html && protect(html) });
        settle();
        write();
      };
    };
  }

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

  koya.mediaField = (file) => ({
    _id: file.id,
    _url: file.url,
    _alt: file.alt,
    _name: file.name,
    _choose() {
      pickMedia((item) => this._set(item));
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

  koya.qr = (el) => {
    if (typeof QRCode === "undefined") return;
    new QRCode(el, { text: el.dataset.qr, width: 192, height: 192, correctLevel: QRCode.CorrectLevel.M });
  };

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

  koya.phrase = (dialog) => ({
    _typed: "",
    _phrase: dialog.querySelector("[data-confirm-phrase]").dataset.confirmPhrase,
    _reset() {
      this._typed = "";
      if (this.$refs.error) this.$refs.error.textContent = "";
    },
  });

  koya.fitContent = (frame) => {
    const fit = () => {
      const doc = frame.contentDocument;
      if (doc && doc.body) frame.style.height = `${Math.ceil(doc.body.getBoundingClientRect().height)}px`;
    };
    const track = () => {
      const doc = frame.contentDocument;
      if (doc && doc.body) new ResizeObserver(fit).observe(doc.body);
    };
    frame.addEventListener("load", track);
    if (frame.contentDocument && frame.contentDocument.readyState === "complete") track();
  };

  koya.importer = (form) => {
    const pieceBytes = Number(form.dataset.importPieceBytes);
    const post = async (url, body) => {
      const response = await fetch(url, {
        method: "POST",
        body,
        headers: { "Content-Type": "application/octet-stream", "nm-request": "true" },
      });
      const text = await response.text();
      if (!response.ok) throw Object.assign(new Error(textOf(text)), { answer: text });
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
          this.$refs.bar.removeAttribute("value");
          this._status = "Making the space. The server answers nothing else until it is done.";
          this.$fetch(dataUrl(await post(`${form.dataset.importFinish}?id=${encodeURIComponent(id)}`)), "GET");
        } catch (e) {
          if (e.answer && new DOMParser().parseFromString(e.answer, "text/html").getElementById("location")) {
            this.$fetch(dataUrl(e.answer), "GET");
            return;
          }
          this._error = e.message || "The import could not be sent.";
          this._busy = false;
        }
      },
    };
  };
}
