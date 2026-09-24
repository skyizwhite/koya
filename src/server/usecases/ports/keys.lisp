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
;;; returned once, when it is made. See ports/store for what a port is.

(declaim (ftype function create-delivery-key list-delivery-keys delete-delivery-key
                space-for-delivery-key stored-delivery-keys import-delivery-key
                create-management-key list-management-keys delete-management-key
                space-for-management-key management-key-label
                stored-management-keys import-management-key))
