(defpackage #:koya-server/web/lib/middlewares
  (:use #:cl)
  (:import-from #:lack-mw
                #:with-args #:*mw-cache-control* #:*mw-cors* #:*mw-body-limit*)
  (:import-from #:koya-server/domain/media #:+max-upload-bytes+)
  (:export #:+temporary-file-header+
           #:*mw-temporary-file*
           #:*mw-default-cache-control*
           #:*mw-delivery-cors*
           #:*mw-max-body*
           #:+max-body-bytes+))
(in-package #:koya-server/web/lib/middlewares)

(defparameter *mw-default-cache-control*
  (with-args *mw-cache-control*
    :rules '(("/assets/" "public, max-age=31536000, immutable" :status (200)))
    :default "no-store"))

(defparameter *mw-delivery-cors*
  (with-args *mw-cors*
    :origin "*"
    :allow-methods '("GET")
    :allow-headers '("X-KOYA-DELIVERY-KEY")
    :max-age 86400))

(defparameter +max-body-bytes+ (+ +max-upload-bytes+ (* 1024 1024)))

(defun too-large-response (env)
  (let ((message (format nil "Request body is limited to ~a MB"
                         (floor +max-body-bytes+ (* 1024 1024)))))
    (if (equal (gethash "koya-request" (getf env :headers)) "true")
        (list 413 (list :content-type "text/html; charset=utf-8" :cache-control "no-store")
              (list (format nil "<p class=\"text-sm text-danger\">~a</p>" message)))
        (list 413 (list :content-type "application/json; charset=utf-8" :cache-control "no-store")
              (list (format nil "{\"error\":{\"code\":\"too_large\",\"message\":\"~a\"}}" message))))))

(defparameter *mw-max-body*
  (with-args *mw-body-limit* :max-size +max-body-bytes+ :on-error #'too-large-response))

(defparameter +temporary-file-header+ :x-koya-temporary-file)

(defparameter *mw-temporary-file*
  (lambda (app)
    (lambda (env)
      (let ((response (funcall app env)))
        (if (and (listp response) (getf (second response) +temporary-file-header+))
            (destructuring-bind (status headers file) response
              (remf headers +temporary-file-header+)
              (lambda (responder)
                (unwind-protect (funcall responder (list status headers file))
                  (uiop:delete-file-if-exists file))))
            response)))))
