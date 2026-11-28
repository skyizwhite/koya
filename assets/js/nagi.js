// Nagi v0.6.0
// Forked from Nomini (https://github.com/nonnorm/nomini)
// Inspired by aidenybai/dababy
// Copyright (c) 2025 nonnorm
// Copyright (c) 2026 Akira Tempaku
// Licensed under the MIT License.

(() => {
    // Important reactivity stuff
    let currentBind = null;
    let currentEl = null;
    let currentHandler = null;
    let currentSite = null;

    // Utility functions
    const dispatch = (el, name, opts) => el.dispatchEvent(new CustomEvent(name, { bubbles: true, detail: {}, ...opts }));

    const failed = Symbol();

    const descriptorOf = (obj, prop) => {
        for (let o = obj; o; o = Object.getPrototypeOf(o)) {
            const found = Object.getOwnPropertyDescriptor(o, prop);
            if (found) return found;
        }
    };

    const define = (obj, key, value, enumerable = true) =>
        Object.defineProperty(obj, key, { value, writable: true, enumerable, configurable: true });

    const evaluate = (expression, data, thisArg, el, host = Object.create(null), name) => {
        try {
            return new Function("__data", "$el", "__host", `with(__data) with(__host) {return (${expression}\n)}`).call(thisArg, data, el, host);
        } catch (err) {
            console.error("[Nagi] failed to evaluate:", expression, "\n", err, "in", el ?? "the page", ...(name ? [name] : []));
            return failed;
        }
    };

    const leftAlone = (el) => {
        for (; el; el = el.parentElement) if (el.nagiBroken || el.hasAttribute("n-ignore")) return true;
        return false;
    };

    const queryAttr = (el, selector) => {
        const elMatch = el.matches(selector) ? [el] : [];
        return [...elMatch, ...el.querySelectorAll(selector)].filter((val) => !leftAlone(val));
    };

    const closestScope = (el) => {
        for (; el; el = el.parentElement) if (el.nagiProxy) return el;
    };

    const ownScopes = new WeakMap();
    const getClosestProxy = (el) => {
        const scope = closestScope(el)?.nagiProxy;
        if (scope) return scope;
        if (!ownScopes.has(el)) ownScopes.set(el, reactive(giveHelpers({}, el)));
        return ownScopes.get(el);
    };

    const hostOf = (scope) => currentEl ?? scope._nagiEl;
    const nativeCode = /^function[^{]*\{\s*\[native code\]\s*\}$/;

    const giveHelpers = (raw, el, outer) => {
        Object.entries({ ...helpers(), _nagiEl: el }).forEach(([key, value]) => define(raw, key, value, false));
        Object.defineProperty(raw, "$refs", { value: refsOf(outer), writable: false, enumerable: false, configurable: true });
        return raw;
    };

    const refsOwn = new WeakMap();
    const refKeys = Symbol();
    let heldRefs = null;

    const refsOf = (outer) => {
        const own = {};
        const deps = new Map();
        const track = (name) => {
            if (!currentBind) return;
            const runs = deps.get(name) ?? deps.set(name, new Set()).get(name);
            runs.add(currentBind);
            currentBind.deps.add(runs);
        };
        const runsOf = (names) => new Set(names.flatMap((name) => [...(deps.get(name) ?? [])]));
        const changed = (names) => {
            const cause = names.find((name) => typeof name === "string");
            if (!heldRefs) return runsOf(names).forEach((run) => run(cause));
            const held = heldRefs.get(runsOf) ?? heldRefs.set(runsOf, new Set()).get(runsOf);
            names.forEach((name) => held.add(name));
        };
        const put = (target, name, value) => {
            const had = Object.hasOwn(target, name);
            if (had && target[name] === value) return true;
            Object.defineProperty(target, name, { value, writable: true, enumerable: true, configurable: true });
            changed(had ? [name] : [name, refKeys]);
            return true;
        };
        const outerRefs = () => outer?.$refs;
        const refs = new Proxy(own, {
            get: (target, name) => {
                track(name);
                if (Object.hasOwn(target, name)) return target[name];
                if (outer && name in outerRefs()) return outerRefs()[name];
                return Reflect.get(target, name);
            },
            has: (target, name) => {
                track(name);
                return Object.hasOwn(target, name) || (!!outer && name in outerRefs()) || Reflect.has(target, name);
            },
            set: (target, name, value) => put(target, name, value),
            defineProperty: (target, name, descriptor) => ("value" in descriptor ? put(target, name, descriptor.value) : false),
            deleteProperty: (target, name) => {
                if (!Object.hasOwn(target, name)) return true;
                delete target[name];
                changed([name, refKeys]);
                return true;
            },
            ownKeys: (target) => {
                track(refKeys);
                return [...new Set([...Reflect.ownKeys(target), ...(outer ? Reflect.ownKeys(outerRefs()) : [])])];
            },
            getOwnPropertyDescriptor: (target, name) => {
                track(name);
                if (Object.hasOwn(target, name) || !outer || !(name in outerRefs())) return Reflect.getOwnPropertyDescriptor(target, name);
                return { value: outerRefs()[name], writable: true, enumerable: true, configurable: true };
            },
        });
        refsOwn.set(refs, own);
        return refs;
    };

    const holdRefs = (fn) => {
        if (heldRefs) return fn();
        const held = (heldRefs = new Map());
        try {
            return fn();
        } finally {
            heldRefs = null;
            const runs = new Set();
            held.forEach((names, runsOf) => runsOf([...names]).forEach((run) => runs.add(run)));
            runs.forEach((run) => run());
        }
    };

    let currentStale = false;
    const startsWork = /^\$(watch|persist|debounce|get|post|put|patch|delete|fetch)$/;

    const staleScope = (scope) => {
        const el = scope?._nagiEl;
        return !!el && el.nagiProxy !== scope && ownScopes.get(el) !== scope;
    };

    const atHost = (el, site, fn, stale = false) => {
        const prev = [currentEl, currentSite, currentStale];
        [currentEl, currentSite, currentStale] = [el, site, stale];
        try {
            return fn();
        } finally {
            [currentEl, currentSite, currentStale] = prev;
        }
    };

    const hostHelpers = ["$dispatch", "$dataset", "$get", "$post", "$put", "$patch", "$delete", "$fetch", "$debounce", "$watch", "$persist"];

    const hostLayer = (el, scope, site) => {
        const made = Object.create(null);
        const gen = el.nagiGen;
        return new Proxy(made, {
            has: (_, name) => hostHelpers.includes(name),
            get: (_, name) =>
                hostHelpers.includes(name) ? (made[name] ||= (...args) => atHost(el, name === "$debounce" ? site : null, () => scope[name](...args), startsWork.test(name) && (el.nagiGen !== gen || staleScope(scope)))) : undefined,
            set: (_, name, value) => Reflect.set(scope, name, value),
        });
    };

    const runWithEl = (el, fn, bind = null, handler = null) => {
        const prev = [currentEl, currentBind, currentHandler, currentSite, currentStale];
        [currentEl, currentBind, currentHandler, currentSite, currentStale] = [el, bind, handler, null, false];
        try {
            return fn();
        } finally {
            [currentEl, currentBind, currentHandler, currentSite, currentStale] = prev;
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
    const NativePromise = (async () => {})().constructor;

    const runPlace = (run) => ["in", run.owner ?? "the page", run.label ?? "$watch"];

    const watch = (fn, el = currentEl, owner = el, attr, label) => {
        if (owner?.nagiGone || currentStale) return Object.assign(() => {}, { gone: true, deps: new Set(), children: [] });
        const run = (cause) => {
            if (run.gone || run === currentBind) return;
            if (run.active) {
                run.dirty = true;
                if (cause !== undefined) run.cause = cause;
                return;
            }
            run.active = true;
            try {
                for (let i = 0; i < 100 && !run.gone && (i === 0 || run.dirty); i++) {
                    run.dirty = false;
                    unlink(run);
                    try {
                        const value = runWithEl(el, fn, run);
                        if (value instanceof NativePromise) value.catch((err) => run.gone || console.error("[Nagi] failed to run:", fn, "\n", err, ...runPlace(run)));
                    } catch (err) {
                        console.error("[Nagi] failed to run:", fn, "\n", err, ...runPlace(run));
                    }
                }
                if (run.gone) unlink(run);
                else if (run.dirty) {
                    console.error("[Nagi] stopped running after 100 times:", fn, ...runPlace(run), "kept changing:", run.cause ?? "a name it read");
                    kill(run);
                }
            } finally {
                run.active = false;
            }
        };
        Object.assign(run, { owner, attr, label, deps: new Set(), children: [] });
        owner && (owner.nagiRuns ||= new Set()).add(run);
        run.key = currentBind ? `${currentBind.key}.${currentBind.children.length}` : `run${++runCount}`;
        currentBind?.children.push(run);
        run();
        return run;
    };

    // Helpers that are included with every data object
    const helpers = (pending = 0, writing = new Set(), controllers = new Set(), read = null) => ({
        $fetching: false,
        _nagiAbort: new AbortController(),
        ...Object.fromEntries(
            ["GET", "POST", "PUT", "PATCH", "DELETE"].map((method) => [
                `$${method.toLowerCase()}`,
                function (url, data, options) {
                    this.$fetch(url, method, data, options);
                },
            ]),
        ),
        $abort() {
            controllers.forEach((controller) => controller.abort());
            this._nagiStop();
        },
        _nagiStop() {
            read?.abort();
            this._nagiAbort.abort();
            asNagi(() => (this._nagiAbort = new AbortController()));
        },
        $fetch(url, method, data, options) {
            options ??= {};
            const el = hostOf(this);
            const controller = new AbortController();
            const { signal } = controller;
            method = (method || "GET").toUpperCase();
            url = String(url);
            const reading = /^(GET|HEAD|OPTIONS)$/.test(method);
            const inQuery = /^(GET|HEAD|DELETE)$/.test(method);
            const dedupe = options.dedupe !== false;
            const stale = !!el?.nagiGone || currentStale || staleScope(this);
            const gen = el?.nagiGen;
            const report = (name, detail, cancelable = false) => {
                const wasStale = currentStale;
                currentStale = false;
                try {
                    return dispatch(!stale && el?.isConnected && el.nagiGen === gen ? el : document, name, { detail, cancelable });
                } finally {
                    currentStale = wasStale;
                }
            };
            let write;

            const opts = runWithEl(el, () => {
                const body = bodyOf(data);
                const entries = [...body];
                const opts = { headers: { "n-request": true }, method, signal };
                if (inQuery) {
                    if (entries.some(([, value]) => typeof value !== "string"))
                        console.warn("[Nagi] files are not sent with", method, url);
                    url = withQuery(url, String(new URLSearchParams(entries.filter(([, value]) => typeof value === "string"))));
                } else opts.body = body;

                write = !reading && `${method} ${url} ${opts.body ? new URLSearchParams(sentOf(entries)) : ""}`;
                if (dedupe && writing.has(write)) return;

                if (!stale) {
                    read?.abort();
                    this._nagiAbort.abort();
                }
                return opts;
            });

            if (!opts) {
                report("fetchskip", { method, url });
                return;
            }

            if (!stale) {
                asNagi(() => (this._nagiAbort = new AbortController()));
                if (reading) read = controller;
                if (reading && el) el.nagiRead = controller;
            }
            const deduped = write && dedupe;
            if (deduped) writing.add(write);
            controllers.add(controller);
            let timedOut = false;
            let done = null;
            let received = false;
            const { timeout } = options;
            const timer = Number.isFinite(timeout) && timeout > 0 && setTimeout(() => {
                timedOut = true;
                controller.abort();
            }, Math.min(timeout, 2147483647));
            pending++;
            asNagi(() => (this.$fetching = true));

            fetch(url, opts)
                .then(async (res) => {
                    const redirect = res.headers.get("n-redirect");
                    if (redirect) {
                        res.body?.cancel();
                        if (!signal.aborted && report("fetchredirect", { url: redirect }, true)) location.assign(redirect);
                        return;
                    }

                    const text = await readText(res.body);
                    if (signal.aborted) return;
                    received = true;

                    const swapped = res.ok || fragmentsOf(text).some((child) => child.id && document.getElementById(child.id));

                    const replace = res.headers.get("n-replace-url");
                    if (replace) {
                        try {
                            history.replaceState(history.state, "", replace);
                        } catch (err) {
                            console.warn("[Nagi] cannot replace the URL with", replace, err);
                        }
                    }
                    const applied = swapped ? swap(text) : 0;
                    if (!res.ok)
                        throw Object.assign(new Error(`${res.status} ${res.statusText}`), { status: res.status, text, swapped });
                    done = { url, status: res.status, swapped: applied > 0 };
                })
                .catch((err) => {
                    if (timedOut) err = new DOMException("The request timed out.", "TimeoutError");
                    else if (signal.aborted && !received) return;
                    report("fetcherr", { err, url, status: err?.status, text: err?.text, swapped: !!err?.swapped });
                })
                .finally(() => {
                    clearTimeout(timer);
                    controllers.delete(controller);
                    if (read === controller) read = null;
                    if (el?.nagiRead === controller) el.nagiRead = null;
                    if (deduped) writing.delete(write);
                    if (!--pending) asNagi(() => (this.$fetching = false));
                    if (done) report("fetchdone", done);
                });
        },
        $dataset() {
            let datasets = {};
            for (let el = hostOf(this); el?.nodeType === 1; el = el.parentElement) datasets = { ...el.dataset, ...datasets };
            return datasets;
        },
        $watch(fn) {
            if (!staleScope(this)) watch(fn, this ? hostOf(this) : currentEl);
        },
        $dispatch(evt, detail, opts) {
            dispatch(hostOf(this) ?? document, evt, { detail, ...opts });
        },
        $debounce(fn, ms, options) {
            const { key: given, abortable = false } = typeof options === "object" && options ? options : { abortable: !!options };
            const el = hostOf(this);
            const signal = abortable && runWithEl(el, () => this._nagiAbort?.signal);
            if (el?.nagiGone || currentStale || staleScope(this)) return;
            const timers = ((el ?? document).nagiTimers ||= new Map());
            const site = currentBind?.key ?? currentSite ?? (currentHandler ? idOf(currentHandler) : "");
            const code = fn.nagiSource ?? String(fn);
            const key = given !== undefined ? given : `\0${site} ${nativeCode.test(code) ? "native" : code}`;
            clearTimeout(timers.get(key));
            timers.set(key, setTimeout(() => {
                timers.delete(key);
                if (!signal?.aborted) runWithEl(el, () => ((currentSite = site), fn()));
            }, ms));
        },
        $persist(prop, key) {
            if (hostOf(this)?.nagiGone || currentStale || staleScope(this)) return;
            key = key || `_nagiProp-${prop}`;
            const warned = new Set();
            const warn = (doing, err) => {
                if (!warned.has(doing)) console.warn(`[Nagi] cannot ${doing} the stored value of`, prop, "\n", err);
                warned.add(doing);
            };

            let stored;
            try {
                const text = localStorage.getItem(key);
                if (text) stored = { value: JSON.parse(text) };
            } catch (err) {
                warn("read", err);
            }
            if (stored) this[prop] = stored.value;

            watch(() => {
                const value = this[prop];
                try {
                    const text = JSON.stringify(value);
                    if (text === undefined) localStorage.removeItem(key);
                    else localStorage.setItem(key, text);
                } catch (err) {
                    warn("save", err);
                    try {
                        localStorage.removeItem(key);
                    } catch {}
                }
            }, hostOf(this), hostOf(this), undefined, "$persist");
        },
    });

    const fileIds = new WeakMap();
    let fileCount = 0;
    const idOf = (file) => {
        if (!fileIds.has(file)) fileIds.set(file, ++fileCount);
        return fileIds.get(file);
    };

    const isBlob = (value) => typeof value?.arrayBuffer === "function";
    const isListOf = (value, method) => typeof value?.[method] === "function" && typeof value[Symbol.iterator] === "function";

    const formBody = (data) => {
        const isEvent = typeof data.preventDefault === "function";
        const node = isEvent ? data.target : data;
        const button = node?.closest?.("button, input[type=submit], input[type=image]");
        const form = node?.tagName === "FORM" ? node : (button ?? node)?.form ?? node?.closest?.("form");
        if (!form) {
            console.warn("[Nagi] no form to send for:", data);
            return new URLSearchParams();
        }
        const submitter = isEvent && data.submitter;
        const body = new FormData(form, submitter || undefined);
        if (button?.name && button !== submitter && button.form === form) body.append(button.name, button.value);
        return body;
    };

    const timeOf = (value) => {
        try {
            return Date.prototype.getTime.call(value);
        } catch {}
    };

    const textOf = (item) => {
        if (typeof item === "symbol") return;
        if (item !== Object(item)) return String(item);
        const time = timeOf(item);
        if (time !== undefined) return isNaN(time) ? undefined : new Date(time).toISOString();
        try {
            const text = String(item);
            if (!text.startsWith("[object ")) return text;
        } catch {}
    };

    const objectBody = (data) => {
        const pairs = Object.keys(data ?? {}).flatMap((key) => {
            let value;
            try {
                value = data[key];
            } catch (err) {
                console.warn("[Nagi] cannot send:", key, "\n", err);
                return [];
            }
            return [value]
                .flat()
                .flatMap((item) => (isListOf(item, "item") ? [...item] : [item]))
                .flatMap((item) => {
                    if (item == null || typeof item === "function") return [];
                    if (isBlob(item)) return [[key, item]];
                    const text = textOf(item);
                    if (text !== undefined) return [[key, text]];
                    console.warn("[Nagi] cannot send:", key, item);
                    return [];
                });
        });
        const body = pairs.some(([, value]) => isBlob(value)) ? new FormData() : new URLSearchParams();
        pairs.forEach(([key, value]) => body.append(key, value));
        return body;
    };

    const bodyOf = (data) => {
        if (typeof data === "string") return new URLSearchParams(data);
        if (announcers.has(data)) return objectBody(data);
        if (typeof data?.preventDefault === "function" || data?.nodeType === 1) return formBody(data);
        if (isListOf(data, "append")) return data;
        return objectBody(data);
    };

    const withQuery = (url, query) => {
        if (!query) return url;
        const hashAt = url.includes("#") ? url.indexOf("#") : url.length;
        const path = url.slice(0, hashAt);
        const joiner = !path.includes("?") ? "?" : /[?&]$/.test(path) ? "" : "&";
        return path + joiner + query + url.slice(hashAt);
    };

    const sentOf = (entries) =>
        entries.map(([key, value]) => [
            key,
            typeof value === "string" ? value : value.size || value.name ? `\0file${idOf(value)}` : "\0empty",
        ]);

    const readText = async (body) => {
        let text = "";
        if (!body) return text;
        const stream = body.pipeThrough(new TextDecoderStream()).getReader();
        for (let chunk; !(chunk = await stream.read()).done; ) text += chunk.value;
        return text;
    };

    const fragmentsOf = (text) => {
        const template = document.createElement("template");
        template.innerHTML = text;
        return [...template.content.children];
    };

    const drop = (el) => {
        droppedNow?.push(el);
        [el, ...el.querySelectorAll("*")].forEach((node) => node.nagiBound && !node.nagiInitDue && dispatch(node, "destroy", { bubbles: false }));
        [el, ...el.querySelectorAll("*")].forEach((node) => {
            (node.nagiProxy ?? ownScopes.get(node))?._nagiStop();
            node.nagiRead?.abort();
            node.nagiRuns?.forEach(kill);
            node.nagiCleanup?.forEach((clean) => clean());
            node.nagiCleanup = null;
            node.nagiTimers?.forEach(clearTimeout);
            node.nagiTimers?.clear();
            node.nagiBound = node.nagiField = node.nagiInitDue = false;
            node.nagiGone = true;
            node.nagiGen = (node.nagiGen ?? 0) + 1;
            node.nagiProxy = node.nagiRaw = node.nagiFields = node.nagiOwnClasses = null;
            node.nagiBroken = false;
            ownScopes.delete(node);
        });
        [el, ...el.querySelectorAll("[n-ref]")].forEach((node) => {
            const scopeEl = node.nagiRefScope;
            const refs = scopeEl?.nagiRaw?.$refs;
            const name = node.getAttribute("n-ref");
            node.nagiRefScope = null;
            if (!refs || refsOwn.get(refs)?.[name] !== node) return;
            const other = queryAttr(scopeEl, "[n-ref]").findLast(
                (n) => n.nagiRefScope === scopeEl && n.getAttribute("n-ref") === name && !el.contains(n),
            );
            if (other) refs[name] = other;
            else delete refs[name];
        });
    };

    const initAll = (nodes) => initRoots(nodes.filter((node) => node.nodeType === 1));

    const swap = (text) => {
        const moving = [];
        try {
            return holdRefs(() => swapAll(text, moving));
        } finally {
            settle(moving);
        }
    };

    const swapAll = (text, moving) => {
        let applied = 0;
        const refused = (refusedFields = []);
        const checks = (fieldChecks = []);
        const safely = (fn) => {
            try {
                fn();
            } catch (err) {
                console.error("[Nagi] failed to run:", fn, "\n", err);
            }
        };
        try {
            for (const fragment of fragmentsOf(text)) {
                const strategy = fragment.getAttribute("n-swap") || "outer";
                const target = fragment.id && document.getElementById(fragment.id);
                if (!fragment.id) { console.warn("[Nagi] a fragment of the response has no id:", fragment); continue; }
                if (!target) { console.warn(`[Nagi] no element on the page for #${fragment.id}:`, fragment); continue; }
                if (!/^(inner|outer|before|after|prepend|append)$/.test(strategy)) { console.error("[Nagi] invalid n-swap:", strategy, fragment); continue; }

                const kids = [...fragment.childNodes];

                const morphs = strategy === "outer" ? cssMorph([fragment], [target, ...target.querySelectorAll("[id]")])
                    : strategy === "inner" ? cssMorph(kids.filter((kid) => kid.nodeType === 1), [...target.querySelectorAll("[id]")])
                    : [];

                applied++;
                holdInits(() => {
                    if (strategy === "inner") {
                        [...target.children].forEach(drop);
                        target.replaceChildren(...kids);
                        initAll([...target.childNodes]);
                    } else if (strategy === "outer") {
                        drop(target);
                        target.replaceWith(fragment);
                        init(fragment);
                    } else {
                        target[strategy](...kids);
                        initAll(kids);
                    }
                });

                for (const morph of putOld(morphs)) moving.push(morph);
            }
        } finally {
            refusedFields = fieldChecks = null;
            refused.forEach((field) => safely(() => field.isConnected && !field.nagiField && init(field)));
            checks.forEach(safely);
        }
        return applied;
    };

    const attributesToSettle = ["style", "class", "height", "width"];
    const rerunAtSettle = ["style", "classname", "height", "width"];

    const heldClasses = (el) => new Set([...(el.nagiOwnClasses?.values() ?? [])].flatMap((names) => [...names]));

    const hasOwnLook = (el, name) => (el.nagiLook ? el.nagiLook.has(name) : el.classList.contains(name));

    const touchClass = (el, name) => el.nagiLook && (el.nagiTouched ??= new Set()).add(name);

    const settleClass = (el, from, markup) => {
        const old = new Set(classesOf(from ?? "").filter(Boolean));
        const now = new Set(el.classList);
        const touched = el.nagiTouched ?? new Set();
        const names = new Set([...el.nagiLook, ...heldClasses(el)]);
        now.forEach((name) => old.has(name) || touched.has(name) || names.add(name));
        old.forEach((name) => now.has(name) || touched.has(name) || names.delete(name));
        if (names.size) el.setAttribute("class", [...names].join(" "));
        else if (markup == null) el.removeAttribute("class");
        else el.setAttribute("class", "");
    };
    const readSettled = (el) => attributesToSettle.map((attr) => [attr, el.getAttribute(attr)]);

    const cssMorph = (roots, removed) => {
        const byId = new Map();
        removed.forEach((el) => el.id && !byId.has(el.id) && byId.set(el.id, el));
        return roots.flatMap((root) =>
            queryAttr(root, "[id]").flatMap((newEl) => {
                const oldEl = byId.get(newEl.id);
                if (!oldEl || oldEl.tagName !== newEl.tagName) return [];
                newEl.nagiMarkup = newEl.getAttribute("class");
                return [[newEl, readSettled(oldEl)]];
            }),
        );
    };

    const putSettled = (el, values) =>
        values.forEach(([attr, value]) => (value != null ? el.setAttribute(attr, value) : el.removeAttribute(attr)));

    const putOld = (morphs) =>
        morphs.flatMap(([newEl, oldValues]) => {
            const settled = readSettled(newEl);
            if (settled.every(([, value], i) => value === oldValues[i][1])) {
                newEl.nagiMarkup = null;
                return [];
            }
            putSettled(newEl, oldValues);
            const bound = heldClasses(newEl);
            newEl.nagiLook = new Set(classesOf(settled[1][1] ?? "").filter((name) => name && !bound.has(name)));
            return [[newEl, settled, oldValues]];
        });

    const styleOf = (text) => {
        const style = document.createElement("div").style;
        style.cssText = text ?? "";
        return style;
    };

    const namesOf = (style) => Array.from({ length: style.length }, (_, i) => style.item(i));

    const settleAttr = (el, attr, from, to) => {
        const now = el.getAttribute(attr);
        const whole = () => (to != null ? el.setAttribute(attr, to) : el.removeAttribute(attr));
        if (now === from) return whole();
        if (attr === "class") {
            const [before, after] = [new Set(classesOf(from ?? "").filter(Boolean)), new Set(classesOf(to ?? "").filter(Boolean))];
            before.forEach((name) => after.has(name) || el.classList.remove(name));
            after.forEach((name) => before.has(name) || el.classList.add(name));
            if (to == null && !el.classList.length) el.removeAttribute(attr);
        } else if (attr === "style") {
            const [before, after] = [styleOf(from), styleOf(to)];
            if ([before, after, el.style].some((style) => namesOf(style).some((name) => !style.getPropertyValue(name)))) return whole();
            new Set([...namesOf(before), ...namesOf(after)]).forEach((name) => {
                const kept = el.style.getPropertyValue(name) === before.getPropertyValue(name) && el.style.getPropertyPriority(name) === before.getPropertyPriority(name);
                if (!kept) return;
                if (after.getPropertyValue(name)) el.style.setProperty(name, after.getPropertyValue(name), after.getPropertyPriority(name));
                else el.style.removeProperty(name);
            });
            if (to == null && !el.style.length) el.removeAttribute(attr);
        }
    };

    const settle = (moving) => {
        if (!moving.length) return;
        void document.documentElement.offsetWidth;
        requestAnimationFrame(() =>
            moving.forEach(([newEl, settled, oldValues]) => {
                settleClass(newEl, oldValues[1][1], newEl.nagiMarkup);
                newEl.nagiLook = newEl.nagiMarkup = newEl.nagiTouched = null;
                settled.forEach(([attr, value], i) => attr === "class" || settleAttr(newEl, attr, oldValues[i][1], value));
                const reruns = [...(newEl.nagiRuns ?? [])].filter((run) => rerunAtSettle.includes(run.attr));
                reruns.forEach((run) => run());
                if (reruns.some((run) => run.attr === "classname")) heldClasses(newEl).forEach((name) => newEl.classList.add(name));
            }),
        );
    };

    const reserved = (key, el) => {
        if (key !== "__host" && !/^(\$|_nagi|__proto__$)/i.test(key)) return false;
        console.error("[Nagi] this name is Nagi's own:", key, el);
        return true;
    };

    const builtIn = (obj) => {
        for (let p = Object.getPrototypeOf(obj); p && Object.getPrototypeOf(p); p = Object.getPrototypeOf(p))
            if (Object.hasOwn(p, "constructor") && /\[native code\]/.test(Function.prototype.toString.call(p.constructor)))
                return true;
    };

    const boundFns = new WeakMap();
    const boundTo = (outer, fn) => {
        const fns = boundFns.get(outer) ?? boundFns.set(outer, new WeakMap()).get(outer);
        if (!fns.has(fn))
            fns.set(fn, new Proxy(fn, {
                apply: (target, _, args) => Reflect.apply(target, outer, args),
                get: (target, key, receiver) =>
                    key === "nagiSource" ? (target.nagiSource ?? Function.prototype.toString.call(target)) : Reflect.get(target, key, receiver),
            }));
        return fns.get(fn);
    };

    const withOuterNames = (outer, fn) => {
        if (!outer) return fn({});
        let open = true;
        const names = new Proxy(Object.create(null), {
            has: (_, name) => open && typeof name === "string" && name in outer,
            get: (_, name) => {
                if (typeof name === "string" && /^(\$|_nagi)/i.test(name)) return undefined;
                const value = outer[name];
                return typeof value === "function" ? boundTo(outer, value) : value;
            },
            set: (_, name) => (console.error("[Nagi] n-scope cannot assign a name of an outer scope:", name, currentEl), true),
        });
        try {
            return fn(names);
        } finally {
            open = false;
        }
    };

    const baseOf = (dataEl, outer) => {
        const base = dataEl.getAttribute("n-scope")?.trim();
        const made = base ? runWithEl(dataEl, () => withOuterNames(outer, (names) => evaluate(base, names, Object.freeze({}), dataEl, undefined, "n-scope"))) : {};
        try {
            if (made !== null && typeof made === "object" && typeof made.then !== "function" && !builtIn(made)) {
                const descriptors = Object.getOwnPropertyDescriptors(made);
                Object.keys(descriptors).forEach((key) => reserved(key, dataEl) && delete descriptors[key]);
                Object.values(descriptors).forEach((d) => {
                    d.configurable = true;
                    if ("value" in d) d.writable = true;
                });
                return Object.create(Object.getPrototypeOf(made), descriptors);
            }
            if (made !== failed) console.error("[Nagi] n-scope must give an object, so Nagi leaves the element alone:", base, dataEl);
        } catch (err) {
            console.error("[Nagi] failed to read the object of n-scope, so Nagi leaves the element alone:", base, dataEl, "\n", err);
        }
        return failed;
    };

    const announcers = new WeakMap();

    let nagiWriting = false;
    const asNagi = (fn) => {
        const was = nagiWriting;
        nagiWriting = true;
        try {
            return fn();
        } finally {
            nagiWriting = was;
        }
    };

    const reactive = (rawData, outer) => {
        const trackedDeps = new Map();
        const fromOuter = (obj, prop) => !(prop in obj) && !!outer && prop in outer;
        const track = (prop) => {
            if (!currentBind) return;
            const deps = trackedDeps.get(prop) ?? trackedDeps.set(prop, new Set()).get(prop);
            deps.add(currentBind);
            currentBind.deps.add(deps);
        };
        const announce = (prop) => {
            const deps = trackedDeps.get(prop);
            deps && [...deps].forEach((run) => run(prop));
        };

        const proxy = new Proxy(rawData, {
            has(obj, prop) {
                if (prop === "$el" || prop === "__host") return false;
                if (prop in obj) return true;
                track(prop);
                return !!outer && prop in outer;
            },
            get(obj, prop, receiver) {
                track(prop);
                if (fromOuter(obj, prop)) {
                    const value = outer[prop];
                    return typeof value === "function" ? boundTo(outer, value) : value;
                }
                if (currentBind && outer && !(prop in obj)) outer[prop];
                return Reflect.get(obj, prop, receiver);
            },
            set(obj, prop, val, receiver) {
                const byNagi = nagiWriting;
                nagiWriting = false;
                if (!byNagi && typeof prop === "string" && /^(\$|_nagi)/i.test(prop)) {
                    console.error("[Nagi] this name is Nagi's own, so it cannot be assigned:", prop, currentEl ?? obj._nagiEl ?? document);
                    return true;
                }
                if (fromOuter(obj, prop)) return Reflect.set(outer, prop, val);
                const found = descriptorOf(obj, prop);
                if (found && "value" in found && val !== Object(val) && Object.is(obj[prop], val)) return true;
                if (!Reflect.set(obj, prop, val, receiver)) return false;
                announce(prop);
                return true;
            },
        });
        announcers.set(proxy, announce);
        return proxy;
    };

    const announceName = (scopeEl, key) => announcers.get(scopeEl.nagiProxy)(key);

    const giveName = (scopeEl, key, value) => {
        define(scopeEl.nagiRaw, key, value);
        announceName(scopeEl, key);
    };

    const makeScope = (dataEl) => {
        if (dataEl.nagiProxy) return;
        const attrs = [...dataEl.attributes];
        if (!dataEl.hasAttribute("n-scope")) {
            if (attrs.some(({ name }) => name.startsWith("n-let-"))) console.error("[Nagi] n-let-* needs n-scope on its element:", dataEl);
            return;
        }

        const gen = dataEl.nagiGen;
        const outer = closestScope(dataEl.parentElement)?.nagiProxy;
        const base = baseOf(dataEl, outer);
        if (dataEl.nagiGen !== gen || dataEl.nagiProxy) return;
        if (base === failed) {
            dataEl.nagiBroken = true;
            return;
        }
        const rawData = giveHelpers(base, dataEl, outer);
        const proxyData = reactive(rawData, outer);

        dataEl.nagiProxy = proxyData;
        dataEl.nagiRaw = rawData;

        attrs.forEach(({ name, value }) => {
            const key = name.match(/^n-let-(.+)$/)?.[1];
            if (!key || dataEl.nagiGen !== gen || reserved(key, dataEl)) return;
            const result = value.trim() ? runWithEl(dataEl, () => evaluate(value, proxyData, proxyData, dataEl, undefined, name)) : undefined;
            if (result === failed || dataEl.nagiGen !== gen) return;
            try {
                if (!(key in rawData) || !Reflect.set(proxyData, key, result)) giveName(dataEl, key, result);
            } catch (err) {
                console.error("[Nagi] failed to set:", key, dataEl, "\n", err);
            }
        });
    };

    const formScope = (el) => closestScope(el.closest("[n-form]"));

    const isField = (el) => /^(SELECT|TEXTAREA)$/.test(el.tagName) || (el.tagName === "INPUT" && !/^(submit|image|button|reset)$/.test(el.type));

    const formFields = new Set();
    document.addEventListener("reset", (e) =>
        setTimeout(() =>
            formFields.forEach((field) => {
                if (!field.inputEl.isConnected) formFields.delete(field);
                else if (field.inputEl.form === e.target) field.setVal();
            }),
        ), true);

    const hasName = (raw, name) => {
        for (let o = raw; o && o !== Object.prototype; o = Object.getPrototypeOf(o)) if (Object.hasOwn(o, name)) return true;
        return false;
    };

    const sameValue = (had, now) => {
        if (had === now) return true;
        if (Array.isArray(now)) return Array.isArray(had) && had.length === now.length && had.every((item, i) => String(item) === String(now[i]));
        const empty = (v) => v == null || v === "";
        if (empty(had) && empty(now)) return true;
        return now !== Object(now) && had !== Object(had) && String(had) === String(now);
    };

    const liveProps = /^(value|checked|selectedIndex|valueAsNumber|valueAsDate|selected)$/;
    const sameGroup = (a, b) => a === b || (a?.type === "radio" && b?.type === "radio" && !!a.name && a.name === b.name && a.form === b.form);
    const focused = (el) => !!el && sameGroup(document.activeElement, el);

    document.addEventListener(
        "focusout",
        (e) => {
            const left = e.target;
            if (left?.nodeType !== 1 || sameGroup(e.relatedTarget, left)) return;
            const members = left.type === "radio" && left.name ? [...document.querySelectorAll("input[type=radio]")].filter((el) => sameGroup(el, left)) : [left];
            members
                .flatMap((el) => [el, ...el.querySelectorAll("option")])
                .forEach((el) => el.nagiRuns?.forEach((run) => run.nagiRetry?.()));
        },
        true,
    );

    const fieldOf = (inputEl, scopeEl) => {
        const { nagiProxy: proxyData, nagiRaw: rawData } = scopeEl;
        const { name, type, form } = inputEl;
        const shared = type === "radio" || type === "checkbox";
        const nform = inputEl.closest("[n-form]");
        const owned = (scopeEl.nagiFields ||= new Map());
        let group = owned.get(name);
        const fresh = !group;
        group?.members.forEach((el) => el.isConnected || group.members.delete(el));
        if (group?.members.size && !(shared && group.type === type && group.form === form && (type === "radio" || group.nform === nform)))
            return void (refusedFields ? refusedFields.push(inputEl) : console.error("[Nagi] another field of the scope has this name:", name, inputEl));
        if (!group) {
            if (hasName(rawData, name)) return void console.error("[Nagi] this field's name is already a name of the scope:", name, inputEl);
            define(rawData, name, undefined);
            owned.set(name, (group = { members: new Set() }));
        }
        Object.assign(group, { type, form, nform });
        group.members.add(inputEl);

        const read = {
            radio: () => [...group.members].find((el) => el.isConnected && el.form === inputEl.form && el.checked)?.value,
            checkbox: () => {
                const boxes = [...group.members].filter((el) => el.isConnected && el.form === form && el.closest("[n-form]") === nform);
                if (boxes.length > 1) return boxes.filter((el) => el.checked).map((el) => el.value);
                return (boxes[0] ?? inputEl).checked;
            },
            file: () => inputEl.files,
            number: () => (inputEl.value === "" ? undefined : +inputEl.value),
            range: () => +inputEl.value,
            "select-multiple": () => [...inputEl.options].filter((option) => option.selected).map((option) => option.value),
        }[type] ?? (() => inputEl.value);
        const setVal = () => {
            if (group.members.has(inputEl)) proxyData[name] = read();
        };
        const field = { inputEl, setVal };
        inputEl.nagiFieldValue = () => (group.members.has(inputEl) ? read() : undefined);
        inputEl.nagiReread = () => {
            if (!group.members.has(inputEl)) return;
            const now = read();
            if (!sameValue(rawData[name], now)) proxyData[name] = now;
        };

        inputEl.addEventListener("input", setVal);
        inputEl.addEventListener("change", setVal);
        formFields.add(field);
        (inputEl.nagiCleanup ||= []).push(() => {
            inputEl.removeEventListener("input", setVal);
            inputEl.removeEventListener("change", setVal);
            inputEl.nagiReread = inputEl.nagiFieldValue = null;
            group.members.delete(inputEl);
            formFields.delete(field);
            const left = rawData[name];
            const check = () => {
                if (scopeEl.nagiFields?.get(name) !== group || scopeEl.contains(inputEl) || !Object.is(rawData[name], left)) return;
                group.members.forEach((el) => (el.isConnected && scopeEl.contains(el)) || group.members.delete(el));
                const [rest] = group.members;
                proxyData[name] = rest ? rest.nagiFieldValue?.() : undefined;
            };
            if (fieldChecks) fieldChecks.push(check);
            else queueMicrotask(check);
        });
        return () => {
            setVal();
            if (fresh && read() === undefined) announceName(scopeEl, name);
        };
    };

    const propOf = (obj, name) => {
        for (let o = obj; o; o = Object.getPrototypeOf(o))
            for (const key of Object.getOwnPropertyNames(o)) if (key.toLowerCase() === name) return key;
    };

    const writable = (obj, key) => {
        const found = descriptorOf(obj, key);
        return !found || !!(found.set || found.writable);
    };

    const unset = (value) => value == null || value === false;

    const keyedWriters = {
        __proto__: null,
        class: (el, sub, value) => {
            const owned = (el.nagiOwnClasses ??= new Map());
            const mine = value && (owned.get("." + sub)?.has(sub) || !hasOwnLook(el, sub));
            el.classList.toggle(sub, !!value);
            touchClass(el, sub);
            if (!value) el.nagiLook?.delete(sub);
            owned.set("." + sub, new Set(mine ? [sub] : []));
        },
        style: (el, sub, value) => (unset(value) ? el.style.removeProperty(sub) : el.style.setProperty(sub, value)),
        dataset: (el, sub, value) =>
            unset(value) ? el.removeAttribute("data-" + sub) : el.setAttribute("data-" + sub, value),
    };

    const sourceOf = (bindEl, name, value) => {
        const [, kind, rest] = name.match(/^n-(bind|on)-(.+)$/) || [];
        if (kind === "on") {
            if (/^\s*(async\s+)?(\([^)]*\)|[\w$]+)\s*=>/.test(value))
                console.warn("[Nagi] n-on-* runs statements, and this only makes a function:", name, bindEl);
            return `${JSON.stringify("@" + rest)}: async (e) => {${value}\n}`;
        }
        if (!kind) return;

        const [first, ...subs] = rest.split(".");
        const sub = subs.join(".");
        const main = first === "class" ? first : propOf(bindEl, first);
        if (/^outer(html|text)$/i.test(main ?? "")) return console.error("[Nagi] cannot write:", name, bindEl);
        const keyed = !!main && main in keyedWriters;
        const inner = !sub || keyed ? sub : propOf(bindEl[main], sub);
        if (!main || inner === undefined) return console.error("[Nagi] no such property:", name, bindEl);

        const camelSub = sub.replace(/-(\w)/g, (_, c) => c.toUpperCase());
        if (main === "style" && sub && !sub.startsWith("--") && !(sub in bindEl.style) && !(camelSub in bindEl.style))
            console.warn("[Nagi] the style has no such property:", name, bindEl);
        if (!(sub && keyed) && !(sub ? writable(bindEl[main], inner) : writable(bindEl, main)))
            return console.error("[Nagi] cannot write:", name, bindEl);

        const key = main + (sub ? "." + inner : "");
        const body = value.replace(/[\s;]+$/, "");
        const empty = !body.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, "").trim();
        return `${JSON.stringify(key)}: () => (${empty ? "undefined" : body}\n)`;
    };

    const classesOf = (v) =>
        typeof v === "string" ? v.split(/\s+/)
            : Array.isArray(v) ? v.filter(Boolean).flatMap((item) => String(item).split(/\s+/))
            : Object.keys(v ?? {}).filter((name) => v[name]).flatMap((name) => name.split(/\s+/));

    const writerOf = (bindEl, main, sub) => {
        if (sub && main in keyedWriters) return (value) => keyedWriters[main](bindEl, sub, value);
        if (sub) return (value) => (bindEl[main][sub] = value);
        if (main !== "class") {
            let textual = false;
            try {
                textual = /^inner(html|text)$/i.test(main) || (!/^(aria|role$|popover$|crossorigin$)/i.test(main) && typeof bindEl[main] === "string");
            } catch {}
            return (value) => (bindEl[main] = value === undefined && textual ? "" : value);
        }

        let added = new Set();
        const write = (value) => {
            const next = new Set(classesOf(value).filter(Boolean));
            const mine = new Set();
            added.forEach((name) => next.has(name) || (bindEl.classList.remove(name), touchClass(bindEl, name)));
            next.forEach((name) => {
                if (added.has(name) || !hasOwnLook(bindEl, name)) mine.add(name);
                bindEl.classList.add(name);
                touchClass(bindEl, name);
            });
            added = mine;
            (bindEl.nagiOwnClasses ??= new Map()).set(write, mine);
        };
        return write;
    };

    const handle = (val, e, place) => val(e)?.catch?.((err) => console.error("[Nagi] failed to run:", val, "\n", err, ...place));

    const listen = (bindEl, key, val, proxyData, name) => {
        const place = ["in", bindEl, name];
        const [eventName, ...mods] = key.split(".");
        const unknown = mods.filter((mod) => !/^(prevent|stop|once|window|debounce\d+)$/.test(mod));
        if (unknown.length) console.warn("[Nagi] unknown modifiers:", unknown, bindEl);

        const delay = +mods.find((mod) => mod.startsWith("debounce"))?.slice(8);

        const listener = (e) => runWithEl(bindEl, () => {
            if (mods.includes("prevent")) e.preventDefault();
            if (mods.includes("stop")) e.stopPropagation();

            if (delay) proxyData.$debounce(() => runWithEl(bindEl, () => handle(val, e, place), null, val), delay);
            else handle(val, e, place);
        }, null, val);

        const listenOn = mods.includes("window") ? window : bindEl;
        listenOn.addEventListener(eventName, listener, { once: mods.includes("once") });
        (bindEl.nagiCleanup ||= []).push(() => listenOn.removeEventListener(eventName, listener));
    };

    const bindProp = (bindEl, key, val, name) => {
        const [main, ...rest] = key.split(".");
        const writeOnly = writerOf(bindEl, main, rest.join("."));
        const live = !rest.length && liveProps.test(main);
        const fieldOfBind = () => (bindEl.nagiReread ? bindEl : bindEl.closest("select"));
        let skipped = false;
        const write = (value, later) => {
            const field = fieldOfBind();
            if (live && focused(field ?? bindEl)) return void (skipped = true);
            skipped = false;
            const before = field?.nagiFieldValue?.();
            const reread = () => field && !sameValue(before, field.nagiFieldValue?.()) && field.nagiReread?.();
            if (!later) {
                writeOnly(value);
                return reread();
            }
            runWithEl(bindEl, () => writeOnly(value));
            runWithEl(bindEl, reread, run);
        };
        let latest = 0;
        const run = watch(() => {
            const value = val();
            const mine = ++latest;
            if (typeof value?.then !== "function") return write(value);
            new NativePromise((resolve, reject) => value.then(resolve, reject))
                .then((resolved) => mine === latest && !run?.gone && write(resolved, true))
                .catch((err) => mine === latest && !run?.gone && console.error("[Nagi] failed to run:", val, "\n", err, ...runPlace(run)));
        }, bindEl, bindEl, /^class(name|list)$/i.test(main) ? "classname" : main, name);
        run.nagiRetry = () => skipped && run();
    };

    const init = (baseEl) => initRoots([baseEl]);

    const initDepth = new Map();

    const initRoots = (roots) => {
        roots = roots.filter((root) => (initDepth.get(root) ?? 0) < 10 || void console.error("[Nagi] stopped setting up an element its own set-up keeps setting up again:", root));
        if (!roots.length) return;
        roots.forEach((root) => initDepth.set(root, (initDepth.get(root) ?? 0) + 1));
        try {
            return runWithEl(null, () => holdInits(() => setUp(roots)));
        } finally {
            roots.forEach((root) => (initDepth.get(root) > 1 ? initDepth.set(root, initDepth.get(root) - 1) : initDepth.delete(root)));
        }
    };

    let droppedNow = null;

    const makeScopes = (baseEl, dropped) => {
        const walker = document.createTreeWalker(baseEl, NodeFilter.SHOW_ELEMENT, {
            acceptNode: (node) =>
                node.nagiBroken || node.parentElement?.nagiBroken || node.hasAttribute("n-ignore") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
        });
        const seen = new Set();
        const isDropped = (node) => dropped.some((el) => el.contains(node));
        let dataEl = leftAlone(baseEl) || isDropped(baseEl) ? null : baseEl;
        while (dataEl) {
            const parent = dataEl.parentElement;
            const before = dataEl.previousElementSibling;
            seen.add(dataEl);
            dataEl.nagiGone = false;
            makeScope(dataEl);
            const moved = dataEl.parentElement !== parent || dataEl.previousElementSibling !== before;
            walker.currentNode = dataEl !== baseEl && (moved || !baseEl.contains(dataEl)) ? baseEl : dataEl;
            do dataEl = walker.nextNode();
            while (dataEl && (seen.has(dataEl) || isDropped(dataEl)));
        }
    };

    const setUp = (roots) => {
        const outerDrops = droppedNow;
        const dropped = (droppedNow = []);
        try {
            roots.forEach((root) => makeScopes(root, dropped));
        } finally {
            droppedNow = outerDrops;
            outerDrops?.push(...dropped);
        }
        const each = (selector) => roots.flatMap((root) => queryAttr(root, selector));

        each("[n-ref]").forEach((el) => {
            if (el.nagiGone) return;
            const scopeEl = el.nagiProxy ? (closestScope(el.parentElement) ?? el) : closestScope(el);
            if (!scopeEl) return console.error("[Nagi] n-ref needs a scope:", el);
            const refs = scopeEl.nagiRaw.$refs;
            const name = el.getAttribute("n-ref");
            const held = refsOwn.get(refs)?.[name];
            el.nagiRefScope = scopeEl;
            const later = held && held !== el && held.isConnected && held.nagiRefScope === scopeEl && el.compareDocumentPosition(held) & Node.DOCUMENT_POSITION_FOLLOWING;
            if (!later) refs[name] = el;
        });

        each("[n-form]").forEach((form) => form.nagiGone || closestScope(form) || console.error("[Nagi] n-form needs a scope:", form));

        const starts = [];
        each("[name]").filter(isField).forEach((inputEl) => {
            const scopeEl = formScope(inputEl);
            if (inputEl.nagiField || inputEl.nagiGone || !scopeEl || reserved(inputEl.name, inputEl)) return;
            const start = fieldOf(inputEl, scopeEl);
            inputEl.nagiField = !!start;
            if (start) starts.push(start);
        });
        starts.forEach((start) => start());

        each("*").forEach((bindEl) => {
            if (bindEl.nagiGone) return;
            if (bindEl.nagiBound) return void (bindEl.nagiInitDue && heldInits.push(bindEl));
            const entries = [...bindEl.attributes]
                .map(({ name, value }) => [name, sourceOf(bindEl, name, value)])
                .filter(([, source]) => source);
            if (!entries.length) return;
            bindEl.nagiBound = true;

            const proxyData = getClosestProxy(bindEl);
            const props = entries.flatMap(([name, source]) => {
                const made = evaluate(`{${source}}`, proxyData, proxyData, bindEl, hostLayer(bindEl, proxyData, name), name);
                return made === failed ? [] : Object.entries(made).map(([key, val]) => [key, val, name]);
            });

            const gen = bindEl.nagiGen;
            const gone = () => bindEl.nagiGone || bindEl.nagiGen !== gen;
            bindEl.nagiInitDue = true;
            for (const [key, val, name] of props) {
                if (gone()) return;
                if (key.startsWith("@")) listen(bindEl, key.slice(1), val, proxyData, name);
                else bindProp(bindEl, key, val, name);
            }
            if (gone()) return;

            heldInits.push(bindEl);
        });
    };

    let heldInits = null;
    let fieldChecks = null;
    let refusedFields = null;

    const holdInits = (fn) => {
        if (heldInits) return fn();
        const held = (heldInits = []);
        try {
            return fn();
        } finally {
            heldInits = null;
            held.forEach((el) => {
                if (!el.nagiInitDue || !el.isConnected) return;
                el.nagiInitDue = false;
                dispatch(el, "init", { bubbles: false });
            });
        }
    };

    const isElement = (name, el) => el?.nodeType === 1 || void console.error(`[Nagi] nagi.${name} needs an element:`, el);

    window.nagi = Object.freeze({
        init: (el) => void (isElement("init", el) && (el.getRootNode({ composed: true }) === document ? init(el) : console.error("[Nagi] nagi.init needs an element in the page:", el))),
        destroy: (el) => void (isElement("destroy", el) && drop(el)),
    });

    document.addEventListener("DOMContentLoaded", () => init(document.body));
})();
