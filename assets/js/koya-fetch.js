// What a page asks of the server goes through here, and what comes back goes to
// Nomini. Nomini's own $fetch sends a scope's data as a query and reads nothing
// but the body, so it cannot send a form as it is (a name given twice, a file),
// follow the server to another page or put the list's state in the URL. These
// do that, and leave the swapping to Nomini.
//
// An element asks with nm-bind, and says what to ask with data-*:
//   data-get / data-post  the action, on the form, the button or the link;
//                         a button's own wins over its form's
//   data-confirm          asked with confirm() before anything is sent
// koya.submit sends a form (on submit, or a button's click), koya.search sends
// it when what it would ask has changed, koya.follow follows a link in place,
// koya.reveal asks once the element comes into view, and koya.upload sends a
// form's files as they are chosen.
//
// The server answers with:
//   Koya-Redirect     go to this page instead
//   Koya-Replace-Url  the page's URL for the state just drawn
//   a body of elements, each drawn again where the element of its id is, as
//   Nomini swaps them (nm-swap says how; outer by default)
// An answer that is refused still has a body to draw: the reason in the toast,
// or in the place the page has for it.
{
  const koya = (window.koya ||= {});

  // Nomini swaps only what its own $fetch read, so an answer is handed to it as
  // a data: URL. Through the body's scope, which holds nothing: $fetch calls every
  // function of the scope it is called on to collect its data, and a scope of
  // koya.js has methods that act. One at a time: a $fetch cancels the one before
  // it on the same scope.
  let feeding = Promise.resolve();
  const feed = (html) => {
    feeding = feeding.then(() => new Promise((resolve) => {
      const scope = document.body.nmProxy;
      scope.$fetch(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`, "GET");
      const wait = () => (scope._nmFetching ? setTimeout(wait, 5) : resolve());
      wait();
    }));
  };

  const textOf = (html) => new DOMParser().parseFromString(html, "text/html").body.textContent.trim();

  // what is not drawn anywhere still shows: in the layout's toast-failed toast
  const failed = (message) => {
    const template = document.getElementById("toast-failed");
    const toast = document.getElementById("toast");
    if (!template || !toast) {
      console.error("[koya]", message);
      return;
    }
    const fresh = template.content.firstElementChild.cloneNode(true);
    if (message) fresh.textContent = message;
    toast.replaceChildren(fresh);
  };

  const drawable = (html) => {
    const template = document.createElement("template");
    template.innerHTML = html;
    return Array.from(template.content.children).some((el) => el.id);
  };

  // a newer GET from the same element makes the one in flight moot: the newest
  // search is the one to show
  const inFlight = new WeakMap();

  koya.request = async (el, method, url, body) => {
    if (method === "GET") {
      inFlight.get(el)?.abort();
      if (body && String(body)) url += (url.includes("?") ? "&" : "?") + body;
      body = undefined;
    }
    const controller = new AbortController();
    inFlight.set(el, controller);
    try {
      const response = await fetch(url, {
        method,
        body,
        headers: { "Koya-Request": "true" },
        signal: controller.signal,
      });
      const redirect = response.headers.get("Koya-Redirect");
      if (redirect) {
        window.location.assign(redirect);
        return;
      }
      const html = await response.text();
      const replace = response.headers.get("Koya-Replace-Url");
      if (replace) history.replaceState(history.state, "", replace);
      if (drawable(html)) feed(html);
      else if (!response.ok) failed(textOf(html) || `${response.status} ${response.statusText}`);
    } catch (error) {
      if (error.name !== "AbortError") failed();
    } finally {
      if (inFlight.get(el) === controller) inFlight.delete(el);
    }
  };

  koya.get = (el, url) => koya.request(el, "GET", url);

  // what a form last asked, so that a search goes only when it would ask
  // something new (a select fires input and change both; a box fires change
  // as it loses focus)
  const asked = new WeakMap();

  const send = (form, submitter, onlyChanged) => {
    const source = submitter && (submitter.dataset.post || submitter.dataset.get) ? submitter : form;
    const method = source.dataset.post ? "POST" : "GET";
    const url = source.dataset.post || source.dataset.get;
    const data = new FormData(form);
    if (submitter?.name) data.append(submitter.name, submitter.value);
    const body = method === "POST" && form.enctype === "multipart/form-data" ? data : new URLSearchParams(data);
    const question = `${method} ${url} ${body}`;
    if (onlyChanged && asked.get(form) === question) return;
    const confirmation = submitter?.dataset.confirm ?? form.dataset.confirm;
    if (confirmation && !window.confirm(confirmation)) return;
    asked.set(form, question);
    koya.request(form, method, url, body);
  };

  koya.submit = (event) => {
    event.preventDefault();
    if (event.type === "submit") send(event.target, event.submitter);
    else send(event.currentTarget.form, event.currentTarget);
  };

  koya.search = (event) => {
    const form = event.target.form;
    if (form) send(form, null, true);
  };

  koya.follow = (event) => {
    if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    koya.get(event.currentTarget, event.currentTarget.dataset.get);
  };

  // the element is a placeholder: it goes, and what it asks for is appended in
  // its place
  koya.reveal = (event) => {
    const el = event.target;
    const observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      const host = el.parentElement;
      el.remove();
      koya.get(host, el.dataset.get);
    });
    observer.observe(el);
  };

  // An upload form's files are checked against its <template data-upload-limit>
  // (ui/media/grid) before they are sent. Too large, the choice is cleared and
  // the template's toast shown.
  koya.upload = (event) => {
    const input = event.target;
    if (input.type !== "file" || input.files.length === 0) return;
    const limit = input.form.querySelector("template[data-upload-limit]");
    const total = Array.from(input.files).reduce((sum, file) => sum + file.size, 0);
    if (limit && total > Number(limit.dataset.uploadLimit)) {
      input.value = "";
      document.getElementById("toast")?.replaceWith(limit.content.cloneNode(true));
      return;
    }
    send(input.form, null);
  };
}
