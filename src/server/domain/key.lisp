(defpackage #:koya-server/domain/key
  (:use #:cl)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string #:digest-sequence)
  (:import-from #:babel
                #:string-to-octets)
  (:export #:key #:make-key
           #:key-id #:key-hash #:key-label #:key-created-at
           #:new-delivery-key
           #:new-management-key
           #:hash-key
           #:new-webhook-secret))
(in-package #:koya-server/domain/key)

;;; A key of a space, as stored: only its hash is kept, and the plaintext is
;;; shown once, when it is made. HASH is NIL where a key is listed to be shown;
;;; an export carries it, since the hash is all a moved key needs.

(defstruct key
  id hash label created-at)

;; the prefixes let a key found in a leaked file be told apart, and a delivery
;; key from one that deploys a schema
(defun new-delivery-key () (format nil "koya_~a" (byte-array-to-hex-string (random-data 24))))
(defun new-management-key () (format nil "koya_mgmt_~a" (byte-array-to-hex-string (random-data 24))))

(defun hash-key (key)
  "SHA-256 of KEY as hex. Keys are random enough that no salt or slow hash is
needed. UTF-8, not ASCII: a header with any character in it must fail to match,
not fail to hash."
  (byte-array-to-hex-string (digest-sequence :sha256 (string-to-octets key :encoding :utf-8))))

(defun new-webhook-secret ()
  "The secret a space's webhooks carry. Kept as it is, not hashed: koya sends it
rather than checks it."
  (byte-array-to-hex-string (random-data 24)))
