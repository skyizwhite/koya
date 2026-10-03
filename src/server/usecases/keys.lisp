(defpackage #:koya-server/usecases/keys
  (:use #:cl)
  (:import-from #:koya-core/ulid
                #:make-ulid)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-server/domain/key
                #:new-delivery-key #:new-management-key #:hash-key #:new-webhook-secret #:key-id)
  (:import-from #:koya-server/domain/errors #:fail #:not-found)
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
           #:remove-delivery-key
           #:space-for-delivery-key
           #:create-management-key
           #:list-management-keys
           #:delete-management-key
           #:space-for-management-key
           #:management-key-label
           #:space-webhook-secret
           #:rotate-webhook-secret))
(in-package #:koya-server/usecases/keys)

(defun create-delivery-key (space &key (label ""))
  (let ((key (new-delivery-key))
        (id (make-ulid)))
    (insert-delivery-key space :id id :hash (hash-key key) :label label :created-at (now-iso))
    (values key id)))

(defun create-management-key (space &key (label ""))
  (let ((key (new-management-key))
        (id (make-ulid)))
    (insert-management-key space :id id :hash (hash-key key) :label label :created-at (now-iso))
    (values key id)))

(defun space-for-delivery-key (key)
  (and (stringp key) (space-by-delivery-key-hash (hash-key key))))

(defun space-for-management-key (key)
  (and (stringp key) (space-by-management-key-hash (hash-key key))))

(defun management-key-label (key)
  (and (stringp key) (label-by-management-key-hash (hash-key key))))

(defun rotate-webhook-secret (space)
  (let ((secret (new-webhook-secret)))
    (set-webhook-secret space secret)
    secret))

(defun remove-delivery-key (space id)
  (unless (find id (list-delivery-keys space) :key #'key-id :test #'equal)
    (fail 'not-found (format nil "Key ~a does not exist" id)))
  (delete-delivery-key space id))
