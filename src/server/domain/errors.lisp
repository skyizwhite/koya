(defpackage #:koya-server/domain/errors
  (:use #:cl)
  (:export #:koya-error
           #:koya-error-code
           #:koya-error-message
           #:koya-error-details
           #:not-found
           #:conflict
           #:invalid-input
           #:rejected
           #:too-large
           #:fail))
(in-package #:koya-server/domain/errors)

;;; What goes wrong in koya, said without HTTP. The class is the kind of failure;
;;; web/http is where a kind becomes a status. CODE is the word the APIs carry in
;;; their error object, so it is part of what a caller can rely on: a new code is
;;; an API change (docs/openapi.yaml).

(define-condition koya-error (error)
  ((code :initarg :code :reader koya-error-code)
   (message :initarg :message :reader koya-error-message)
   (details :initarg :details :initform nil :reader koya-error-details))
  (:report (lambda (c s) (write-string (koya-error-message c) s))))

(define-condition not-found (koya-error) ()
  (:default-initargs :code "not_found")
  (:documentation "What was asked for does not exist."))

(define-condition conflict (koya-error) ()
  (:default-initargs :code "conflict")
  (:documentation "The request is sound but the state of koya refuses it: taken,
in use, not published, destructive."))

(define-condition invalid-input (koya-error) ()
  (:default-initargs :code "bad_request")
  (:documentation "The request itself is malformed."))

(define-condition rejected (koya-error) ()
  (:default-initargs :code "rejected")
  (:documentation "Well-formed, but not something koya accepts: an empty file, an
image type it does not take."))

(define-condition too-large (koya-error) ()
  (:default-initargs :code "too_large"))

(defun fail (kind message &rest initargs &key code details)
  "Signal a condition of KIND with MESSAGE. CODE replaces the kind's own."
  (declare (ignore code details))
  (apply #'error kind :message message initargs))
