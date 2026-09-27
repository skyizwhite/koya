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

(define-condition koya-error (error)
  ((code :initarg :code :reader koya-error-code)
   (message :initarg :message :reader koya-error-message)
   (details :initarg :details :initform nil :reader koya-error-details))
  (:report (lambda (c s) (write-string (koya-error-message c) s))))

(define-condition not-found (koya-error) ()
  (:default-initargs :code "not_found"))

(define-condition conflict (koya-error) ()
  (:default-initargs :code "conflict"))

(define-condition invalid-input (koya-error) ()
  (:default-initargs :code "bad_request"))

(define-condition rejected (koya-error) ()
  (:default-initargs :code "rejected"))

(define-condition too-large (koya-error) ()
  (:default-initargs :code "too_large"))

(defun fail (kind message &rest initargs &key code details)
  (declare (ignore code details))
  (apply #'error kind :message message initargs))
