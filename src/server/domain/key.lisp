(defpackage #:koya-server/domain/key
  (:use #:cl)
  (:export #:key #:make-key
           #:key-id #:key-hash #:key-label #:key-created-at))
(in-package #:koya-server/domain/key)

;;; A key of a space, as stored: only its hash is kept, and the plaintext is
;;; shown once, when it is made. HASH is NIL where a key is listed to be shown;
;;; an export carries it, since the hash is all a moved key needs.

(defstruct key
  id hash label created-at)
