(defpackage #:koya-server/web/lib/binds
  (:use #:cl)
  (:import-from #:koya-core/json #:to-json)
  (:export #:js-string
           #:post
           #:submit
           #:follow
           #:ask
           #:upload-picked))
(in-package #:koya-server/web/lib/binds)

(defun js-string (string) (to-json string))

(defun post (url &key data confirm guard)
  (format nil "~@[~a && ~]~@[confirm(~a) && ~]$post(~a~@[, ~a~])"
          guard (and confirm (js-string confirm)) (js-string url) data))

(defun submit (url &key (data "e") confirm guard)
  (post url :data data :confirm confirm :guard guard))

(defun follow (url)
  (format nil "koya.follow(e) && $get(~a)" (js-string url)))

(defun ask (url)
  (format nil "$get(~a)" (js-string url)))

(defun upload-picked (url)
  (format nil "koya.fits(e.target) && $post(~a, e)" (js-string url)))
