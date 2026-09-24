(defpackage #:koya-server/usecases/ports/sessions
  (:use #:cl)
  (:export #:make-session-store
           #:purge-expired-sessions
           #:+session-seconds+))
(in-package #:koya-server/usecases/ports/sessions)

;;; Where the owner's session is kept between requests. See ports/store for what
;;; a port is.

(declaim (ftype function make-session-store purge-expired-sessions))

;; (make-session-store): a Lack session store.

(defparameter +session-seconds+ (* 24 3600)
  "How long a session lives, in the cookie and in the store. Using a session
slides both, so the owner is logged out only after a day away.")
