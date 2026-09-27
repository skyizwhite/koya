(defpackage #:koya-server/usecases/ports/keys
  (:use #:cl)
  (:export #:insert-delivery-key
           #:list-delivery-keys
           #:delete-delivery-key
           #:space-by-delivery-key-hash
           #:stored-delivery-keys
           #:insert-management-key
           #:list-management-keys
           #:delete-management-key
           #:space-by-management-key-hash
           #:label-by-management-key-hash
           #:stored-management-keys))
(in-package #:koya-server/usecases/ports/keys)

;;; The keys of a space (domain/key): delivery keys read its published content,
;;; management keys drive the admin API for it. The store keeps a key's hash and
;;; is asked by it; it never sees the plaintext.

(defgeneric insert-delivery-key (space &key id hash label created-at)
  (:documentation "Store a key of SPACE by its HASH: a new one, or one an import carries."))

(defgeneric list-delivery-keys (space)
  (:documentation "The keys of SPACE, oldest first, without their hashes."))

(defgeneric delete-delivery-key (space id))

(defgeneric space-by-delivery-key-hash (hash)
  (:documentation "The space the delivery key hashed as HASH reads, or NIL."))

(defgeneric stored-delivery-keys (space)
  (:documentation "The keys of SPACE as stored, hashes included, for an export."))

(defgeneric insert-management-key (space &key id hash label created-at)
  (:documentation "Store a key of SPACE by its HASH: a new one, or one an import carries."))

(defgeneric list-management-keys (space)
  (:documentation "The keys of SPACE, oldest first, without their hashes."))

(defgeneric delete-management-key (space id))

(defgeneric space-by-management-key-hash (hash)
  (:documentation "The space the management key hashed as HASH manages, or NIL."))

(defgeneric label-by-management-key-hash (hash)
  (:documentation "The label of the management key hashed as HASH, or NIL when there is none.
An unlabelled key answers with the empty string it was made with."))

(defgeneric stored-management-keys (space)
  (:documentation "The keys of SPACE as stored, hashes included, for an export."))
