{
  const koya = (window.koya ||= {});

  const changed = (el) => el.dispatchEvent(new Event("change", { bubbles: true }));

  const openPicker = (id, detail) => document.getElementById(id)?.dispatchEvent(new CustomEvent("openpicker", { detail }));

  koya.follow = (event) => {
    if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return false;
    event.preventDefault();
    return true;
  };

  const textOf = (html) => new DOMParser().parseFromString(html, "text/html").body.textContent.trim();

  const unreachable = () => document.getElementById("toast-failed")?.content.textContent.trim() ?? "";

  const drawToast = (templateId, message) => {
    const toast = document.getElementById("toast");
    const template = document.getElementById(templateId);
    if (!toast || !template) return;
    const alert = template.content.firstElementChild.cloneNode(true);
    if (message) alert.textContent = message;
    const drawn = toast.cloneNode(false);
    drawn.append(alert);
    toast.replaceWith(drawn);
  };

  document.addEventListener("fetcherr", (event) => {
    if (event.detail.swapped) return;
    drawToast("toast-failed", textOf(event.detail.text ?? ""));
  });

  let leaving = false;
  koya.leave = () => {
    leaving = true;
  };
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) leaving = false;
  });

  koya.search = () => ({
    asked: null,
    ask(url, form, always) {
      const data = new URLSearchParams(new FormData(form));
      const asked = `${url}?${data}`;
      if (!always && asked === this.asked) return;
      this.asked = asked;
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

  koya.uploader = (form) => {
    const limit = Number(form.dataset.uploadLimit);
    const send = async (file) => {
      const body = new FormData();
      body.append("file", file);
      try {
        const response = await fetch(form.dataset.uploadUrl, { method: "POST", body, headers: { "n-request": "true" } });
        return { status: response.status, reason: textOf(await response.text()) };
      } catch {
        return { status: 0, reason: unreachable() };
      }
    };
    const refusedFile = (status) => status === 413 || status === 422;
    return {
      busy: false,
      sent: 0,
      total: 0,
      status: "",
      error: "",
      async upload(input) {
        if (input.type !== "file" || input.files.length === 0 || this.busy) return;
        const files = Array.from(input.files);
        input.value = "";
        this.busy = true;
        this.error = "";
        this.sent = 0;
        this.total = files.length;
        this.$refs.dialog.showModal();
        let done = 0;
        const refused = [];
        let stopped = null;
        for (const [i, file] of files.entries()) {
          this.status = `Uploading ${file.name} (${i + 1} of ${files.length})`;
          if (file.size > limit) refused.push(`${file.name}: ${form.dataset.uploadLimitMessage}`);
          else {
            const answer = await send(file);
            if (answer.status >= 200 && answer.status < 300) done++;
            else if (refusedFile(answer.status)) refused.push(`${file.name}: ${answer.reason}`);
            else {
              stopped = `The rest were not sent: ${answer.reason || `the upload was refused (${answer.status})`}`;
              break;
            }
          }
          this.sent = i + 1;
        }
        this.busy = false;
        const message = `Uploaded ${done} of ${files.length} file${files.length === 1 ? "" : "s"}.`;
        if (refused.length || stopped) {
          const reasons = [...refused, ...(stopped ? [stopped] : [])];
          this.status = message;
          this.error = reasons.join("\n");
          if (!this.$refs.dialog.open) drawToast("toast-failed", `${message} ${reasons.join(" ")}`);
        } else {
          this.$refs.dialog.close();
          drawToast("toast-done", `Uploaded ${done} file${done === 1 ? "" : "s"}.`);
        }
        const search = form.dataset.uploadSearch && document.getElementById(form.dataset.uploadSearch);
        this.$get(form.dataset.uploadRedraw, search || undefined);
      },
    };
  };

  {
    const IDEOGRAPHIC_SPACE = "　";
    const PLACEHOLDER = "";

    const protect = (html) => {
      const doc = new DOMParser().parseFromString(html, "text/html");
      const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        node.data = node.data.replaceAll(IDEOGRAPHIC_SPACE, PLACEHOLDER);
      }
      for (const el of doc.body.querySelectorAll("pre, textarea, listing")) {
        if (el.firstChild?.nodeType === Node.TEXT_NODE && el.firstChild.data.startsWith("\n")) {
          el.firstChild.data = `\n${el.firstChild.data}`;
        }
      }
      return doc.documentElement.outerHTML;
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
        placeholder: "Write here",
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
                openPicker("media-picker", {
                  onpick: (item) => {
                    const range = quill.getSelection(true);
                    quill.insertEmbed(range.index, "image", item.url, "user");
                    quill.setSelection(range.index + 1);
                  },
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
        quill.setContents(quill.clipboard.convert({ html: protect(input.value), text: "" }));
        settle();
      }
      const empty = () =>
        quill.getContents().ops.every((op) => typeof op.insert === "string") && quill.getText().trim() === "";
      const html = () => (empty() ? "" : tidy(restore(quill.getSemanticHTML())));
      const opened = html();
      const original = input.value;
      const write = () => {
        const now = html();
        input.value = now === opened ? original : now;
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

  koya.references = (el, model, many) => {
    const list = el.querySelector("[data-reference-list]");
    list.addEventListener("click", (event) => {
      const button = event.target.closest?.("[data-action]");
      if (!button) return;
      if (button.dataset.action === "remove") koya.removeRow(button);
      else koya.moveRow(button, button.dataset.action === "up" ? -1 : 1);
    });
    return {
      choose() {
        openPicker("reference-picker", {
          many,
          held: many ? Array.from(list.querySelectorAll("input"), (input) => input.value) : [],
          query: { model, many },
          onpick: (picked) => {
            const cards = many ? picked : [picked];
            if (!cards.length) return;
            for (const card of cards) card.querySelector("input").name = list.id;
            if (many) list.append(...cards);
            else list.replaceChildren(...cards);
            changed(list);
          },
        });
      },
    };
  };

  koya.customField = (on) => ({
    on,
    add() {
      this.on = true;
      changed(this.$refs.marker);
    },
    remove() {
      this.on = false;
      changed(this.$refs.marker);
    },
  });

  koya.repeater = (url) => ({
    add(select) {
      if (select.value) this.$get(url, { kind: select.value });
    },
  });

  koya.rowAdded = (row) => changed(row);

  const rowOf = (el) => el.closest("[data-row]");

  koya.moveRow = (button, step) => {
    const row = rowOf(button);
    const other = step < 0 ? row.previousElementSibling : row.nextElementSibling;
    if (!other) return;
    if (step < 0) other.before(row);
    else other.after(row);
    button.focus();
    changed(row);
  };

  koya.removeRow = (button) => {
    const row = rowOf(button);
    const list = row.parentElement;
    row.remove();
    changed(list);
  };

  koya.sortable = (list) => {
    let dragged = null;
    list.addEventListener("pointerdown", (event) => {
      const handle = event.target.closest?.("[data-drag-handle]");
      if (handle) rowOf(handle).draggable = true;
    });
    document.addEventListener("pointerup", () => {
      if (dragged) return;
      for (const row of list.querySelectorAll(":scope > [draggable='true']")) row.draggable = false;
    });
    list.addEventListener("dragstart", (event) => {
      const row = event.target.closest?.("[data-row]");
      if (!row || !row.draggable || row.parentElement !== list) return;
      dragged = row;
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", "");
      dragged.classList.add("opacity-50");
    });
    const across = list.dataset.sortAxis === "x";
    list.addEventListener("dragover", (event) => {
      if (!dragged) return;
      const over = event.target.closest?.("[data-row]");
      if (!over || over.parentElement !== list) {
        if (event.target !== list) return;
        event.preventDefault();
        const last = list.lastElementChild;
        const box = last?.getBoundingClientRect();
        const beyond = box && (across ? event.clientX > box.right && event.clientY > box.top : event.clientY > box.bottom);
        if (beyond && last !== dragged) list.append(dragged);
        return;
      }
      event.preventDefault();
      if (over === dragged) return;
      const box = over.getBoundingClientRect();
      const before = across ? event.clientX < box.left + box.width / 2 : event.clientY < box.top + box.height / 2;
      if (before) over.before(dragged);
      else over.after(dragged);
    });
    list.addEventListener("dragend", () => {
      if (!dragged) return;
      dragged.classList.remove("opacity-50");
      dragged.draggable = false;
      changed(dragged);
      dragged = null;
    });
  };

  const picker = (dialog, url, itemOf) => {
    const items = new Map();
    return {
      onpick: null,
      many: false,
      held: [],
      chosen: [],
      open(detail) {
        this.many = Boolean(detail.many);
        this.onpick = detail.onpick;
        this.held = detail.held ?? [];
        this.chosen = [];
        items.clear();
        this.$get(url, detail.query ?? {});
        dialog.showModal();
      },
      close() {
        this.onpick = null;
        this.chosen = [];
        items.clear();
        dialog.close();
      },
      has(id) {
        return this.chosen.includes(id);
      },
      taken(id) {
        return this.held.includes(id);
      },
      pick(button) {
        const id = button.dataset.pickId;
        if (this.many) {
          if (this.has(id)) {
            this.chosen = this.chosen.filter((chosen) => chosen !== id);
            items.delete(id);
          } else {
            items.set(id, itemOf(button));
            this.chosen = [...this.chosen, id];
          }
          return;
        }
        const onpick = this.onpick;
        const item = itemOf(button);
        this.close();
        onpick?.(item);
      },
      done() {
        const onpick = this.onpick;
        const chosen = this.chosen.map((id) => items.get(id));
        this.close();
        onpick?.(chosen);
      },
    };
  };

  koya.mediaPicker = (dialog, url) =>
    picker(dialog, url, (button) => ({
      id: button.dataset.pickId,
      url: button.dataset.pickUrl,
      alt: button.dataset.pickAlt,
      name: button.dataset.pickName,
    }));

  koya.referencePicker = (dialog, url) =>
    picker(dialog, url, (button) => button.nextElementSibling.content.firstElementChild.cloneNode(true));

  koya.mediaList = (el) => {
    const list = el.querySelector("[data-media-list]");
    const template = el.querySelector("template");
    const add = (item) => {
      if ([...list.querySelectorAll("input")].some((input) => input.value === item.id)) return;
      const entry = template.content.firstElementChild.cloneNode(true);
      const img = entry.querySelector("img");
      img.src = item.url;
      img.alt = item.alt;
      entry.querySelector("[data-media-name]").textContent = item.name;
      entry.querySelector("[data-media-name]").title = item.name;
      entry.querySelector("input").value = item.id;
      list.append(entry);
    };
    list.addEventListener("click", (event) => {
      const button = event.target.closest?.("[data-action]");
      if (!button) return;
      if (button.dataset.action === "remove") koya.removeRow(button);
      else koya.moveRow(button, button.dataset.action === "left" ? -1 : 1);
    });
    return {
      add() {
        openPicker("media-picker", {
          many: true,
          onpick: (items) => {
            items.forEach(add);
            if (items.length) changed(list);
          },
        });
      },
    };
  };

  koya.mediaField = (file) => ({
    id: file.id,
    url: file.url,
    alt: file.alt,
    name: file.name,
    choose() {
      openPicker("media-picker", { onpick: (item) => this.set(item) });
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

  koya.qr = (el) => {
    if (typeof QRCode === "undefined") return;
    new QRCode(el, { text: el.dataset.qr, width: 192, height: 192, correctLevel: QRCode.CorrectLevel.M });
  };

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

  const unsavedEdits = new Map();
  const forgetGone = () => unsavedEdits.forEach((_, editor) => editor.isConnected || unsavedEdits.delete(editor));
  const anyUnsaved = () => {
    forgetGone();
    return [...unsavedEdits.values()].some((unsaved) => unsaved());
  };

  window.addEventListener("beforeunload", (event) => {
    if (!leaving && anyUnsaved()) event.preventDefault();
  });

  koya.mayLeave = () =>
    !anyUnsaved() ||
    window.confirm("This page has changes that are not saved. Leave it anyway?");

  koya.closeDialogs = () => {
    for (const dialog of document.querySelectorAll("dialog[open]")) dialog.close();
  };

  koya.editor = (el, unsaved) => {
    const form = el.querySelector("#editor-form");
    const snapshot = () => new URLSearchParams(new FormData(form)).toString();
    const drawn = snapshot();
    let current = drawn;
    forgetGone();
    unsavedEdits.set(el, () => unsaved || current !== drawn);
    return {
      current: drawn,
      unfolded: false,
      track() {
        this.current = snapshot();
        current = this.current;
      },
      unchanged() {
        return !unsaved && this.current === drawn;
      },
    };
  };

  koya.phrase = (dialog) => ({
    typed: "",
    phrase: dialog.querySelector("[data-confirm-phrase]").dataset.confirmPhrase,
    reset() {
      this.typed = "";
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
        headers: { "Content-Type": "application/octet-stream", "n-request": "true" },
      });
      const text = await response.text();
      const redirect = response.headers.get("n-redirect");
      if (!response.ok) throw Object.assign(new Error(textOf(text)), { answer: text, redirect });
      return { text, redirect };
    };
    const megabytes = (n) => `${(n / 1048576).toFixed(1)} MB`;
    return {
      busy: false,
      sent: 0,
      total: 0,
      status: "",
      error: "",
      login: "",
      async start() {
        const file = this.$refs.file.files[0];
        if (!file || this.busy) return;
        this.error = "";
        this.login = "";
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
          this.$refs.bar.removeAttribute("value");
          this.status = "Making the space. The server answers nothing else until it is done.";
          const { redirect } = await post(`${form.dataset.importFinish}?id=${encodeURIComponent(id)}`);
          if (redirect) window.location.assign(redirect);
        } catch (e) {
          if (e.redirect) {
            window.location.assign(e.redirect);
            return;
          }
          const answer = e.answer && new DOMParser().parseFromString(e.answer, "text/html");
          const login = answer && answer.querySelector("#toast a[href]");
          if (login) {
            this.error = "The session has ended.";
            this.login = login.getAttribute("href");
            this.busy = false;
            return;
          }
          this.error = e.message || "The import could not be sent.";
          this.busy = false;
        }
      },
    };
  };
}
