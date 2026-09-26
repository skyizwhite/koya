(defpackage #:koya-server/web/middlewares
  (:use #:cl)
  (:import-from #:lack-mw
                #:with-args #:*cache-control* #:*cors* #:*body-limit*)
  (:import-from #:koya-server/domain/media #:+max-upload-bytes+)
  (:export #:+temporary-file-header+
           #:*temporary-file-middleware*
           #:*cache-control-middleware*
           #:*delivery-cors-middleware*
           #:*body-limit-middleware*
           #:+max-body-bytes+))
(in-package #:koya-server/web/middlewares)

;;; Middlewares app.lisp stacks: koya's settings for lack-mw's, and
;;; *temporary-file-middleware* below. The auth guards stay in web/auth, which
;;; they share its key and session checks with.

(defparameter *cache-control-middleware*
  (with-args *cache-control*
    ;; asset URLs carry ?v=<version> (see web/assets), so the file behind one never changes
    :rules '(("/assets/" "public, max-age=31536000, immutable" :status (200)))
    ;; pages and both APIs are per-request and often per-owner
    :default "no-store")
  "Cache-Control for everything that did not set one: immutable assets, no-store otherwise.
/media/ sets its own (see MEDIA-APP).")

;; A delivery key reads only what is published, so a page on any origin may use one;
;; answering with "*" rather than the caller's origin keeps the answer the same for
;; every caller, so no Vary on Origin is needed. The admin API is not mounted under this.
(defparameter *delivery-cors-middleware*
  (with-args *cors*
    :origin "*"
    :allow-methods '("GET")
    :allow-headers '("X-KOYA-DELIVERY-KEY")
    :max-age 86400)
  "CORS for the delivery API: answers the preflight a browser sends before a GET with
X-KOYA-DELIVERY-KEY, and lets the page read every answer, errors included.")

(defparameter +max-body-bytes+ (+ +max-upload-bytes+ (* 1024 1024))
  "Largest request body accepted: the media upload limit plus room for the other
parts. A space archive is uploaded in pieces smaller than this.")

(defun too-large-response (env)
  (let ((message (format nil "Request body is limited to ~a MB"
                         (floor +max-body-bytes+ (* 1024 1024)))))
    ;; htmx swaps an error response in, so it gets HTML rather than JSON
    (if (gethash "hx-request" (getf env :headers))
        (list 413 (list :content-type "text/html; charset=utf-8" :cache-control "no-store")
              (list (format nil "<p class=\"text-sm text-danger\">~a</p>" message)))
        (list 413 (list :content-type "application/json; charset=utf-8" :cache-control "no-store")
              (list (format nil "{\"error\":{\"code\":\"too_large\",\"message\":\"~a\"}}" message))))))

(defparameter *body-limit-middleware*
  (with-args *body-limit* :max-size +max-body-bytes+ :on-error #'too-large-response)
  "Rejects oversized bodies, before any parser allocates for them.
Under Woo no such body gets here: Woo is held to the same limit (web/app) and
answers 413 itself, in plain text, before it reads a body its Content-Length
puts past it, or once one goes past it.")

;;; A page may answer with a file it made for the one answer, such as a space's
;;; archive, and that nothing needs once it is sent. It says so with the header
;;; below, which goes no further than here. The file is deleted once the server
;;; has it: Woo opens the file before it returns and sends from what it opened,
;;; and Hunchentoot sends it whole before it returns.

(defparameter +temporary-file-header+ :x-koya-temporary-file)

(defparameter *temporary-file-middleware*
  (lambda (app)
    (lambda (env)
      (let ((response (funcall app env)))
        (if (and (listp response) (getf (second response) +temporary-file-header+))
            (destructuring-bind (status headers file) response
              (remf headers +temporary-file-header+)
              (lambda (responder)
                (unwind-protect (funcall responder (list status headers file))
                  (uiop:delete-file-if-exists file))))
            response))))
  "Deletes the file a response marked with +TEMPORARY-FILE-HEADER+ sends, once the
server has it. Installed outside everything that reads a response as a list.")
