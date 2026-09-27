(defpackage #:koya-server/infra/db/delivery-keys
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/domain/key #:make-key)
  (:import-from #:koya-server/usecases/ports/keys
                #:insert-delivery-key #:stored-delivery-keys
                #:list-delivery-keys #:delete-delivery-key #:space-by-delivery-key-hash))
(in-package #:koya-server/infra/db/delivery-keys)

(defmethod insert-delivery-key (space &key id hash label created-at)
  (exec "INSERT INTO delivery_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
        id space hash (or label "") created-at))

(defmethod list-delivery-keys (space)
  (mapcar (lambda (row) (make-key :id (col row "id") :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT id, label, created_at FROM delivery_keys WHERE space = ? ORDER BY created_at" space)))

(defmethod delete-delivery-key (space id)
  (exec "DELETE FROM delivery_keys WHERE space = ? AND id = ?" space id))

(defmethod space-by-delivery-key-hash (hash)
  (let ((row (fetch-one "SELECT space FROM delivery_keys WHERE key_hash = ?" hash)))
    (and row (col row "space"))))

(defmethod stored-delivery-keys (space)
  (mapcar (lambda (row) (make-key :id (col row "id") :hash (col row "key_hash")
                                  :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT * FROM delivery_keys WHERE space = ? ORDER BY created_at" space)))
