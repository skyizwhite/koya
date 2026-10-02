(defpackage #:koya-server/web/lib/binds
  (:use #:cl)
  (:import-from #:koya-core/json #:to-json)
  (:export #:js-string
           #:on-submit
           #:on-click
           #:on-follow
           #:on-search
           #:on-reveal
           #:on-pick))
(in-package #:koya-server/web/lib/binds)

(defun js-string (string) (to-json string))

(defun binds (&rest entries)
  (format nil "{ ~{~a~^, ~} }" (remove nil entries)))

(defun request (method url data confirm)
  (format nil "~@[confirm(~a) && ~]$~a(~a~@[, ~a~])" (and confirm (js-string confirm)) method (js-string url) data))

(defun on-submit (url &key (data "koya.form(this)") confirm binds)
  (binds (format nil "'onsubmit.prevent': () => ~a" (request "post" url data confirm))
         binds))

(defun on-click (url &key data confirm binds)
  (binds (format nil "onclick: () => ~a" (request "post" url data confirm))
         binds))

(defun on-follow (url)
  (binds (format nil "onclick: (e) => koya.follow(e) && $get(~a)" (js-string url))))

(defun on-search (url &key (typing t))
  (binds (format nil "'onsubmit.prevent': () => _ask(~a, this, true)" (js-string url))
         (and typing (format nil "'oninput.debounce300': () => _ask(~a, this)" (js-string url)))
         (format nil "onchange: () => _ask(~a, this)" (js-string url))))

(defun on-reveal (url)
  (binds "oninit: koya.reveal"
         (format nil "onrevealed: () => $get(~a)" (js-string url))))

(defun on-pick (url)
  (binds (format nil "onchange: (e) => koya.upload(e.target, ~a, (url) => $fetch(url, 'GET'))" (js-string url))))
