(defpackage #:koya-server/usecases/ports/keys
  (:use #:cl)
  (:export #:create-delivery-key
           #:list-delivery-keys
           #:delete-delivery-key
           #:space-for-delivery-key
           #:stored-delivery-keys
           #:import-delivery-key
           #:create-management-key
           #:list-management-keys
           #:delete-management-key
           #:space-for-management-key
           #:management-key-label
           #:stored-management-keys
           #:import-management-key))
(in-package #:koya-server/usecases/ports/keys)

;;; The keys of a space: delivery keys read its published content, management
;;; keys drive the admin API for it. Only a key's hash is kept; the plaintext is
;;; returned once, when it is made.

(defgeneric create-delivery-key (space &key label)
  (:documentation "Create a key for SPACE. Returns (values plaintext-key id)."))

(defgeneric list-delivery-keys (space)
  (:documentation "Plists (:id :label :created-at) of the keys of SPACE."))

(defgeneric delete-delivery-key (space id))

(defgeneric space-for-delivery-key (key)
  (:documentation "The space name KEY grants access to, or NIL."))

(defgeneric stored-delivery-keys (space)
  (:documentation "Plists (:id :hash :label :created-at) of the keys of SPACE as stored, for an
export: the hash is all there is, and all a moved key needs."))

(defgeneric import-delivery-key (space &key id hash label created-at))

(defgeneric create-management-key (space &key label)
  (:documentation "Create a key for SPACE. Returns (values plaintext-key id)."))

(defgeneric list-management-keys (space)
  (:documentation "Plists (:id :label :created-at) of the keys of SPACE, oldest first."))

(defgeneric delete-management-key (space id))

(defgeneric space-for-management-key (key)
  (:documentation "The space KEY manages, or NIL when it is not a management key."))

(defgeneric management-key-label (key)
  (:documentation "The label of the management key KEY, or NIL when it is not one. An unlabelled
key answers with the empty string it was made with."))

(defgeneric stored-management-keys (space)
  (:documentation "Plists (:id :hash :label :created-at) of the keys of SPACE as stored, for an
export: the hash is all there is, and all a moved key needs."))

(defgeneric import-management-key (space &key id hash label created-at))
