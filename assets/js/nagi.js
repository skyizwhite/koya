// Nagi v0.1.0
// Forked from Nomini (https://github.com/nonnorm/nomini)
// Inspired by aidenybai/dababy
// Copyright (c) 2025 nonnorm
// Copyright (c) 2026 Akira Tempaku
// Licensed under the MIT License.

(() => {
    // Utility functions
    const dispatch = (el, name, opts) => {
        opts = { bubbles: true, detail: {}, ...opts };
        return el.dispatchEvent(new CustomEvent(name, opts));
    };

    const failed = Symbol();

    const isData = (obj, prop) => {
        for (let o = obj; o; o = Object.getPrototypeOf(o)) {
            const found = Object.getOwnPropertyDescriptor(o, prop);
            if (found) return "value" in found;
        }
        return true;
    };

    const evaluate = (expression, data, thisArg) => {
        try {
            return new Function("__data", `with(__data) {return (${expression}\n)}`).call(thisArg, data);
        } catch (err) {
            console.error("[Nagi] failed to evaluate:", expression, "\n", err);
            return failed;
        }
    };

    const queryAttr = (el, selector) => {
        const elMatch = el.matches(selector) ? [el] : [];
        return [...elMatch, ...el.querySelectorAll(selector)].filter(
            (val) => !val.closest("[n-ignore]"),
        );
    };

    const pageWriting = new Set();
    const getClosestProxy = (el) => {
        for (; el; el = el.parentElement) if (el.nagiProxy) return el.nagiProxy;
        return helpers(0, pageWriting);
    };

    const runWithEl = (el, fn, bind = null, handler = null) => {
        const prev = [currentEl, currentBind, currentHandler];
        currentEl = el;
        currentBind = bind;
        currentHandler = handler;
        try {
            return fn();
        } finally {
            [currentEl, currentBind, currentHandler] = prev;
        }
    };

    const unlink = (run) => {
        run.deps.forEach((deps) => deps.delete(run));
        run.deps.clear();
        run.children.forEach(kill);
        run.children = [];
    };

    const kill = (run) => {
        run.gone = true;
        run.owner?.nagiRuns.delete(run);
        unlink(run);
    };

    let runCount = 0;

    const watch = (fn, el = currentEl, owner = el) => {
        const run = () => {
            if (run.gone || run === currentBind) return;
            if (run.active) return (run.dirty = true);
            run.active = true;
            try {
                for (let i = 0; i < 100 && !run.gone && (i === 0 || run.dirty); i++) {
                    run.dirty = false;
                    unlink(run);
                    try {
                        runWithEl(el, fn, run);
                    } catch (err) {
                        console.error("[Nagi] failed to run:", fn, "\n", err);
                    }
                }
                if (run.gone) unlink(run);
                else if (run.dirty) console.error("[Nagi] stopped running after 100 times:", fn);
            } finally {
                run.active = false;
            }
        };
        run.owner = owner;
        run.deps = new Set();
        run.children = [];
        owner && (owner.nagiRuns ||= new Set()).add(run);
        run.key = currentBind ? `${currentBind.key}.${currentBind.children.length}` : `run${++runCount}`;
        currentBind?.children.push(run);
        run();
        return run;
    };

    // Important reactivity stuff
    let currentBind = null;
    let currentEl = null;
    let currentHandler = null;

    // Helpers that are included with every data object
    const helpers = (pending = 0, writing = new Set(), controllers = new Set()) => ({
        // --- BEGIN ref
        $refs: {},
        // --- END ref
        // --- BEGIN fetch
        $fetching: false,
        _nagiAbort: new AbortController(),
        $get(url, data, options) {
            this.$fetch(url, "GET", data, options);
        },
        $post(url, data, options) {
            this.$fetch(url, "POST", data, options);
        },
        $abort() {
            controllers.forEach((controller) => controller.abort());
            this._nagiAbort.abort();
            this._nagiAbort = new AbortController();
        },
        $fetch(url, method, data, options) {
            options ??= {};
            const el = currentEl ?? this._nagiEl;
            const controller = new AbortController();
            const { signal } = controller;
            method = (method || "GET").toUpperCase();
            url = String(url);
            const reading = /^(GET|HEAD|OPTIONS)$/.test(method);
            const report = (name, detail, cancelable = false) =>
                dispatch(el?.isConnected ? el : document, name, { detail, cancelable });
            let write;

            const opts = runWithEl(el, () => {
                let body;
                const isEvent = typeof data?.preventDefault === "function";
                const isBlob = (value) => typeof value?.arrayBuffer === "function";
                if (typeof data === "string") body = new URLSearchParams(data);
                else if (typeof data?.append === "function" && typeof data[Symbol.iterator] === "function") body = data;
                else if (isEvent || data?.nodeType === 1) {
                    const node = isEvent ? data.target : data;
                    const button = node?.closest?.("button, input[type=submit], input[type=image]");
                    const form = node?.tagName === "FORM" ? node : (button ?? node)?.form ?? node?.closest?.("form");
                    const submitter = isEvent && data.submitter;
                    if (form) {
                        body = new FormData(form, submitter || undefined);
                        if (button?.name && button !== submitter && button.form === form) body.append(button.name, button.value);
                    } else {
                        console.warn("[Nagi] no form to send for:", data);
                        body = new URLSearchParams();
                    }
                } else {
                    const pairs = Object.entries(data ?? {}).flatMap(([key, value]) =>
                        [value]
                            .flat()
                            .flatMap((item) => (typeof item?.item === "function" && typeof item[Symbol.iterator] === "function" ? [...item] : [item]))
                            .filter((item) => item != null)
                            .filter((item) => {
                                if (item !== Object(item) || isBlob(item) || !String(item).startsWith("[object ")) return true;
                                console.warn("[Nagi] cannot send:", key, item);
                            })
                            .map((item) => [key, isBlob(item) ? item : String(item)]),
                    );
                    body = pairs.some(([, value]) => isBlob(value)) ? new FormData() : new URLSearchParams();
                    pairs.forEach(([key, value]) => body.append(key, value));
                }

                const entries = [...body];
                const opts = { headers: { "n-request": true }, method, signal };
                const reads = /^(GET|HEAD|DELETE)$/.test(method);
                if (reads && entries.some(([, value]) => typeof value !== "string"))
                    console.warn("[Nagi] files are not sent with", method, url);
                const query = String(new URLSearchParams(entries.filter(([, value]) => typeof value === "string")));

                if (!/^(GET|HEAD|DELETE)$/.test(method)) opts.body = body;
                else if (query) {
                    const hashAt = url.includes("#") ? url.indexOf("#") : url.length;
                    const path = url.slice(0, hashAt);
                    const joiner = !path.includes("?") ? "?" : /[?&]$/.test(path) ? "" : "&";
                    url = path + joiner + query + url.slice(hashAt);
                }

                const sent = entries.map(([key, value]) => [
                    key,
                    typeof value === "string" ? value : value.size || value.name ? `\0file${idOf(value)}` : "\0empty",
                ]);
                write = !reading && `${method} ${url} ${opts.body ? new URLSearchParams(sent) : ""}`;
                if (options.dedupe !== false && writing.has(write)) return;

                this._nagiAbort.abort();
                return opts;
            });

            if (!opts) return report("fetchskip", { method, url });

            this._nagiAbort = reading ? controller : new AbortController();
            const deduped = write && options.dedupe !== false;
            if (deduped) writing.add(write);
            controllers.add(controller);
            let timedOut = false;
            const { timeout } = options;
            const timer = Number.isFinite(timeout) && timeout > 0 && setTimeout(() => {
                timedOut = true;
                controller.abort();
                if (this._nagiAbort === controller) this._nagiAbort = new AbortController();
            }, Math.min(timeout, 2147483647));
            pending++;
            this.$fetching = true;

            fetch(url, opts)
                .then(async (res) => {
                    const redirect = res.headers.get("n-redirect");
                    if (redirect) {
                        res.body?.cancel();
                        if (!signal.aborted && report("fetchredirect", { url: redirect }, true)) location.assign(redirect);
                        return;
                    }

                    let buf = "";
                    if (res.body) {
                        const stream = res.body.pipeThrough(new TextDecoderStream()).getReader();
                        while (true) {
                            const { done, value } = await stream.read();
                            if (done) break;
                            buf += value;
                        }
                    }
                    if (signal.aborted) return;

                    let swapped = res.ok;
                    if (!res.ok) {
                        const template = document.createElement("template");
                        template.innerHTML = buf;
                        swapped = [...template.content.children].some((child) => child.id && document.getElementById(child.id));
                    }

                    const replace = res.headers.get("n-replace-url");
                    if (replace) {
                        try {
                            history.replaceState(history.state, "", replace);
                        } catch (err) {
                            console.warn("[Nagi] cannot replace the URL with", replace, err);
                        }
                    }
                    if (swapped) swap(buf);
                    if (!res.ok)
                        throw Object.assign(new Error(`${res.status} ${res.statusText}`), { status: res.status, text: buf, swapped });
                })
                .catch((err) => {
                    if (timedOut) err = new DOMException("The request timed out.", "TimeoutError");
                    else if (signal.aborted) return;
                    report("fetcherr", { err, url, status: err?.status, text: err?.text, swapped: !!err?.swapped });
                })
                .finally(() => {
                    clearTimeout(timer);
                    controllers.delete(controller);
                    if (deduped) writing.delete(write);
                    if (!--pending) this.$fetching = false;
                });
        },
        // --- END fetch
        $dataset() {
            let datasets = {};
            let el = currentEl ?? this._nagiEl;

            while (el?.nodeType === 1) {
                datasets = { ...el.dataset, ...datasets };
                if (el.nagiProxy) break;
                el = el.parentElement;
            }

            return datasets;
        },
        $watch: (fn) => {
            watch(fn);
        },
        $dispatch(evt, detail, opts) {
            dispatch(currentEl ?? this._nagiEl ?? document, evt, { detail, ...opts });
        },
        $debounce(fn, ms, abortable = false) {
            const el = currentEl ?? this._nagiEl;
            const signal = abortable && runWithEl(el, () => this._nagiAbort?.signal);
            const timers = ((el ?? document).nagiTimers ||= new Map());
            const key = currentHandler ?? currentBind?.key ?? fn.nagiSource ?? String(fn);
            clearTimeout(timers.get(key));
            timers.set(key, setTimeout(() => {
                timers.delete(key);
                if (!signal?.aborted) runWithEl(el, fn);
            }, ms));
        },
        // --- BEGIN helpers
        $persist(prop, key) {
            key = key || `_nagiProp-${prop}`;

            const stored = localStorage[key];
            if (stored) this[prop] = JSON.parse(stored);

            watch(() => {
                localStorage[key] = JSON.stringify(this[prop]);
            });
        },
        // --- END helpers
    });

    // --- BEGIN fetch
    const fileIds = new WeakMap();
    let fileCount = 0;
    const idOf = (file) => {
        if (!fileIds.has(file)) fileIds.set(file, ++fileCount);
        return fileIds.get(file);
    };

    const drop = (el) => {
        queryAttr(el, "*").forEach((node) => node.nagiBound && dispatch(node, "destroy", { bubbles: false }));
        // --- BEGIN ref
        queryAttr(el, "[n-ref]").forEach((node) => {
            const refs = getClosestProxy(node).$refs;
            const name = node.getAttribute("n-ref");
            if (refs[name] === node) delete refs[name];
        });
        // --- END ref
        [el, ...el.querySelectorAll("*")].forEach((node) => {
            node.nagiProxy?._nagiAbort.abort();
            node.nagiRuns?.forEach(kill);
            node.nagiCleanup?.forEach((clean) => clean());
            node.nagiTimers?.forEach(clearTimeout);
            node.nagiTimers?.clear();
        });
    };

    const initAll = (nodes) => nodes.forEach((node) => node.nodeType === 1 && init(node));

    const swap = (text) => {
        const template = document.createElement("template");
        template.innerHTML = text;

        for (const fragment of [...template.content.children]) {
            if (!fragment.id) {
                console.warn("[Nagi] Fragment is missing an id: ", fragment);
                continue;
            }

            const strategy = fragment.getAttribute("n-swap") || "outer";
            const target = document.getElementById(fragment.id);

            if (!target) {
                console.warn("[Nagi] Swap target not found: #", fragment.id);
                continue;
            }

            if (!/^(inner|outer|before|after|prepend|append)$/.test(strategy)) {
                console.error("[Nagi] Invalid swap strategy: ", strategy);
                continue;
            }

            const kids = [...fragment.childNodes];

            // --- BEGIN morph
            const settles = (strategy === "outer" ? [fragment] : kids.filter((kid) => kid.nodeType === 1)).map(cssMorph);
            // --- END morph

            if (strategy === "inner") {
                [...target.children].forEach(drop);
                target.replaceChildren(...kids);
                // --- BEGIN template
                if (target.hasAttribute("n-use")) use(target);
                // --- END template
                initAll([...target.childNodes]);
            } else if (strategy === "outer") {
                drop(target);
                target.replaceWith(fragment);
                init(fragment);
            } else {
                target[strategy](...kids);
                initAll(kids);
            }

            // --- BEGIN morph
            settles.forEach((settle) => settle());
            // --- END morph
        }
    };
    // --- END fetch

    // --- BEGIN morph
    const cssMorph = (fragment) => {
        const attributesToSettle = ["style", "class", "height", "width"];
        const read = (el) => attributesToSettle.map((attr) => [attr, el.getAttribute(attr)]);

        const pairs = queryAttr(fragment, "[id]").flatMap((newEl) => {
            const oldEl = document.getElementById(newEl.id);
            return oldEl && oldEl.tagName === newEl.tagName ? [[newEl, read(oldEl)]] : [];
        });

        return () =>
            pairs.forEach(([newEl, oldValues]) => {
                const apply = (values) =>
                    values.forEach(([attr, value]) =>
                        value != null ? newEl.setAttribute(attr, value) : newEl.removeAttribute(attr),
                    );
                const settled = read(newEl);
                apply(oldValues);
                requestAnimationFrame(() => {
                    apply(settled);
                    newEl.nagiRuns?.forEach((run) => attributesToSettle.includes(run.attr) && run());
                });
            });
    };
    // --- END morph

    // --- BEGIN template
    const use = (useEl) => {
        const id = useEl.getAttribute("n-use");
        const template = document.getElementById(id);
        if (template) {
            const templateFrag = template.content.cloneNode(true);
            const slot = templateFrag.querySelector("slot:not([name])");
            if (slot) slot.replaceWith(...useEl.childNodes);
            useEl.replaceChildren(templateFrag);
        } else console.error("[Nagi] No template with id: #", id);
    };
    // --- END template

    const init = (baseEl) => {
        // --- BEGIN template
        queryAttr(baseEl, "[n-use]").forEach(use);
        // --- END template


        // --- BEGIN data
        const reserved = (key, el) => {
            if (!/^(\$|_nagi|__proto__$)/i.test(key)) return false;
            console.error("[Nagi] this name is Nagi's own:", key, el);
            return true;
        };

        const walker = document.createTreeWalker(baseEl, NodeFilter.SHOW_ELEMENT, {
            acceptNode: (node) => (node.hasAttribute("n-ignore") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
        });
        const define = (obj, key, value) =>
            Object.defineProperty(obj, key, { value, writable: true, enumerable: true, configurable: true });

        const baseOf = (dataEl) => {
            const base = dataEl.getAttribute("n-scope")?.trim();
            const made = base ? evaluate(base, {}, dataEl) : {};
            try {
                const builtIn = (obj) => {
                    for (let p = Object.getPrototypeOf(obj); p && Object.getPrototypeOf(p); p = Object.getPrototypeOf(p))
                        if (Object.hasOwn(p, "constructor") && /\[native code\]/.test(Function.prototype.toString.call(p.constructor)))
                            return true;
                };
                if (made !== null && typeof made === "object" && typeof made.then !== "function" && !builtIn(made)) {
                    const descriptors = Object.getOwnPropertyDescriptors(made);
                    Object.values(descriptors).forEach((d) => {
                        d.configurable = true;
                        if ("value" in d) d.writable = true;
                    });
                    return Object.create(Object.getPrototypeOf(made), descriptors);
                }
                if (made !== failed) console.error("[Nagi] n-scope must give an object:", base, dataEl);
            } catch (err) {
                console.error("[Nagi] failed to read the object of n-scope:", base, dataEl, "\n", err);
            }
            return {};
        };

        const makeScope = (dataEl) => {
            if (dataEl.nagiProxy) return;
            const attrs = [...dataEl.attributes];
            if (!attrs.some(({ name }) => /^n-(scope$|let-)/.test(name))) return;

            const rawData = baseOf(dataEl);
            Object.entries({ ...helpers(), _nagiEl: dataEl }).forEach(([key, value]) => define(rawData, key, value));
            Object.entries(dataEl.dataset).forEach(([key, value]) => reserved(key, dataEl) || define(rawData, key, value));

            const trackedDeps = new Map();

            let outer = null;
            for (let node = dataEl.parentElement; node && !outer; node = node.parentElement) outer = node.nagiProxy ?? null;
            const fromOuter = (obj, prop) => !(prop in obj) && !!outer && prop in outer;
            const bound = new WeakMap();
            const bindToOuter = (fn) => {
                if (!bound.has(fn)) bound.set(fn, Object.assign(fn.bind(outer), { nagiSource: fn.nagiSource ?? String(fn) }));
                return bound.get(fn);
            };

            const proxyData = new Proxy(rawData, {
                has(obj, prop) {
                    return prop in obj || (!!outer && prop in outer);
                },
                get(obj, prop, receiver) {
                    if (fromOuter(obj, prop)) {
                        const value = outer[prop];
                        return typeof value === "function" ? bindToOuter(value) : value;
                    }
                    if (currentBind) {
                        let deps = trackedDeps.get(prop);
                        if (!deps) trackedDeps.set(prop, (deps = new Set()));
                        deps.add(currentBind);
                        currentBind.deps.add(deps);
                    }

                    return Reflect.get(obj, prop, receiver);
                },
                set(obj, prop, val, receiver) {
                    if (fromOuter(obj, prop)) return Reflect.set(outer, prop, val);
                    if (prop in obj && val !== Object(val) && isData(obj, prop) && Object.is(obj[prop], val)) return true;
                    if (!Reflect.set(obj, prop, val, receiver)) return false;

                    const deps = trackedDeps.get(prop);

                    deps && [...deps].forEach((run) => run());

                    return true;
                },
            });

            dataEl.nagiProxy = proxyData;
            dataEl.nagiRaw = rawData;

            attrs.forEach(({ name, value }) => {
                const key = name.match(/^n-let-(.+)$/)?.[1];
                if (!key || reserved(key, dataEl)) return;
                const result = value.trim() ? runWithEl(dataEl, () => evaluate(value, proxyData, dataEl)) : undefined;
                if (result === failed) return;
                if (!(key in rawData) || !Reflect.set(proxyData, key, result)) define(rawData, key, result);
            });
        };

        const seen = new Set();
        let dataEl = baseEl.closest("[n-ignore]") ? null : baseEl;
        while (dataEl) {
            const parent = dataEl.parentElement;
            const before = dataEl.previousElementSibling;
            seen.add(dataEl);
            makeScope(dataEl);
            const moved = dataEl.parentElement !== parent || dataEl.previousElementSibling !== before;
            walker.currentNode = dataEl !== baseEl && (moved || !baseEl.contains(dataEl)) ? baseEl : dataEl;
            do dataEl = walker.nextNode();
            while (dataEl && seen.has(dataEl));
        }
        // --- END data

        // --- BEGIN ref
        queryAttr(baseEl, "[n-ref]").forEach((el) => {
            const proxyData = getClosestProxy(el);
            const refName = el.getAttribute("n-ref");

            proxyData.$refs[refName] = el;
        });
        // --- END ref

        // --- BEGIN form
        const formProxy = (el) => {
            const form = el.closest("[n-form]");
            return form && getClosestProxy(form);
        };

        queryAttr(baseEl, "[name]").forEach((inputEl) => {
            const proxyData = formProxy(inputEl);
            if (!proxyData) return;

            let scopeEl = inputEl.closest("[n-form]");
            while (scopeEl && !scopeEl.nagiRaw) scopeEl = scopeEl.parentElement;
            if (scopeEl && !(inputEl.name in scopeEl.nagiRaw))
                Object.defineProperty(scopeEl.nagiRaw, inputEl.name, { writable: true, enumerable: true, configurable: true });

            const inputType = inputEl.type;

            const setVal = () => {
                let res;

                if (inputType === "checkbox")
                    res = inputEl.checked;
                else if (inputType === "radio") {
                    if (!inputEl.checked) {
                        if (!(inputEl.name in proxyData)) proxyData[inputEl.name] = undefined;
                        return;
                    }
                    res = inputEl.value;
                }
                else if (inputType === "file")
                    res = inputEl.files;
                else if (/number|range/.test(inputType))
                    res = +inputEl.value;
                else res = inputEl.value;

                proxyData[inputEl.name] = res;
            };

            setVal();

            inputEl.addEventListener("input", setVal);
            inputEl.addEventListener("change", setVal);
        });

        queryAttr(baseEl, "button, input[type='submit']").forEach((submitEl) => {
            const proxyData = formProxy(submitEl);
            if (proxyData) watch(() => submitEl.disabled = proxyData.$fetching, submitEl);
        });
        // --- END form

        // --- BEGIN bind
        const propOf = (obj, name) => {
            for (let o = obj; o; o = Object.getPrototypeOf(o))
                for (const key of Object.getOwnPropertyNames(o))
                    if (key.toLowerCase() === name) return key;
        };

        const writable = (obj, key) => {
            for (let o = obj; o; o = Object.getPrototypeOf(o)) {
                const found = Object.getOwnPropertyDescriptor(o, key);
                if (found) return !!(found.set || found.writable);
            }
            return true;
        };

        queryAttr(baseEl, "*").forEach((bindEl) => {
            if (bindEl.nagiBound) return;
            const entries = [...bindEl.attributes].flatMap(({ name, value }) => {
                const [, kind, rest] = name.match(/^n-(bind|on)-(.+)$/) || [];
                if (kind === "on") {
                    if (/^\s*(async\s+)?(\([^)]*\)|[\w$]+)\s*=>/.test(value))
                        console.warn("[Nagi] n-on-* runs statements, and this only makes a function:", name, bindEl);
                    return `${JSON.stringify("@" + rest)}: async (e) => {${value}\n}`;
                }
                if (!kind) return [];
                const [first, ...subs] = rest.split(".");
                const sub = subs.join(".");
                const main = first === "class" ? first : propOf(bindEl, first);
                const inner = !sub || /^(class|style|dataset)$/.test(main) ? sub : propOf(bindEl[main], sub);
                if (!main || inner === undefined) {
                    console.error("[Nagi] no such property:", name, bindEl);
                    return [];
                }
                const keyed = sub && /^(class|style|dataset)$/.test(main);
                const camelSub = sub.replace(/-(\w)/g, (_, c) => c.toUpperCase());
                if (main === "style" && sub && !sub.startsWith("--") && !(sub in bindEl.style) && !(camelSub in bindEl.style))
                    console.warn("[Nagi] the style has no such property:", name, bindEl);
                if (!keyed && !(sub ? writable(bindEl[main], inner) : writable(bindEl, main))) {
                    console.error("[Nagi] cannot write:", name, bindEl);
                    return [];
                }
                const key = main + (sub ? "." + inner : "");
                const body = value.replace(/[\s;]+$/, "");
                const empty = !body.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, "").trim();
                return `${JSON.stringify(key)}: () => (${empty ? "undefined" : body}\n)`;
            });

            if (!entries.length) return;
            bindEl.nagiBound = true;

            const proxyData = getClosestProxy(bindEl);
            const props = Object.assign({}, ...entries.map((entry) => evaluate(`{${entry}}`, proxyData, bindEl)));
            const handle = (val, e) => val(e)?.catch?.((err) => console.error("[Nagi] failed to run:", val, "\n", err));

            Object.entries(props).forEach(([key, val]) => {
                if (key.startsWith("@")) {
                    // --- BEGIN events
                    const [eventName, ...mods] = key.slice(1).split(".");
                    const unknown = mods.filter((mod) => !/^(prevent|stop|once|window|debounce\d+)$/.test(mod));
                    if (unknown.length) console.warn("[Nagi] unknown modifiers:", unknown, bindEl);

                    const debounceMod = mods.find((val) => val.startsWith("debounce"));
                    const delay = +debounceMod?.slice(8);

                    const listener = (e) => runWithEl(bindEl, () => {

                        if (mods.includes("prevent")) e.preventDefault();
                        if (mods.includes("stop")) e.stopPropagation();

                        if (delay) proxyData.$debounce(() => handle(val, e), delay);
                        else handle(val, e);
                    }, null, val);

                    const listenOn = mods.includes("window") ? window : bindEl;
                    listenOn.addEventListener(eventName, listener, { once: mods.includes("once") });
                    if (listenOn === window)
                        (bindEl.nagiCleanup ||= []).push(() => window.removeEventListener(eventName, listener));

                    return;
                    // --- END events

                    // If special event handling isn't enabled just do a normal event listener
                    if (key.includes(".")) console.warn("[Nagi] this build does not handle modifiers:", key.slice(1), bindEl);
                    bindEl.addEventListener(key.slice(1).split(".")[0], (e) => runWithEl(bindEl, () => handle(val, e), null, val));
                } else {
                    const [main, ...rest] = key.split(".");
                    const sub = rest.join(".");
                    let added = new Set();
                    const write = (resolvedVal) => {
                        if (main === "class" && !sub) {
                            const v = resolvedVal;
                            const next = new Set(
                                typeof v === "string" ? v.split(/\s+/).filter(Boolean)
                                    : Array.isArray(v) ? v.filter(Boolean).flatMap((item) => String(item).split(/\s+/)).filter(Boolean)
                                    : Object.keys(v ?? {}).filter((name) => v[name]).flatMap((name) => name.split(/\s+/)).filter(Boolean),
                            );
                            const mine = new Set();
                            added.forEach((name) => next.has(name) || bindEl.classList.remove(name));
                            next.forEach((name) => {
                                if (added.has(name) || !bindEl.classList.contains(name)) mine.add(name);
                                bindEl.classList.add(name);
                            });
                            added = mine;
                        } else if (sub) {
                            const unset = resolvedVal == null || resolvedVal === false;
                            if (main === "class") bindEl.classList.toggle(sub, !!resolvedVal);
                            else if (main === "style")
                                unset ? bindEl.style.removeProperty(sub) : bindEl.style.setProperty(sub, resolvedVal);
                            else if (main === "dataset")
                                unset ? bindEl.removeAttribute("data-" + sub) : bindEl.setAttribute("data-" + sub, resolvedVal);
                            else bindEl[main][sub] = resolvedVal;
                        } else bindEl[main] = resolvedVal;
                    };

                    let latest = 0;
                    const run = watch(() => {
                        const value = val();
                        const mine = ++latest;
                        if (typeof value?.then === "function")
                            value
                                .then((resolved) => mine === latest && !run?.gone && write(resolved))
                                .catch((err) => console.error("[Nagi] failed to run:", val, "\n", err));
                        else write(value);
                    }, bindEl);
                    run.attr = /^class(name|list)$/i.test(main) ? "class" : main;
                }
            });

            dispatch(bindEl, "init", { bubbles: false });
        });
        // --- END bind
    };

    document.addEventListener("DOMContentLoaded", () => init(document.body));
})();
