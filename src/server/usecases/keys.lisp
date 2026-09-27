(defpackage #:koya-server/usecases/keys
  (:use #:cl)
  (:import-from #:koya-core/ulid
                #:make-ulid)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-server/domain/key
                #:new-delivery-key #:new-management-key #:hash-key #:new-webhook-secret)
  (:import-from #:koya-server/usecases/ports/keys
                #:insert-delivery-key #:list-delivery-keys #:delete-delivery-key
                #:space-by-delivery-key-hash
                #:insert-management-key #:list-management-keys #:delete-management-key
                #:space-by-management-key-hash #:label-by-management-key-hash)
  (:import-from #:koya-server/usecases/ports/spaces
                #:space-webhook-secret #:set-webhook-secret)
  (:export #:create-delivery-key
           #:list-delivery-keys
           #:delete-delivery-key
           #:space-for-delivery-key
           #:create-management-key
           #:list-management-keys
           #:delete-management-key
           #:space-for-management-key
           #:management-key-label
           #:space-webhook-secret
           #:rotate-webhook-secret))
(in-package #:koya-server/usecases/keys)

;;; Four keys, three kinds of callers:
;;;  - the owner secret (KOYA_SECRET) logs into the admin UI (usecases/auth)
;;;  - a management key drives the admin API for one space, and reaches nothing
;;;    outside it
;;;  - a delivery key reads one space's published content
;;;  - the webhook secret is the one koya sends, not one it checks
;;;
;;; A key is made and hashed here; the store is handed the hash and asked by it.

(defun create-delivery-key (space &key (label ""))
  "Make a delivery key for SPACE. Returns (values plaintext-key id): the plaintext
is not kept, so this is the one time it is seen."
  (let ((key (new-delivery-key))
        (id (make-ulid)))
    (insert-delivery-key space :id id :hash (hash-key key) :label label :created-at (now-iso))
    (values key id)))

(defun create-management-key (space &key (label ""))
  "Make a management key for SPACE. Returns (values plaintext-key id), as
CREATE-DELIVERY-KEY does."
  (let ((key (new-management-key))
        (id (make-ulid)))
    (insert-management-key space :id id :hash (hash-key key) :label label :created-at (now-iso))
    (values key id)))

;; KEY is whatever a request carried, so anything but a string is no key
(defun space-for-delivery-key (key)
  "The space KEY reads, or NIL when it is not a delivery key."
  (and (stringp key) (space-by-delivery-key-hash (hash-key key))))

(defun space-for-management-key (key)
  "The space KEY manages, or NIL when it is not a management key."
  (and (stringp key) (space-by-management-key-hash (hash-key key))))

(defun management-key-label (key)
  "The label of the management key KEY, or NIL when it is not one."
  (and (stringp key) (label-by-management-key-hash (hash-key key))))

(defun rotate-webhook-secret (space)
  "Give SPACE a new webhook secret and return it. The old one stops being sent at
once, so the site must be given the new one."
  (let ((secret (new-webhook-secret)))
    (set-webhook-secret space secret)
    secret))
