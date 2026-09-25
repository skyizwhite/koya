(defpackage #:koya-server/usecases/ports/sessions
  (:use #:cl)
  (:export #:make-session-store
           #:+session-seconds+))
(in-package #:koya-server/usecases/ports/sessions)

;;; Where the owner's session is kept between requests.

(defgeneric make-session-store ()
  (:documentation "A store the web's session middleware keeps the owner's session in, across
restarts. What a store answers to is that middleware's protocol, which infra
speaks; the use cases only ask for one."))

(defparameter +session-seconds+ (* 24 3600)
  "How long a session lives, in the cookie and in the store. Using a session
slides both, so the owner is logged out only after a day away.")
