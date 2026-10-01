(defpackage #:koya-server/web/lib/binds
  (:use #:cl)
  (:import-from #:koya-core/json #:to-json)
  (:export #:js
           #:posts
           #:clicks
           #:follows
           #:searches
           #:reveals
           #:uploads
           #:+draws-refusals+))
(in-package #:koya-server/web/lib/binds)

(defun js (string) (to-json string))

(defparameter +draws-refusals+
  "'onfetcherr.stop': (e) => koya.refused(e, (url) => $fetch(url, 'GET'))")

(defun binds (&rest entries)
  (format nil "{ ~{~a~^, ~} }" (remove nil entries)))

(defun request (method url data confirm)
  (format nil "~@[confirm(~a) && ~]$~a(~a~@[, ~a~])" (and confirm (js confirm)) method (js url) data))

(defun posts (url &key (data "koya.form(this)") confirm also)
  (binds (format nil "'onsubmit.prevent': () => ~a" (request "post" url data confirm))
         also
         +draws-refusals+))

(defun clicks (url &key data confirm also)
  (binds (format nil "onclick: () => ~a" (request "post" url data confirm))
         also
         +draws-refusals+))

(defun follows (url)
  (binds (format nil "onclick: (e) => koya.follow(e) && $get(~a)" (js url))
         +draws-refusals+))

(defun searches (url &key (typing t))
  (binds (format nil "'onsubmit.prevent': () => _ask(~a, this, true)" (js url))
         (and typing (format nil "'oninput.debounce300': () => _ask(~a, this)" (js url)))
         (format nil "onchange: () => _ask(~a, this)" (js url))
         +draws-refusals+))

(defun reveals (url)
  (binds "oninit: koya.reveal"
         (format nil "onrevealed: () => $get(~a)" (js url))
         +draws-refusals+))

(defun uploads (url)
  (binds (format nil "onchange: (e) => koya.upload(e.target, ~a, (url) => $fetch(url, 'GET'))" (js url))))
