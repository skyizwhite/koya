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

(defgeneric insert-delivery-key (space &key id hash label created-at))

(defgeneric list-delivery-keys (space))

(defgeneric delete-delivery-key (space id))

(defgeneric space-by-delivery-key-hash (hash))

(defgeneric stored-delivery-keys (space))

(defgeneric insert-management-key (space &key id hash label created-at))

(defgeneric list-management-keys (space))

(defgeneric delete-management-key (space id))

(defgeneric space-by-management-key-hash (hash))

(defgeneric label-by-management-key-hash (hash))

(defgeneric stored-management-keys (space))
