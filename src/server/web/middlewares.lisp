(defpackage #:koya-server/web/middlewares
  (:use #:cl)
  (:import-from #:koya-server/domain/media #:+max-upload-bytes+)
  (:import-from #:smart-buffer)
  (:export #:+temporary-file-header+
           #:*temporary-file-middleware*
           #:*body-file-middleware*
           #:*cache-control-middleware*
           #:*delivery-cors-middleware*
           #:*body-limit-middleware*))
(in-package #:koya-server/web/middlewares)

;;; The Lack middlewares app.lisp installs. Two stay with what they are built from:
;;; the auth guards in web/auth, which share its key and session checks, and
;;; *media-middleware* in web/media, which serves the library's files.

(defun prefix-p (prefix path)
  (and (>= (length path) (length prefix)) (string= prefix path :end2 (length prefix))))

;;; Woo reads a request's whole body before the app sees it, and one past a
;;; megabyte goes to a file under smart-buffer's temporary directory. It hands
;;; the app that file open and neither closes nor deletes it: left alone, every
;;; large body -- a media upload, or anything anyone posts -- stays on the disk.

(defun body-file (stream)
  "The file Woo left a body in, when STREAM reads one, or NIL for a body held in
memory, or read from the socket as Hunchentoot does."
  (let ((path (and (typep stream 'file-stream) (ignore-errors (pathname stream))))
        (directory (namestring smart-buffer::*temporary-directory*)))
    (and path (prefix-p directory (namestring path)) path)))

(defun remove-body-file (stream)
  (let ((path (body-file stream)))
    (when path
      (close stream)
      (uiop:delete-file-if-exists path))))

(defparameter *body-file-middleware*
  (lambda (app)
    (lambda (env)
      ;; taken now: lack wraps the body in a stream of its own, in ENV itself
      (let ((body (getf env :raw-body))
            (response nil))
        (unwind-protect
             (setf response
                   (let ((answer (funcall app env)))
                     (if (functionp answer)
                         ;; a delayed answer may read the body until it is done
                         (lambda (responder)
                           (unwind-protect (funcall answer responder)
                             (remove-body-file body)))
                         answer)))
          (unless (functionp response)
            (remove-body-file body))))))
  "Deletes the file Woo buffered a request's body in, once the request is answered.
Installed outermost, so it runs whatever answered.")

(defparameter *cache-control-middleware*
  (lambda (app)
    (lambda (env)
      ;; taken before the call: the static middleware strips its prefix from path-info
      (let* ((path (getf env :path-info))
             (response (funcall app env)))
        (when (and (listp response) (not (getf (second response) :cache-control)))
          (setf (getf (second response) :cache-control)
                (if (and (prefix-p "/assets/" path) (eql (first response) 200))
                    ;; asset URLs carry ?v=<version> (see web/assets), so the file behind one never changes
                    "public, max-age=31536000, immutable"
                    ;; pages and both APIs are per-request and often per-owner
                    "no-store")))
        response)))
  "Cache-Control for everything that did not set one: immutable assets, no-store otherwise.
/media/ sets its own (see *media-middleware*).")

;; A delivery key reads only what is published, so a page on any origin may use one;
;; answering with "*" rather than the caller's origin keeps the answer the same for
;; every caller, so no Vary is needed. The admin API is not mounted under this.
(defparameter *delivery-cors-middleware*
  (lambda (app)
    (lambda (env)
      (if (eq (getf env :request-method) :options)
          ;; a preflight never reaches the routes: it carries no key to check
          (list 204 (list :access-control-allow-origin "*"
                          :access-control-allow-methods "GET"
                          :access-control-allow-headers "X-KOYA-DELIVERY-KEY"
                          :access-control-max-age "86400")
                '())
          (let ((response (funcall app env)))
            (when (listp response)
              (setf (getf (second response) :access-control-allow-origin) "*"))
            response))))
  "CORS for the delivery API: answers the preflight a browser sends before a GET with
X-KOYA-DELIVERY-KEY, and lets the page read every answer, errors included.")

(defparameter +max-body-bytes+ (+ +max-upload-bytes+ (* 1024 1024))
  "Largest request body accepted: the media upload limit plus room for the other
parts. A space archive is uploaded in pieces smaller than this.")

(defparameter *body-limit-middleware*
  (lambda (app)
    (lambda (env)
      (let ((length (getf env :content-length)))
        (if (and (integerp length) (> length +max-body-bytes+))
            ;; before anything parses the body: lack reads a multipart body whole
            (let ((message (format nil "Request body is limited to ~a MB"
                                   (floor +max-body-bytes+ (* 1024 1024)))))
              ;; htmx swaps an error response in, so it gets HTML rather than JSON
              (if (gethash "hx-request" (getf env :headers))
                  (list 413 (list :content-type "text/html; charset=utf-8" :cache-control "no-store")
                        (list (format nil "<p class=\"text-sm text-danger\">~a</p>" message)))
                  (list 413 (list :content-type "application/json; charset=utf-8" :cache-control "no-store")
                        (list (format nil "{\"error\":{\"code\":\"too_large\",\"message\":\"~a\"}}" message)))))
            (funcall app env)))))
  "Rejects oversized bodies by Content-Length, before any parser allocates for them.
Woo has read the body by then, up to smart-buffer's own limit of a gigabyte.
That limit is not lowered to this one: past it Woo signals an error it does not
catch, which stops the server.")

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
