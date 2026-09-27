(defpackage #:koya-server/infra/db/management-keys
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/domain/key #:make-key)
  (:import-from #:koya-server/usecases/ports/keys
                #:insert-management-key #:stored-management-keys
                #:label-by-management-key-hash #:list-management-keys #:delete-management-key
                #:space-by-management-key-hash))
(in-package #:koya-server/infra/db/management-keys)

(defmethod insert-management-key (space &key id hash label created-at)
  (exec "INSERT INTO management_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
        id space hash (or label "") created-at))

(defmethod list-management-keys (space)
  (mapcar (lambda (row) (make-key :id (col row "id") :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT id, label, created_at FROM management_keys WHERE space = ? ORDER BY created_at" space)))

(defmethod delete-management-key (space id)
  (exec "DELETE FROM management_keys WHERE space = ? AND id = ?" space id))

(defmethod label-by-management-key-hash (hash)
  (let ((row (fetch-one "SELECT label FROM management_keys WHERE key_hash = ?" hash)))
    (and row (col row "label"))))

(defmethod space-by-management-key-hash (hash)
  (let ((row (fetch-one "SELECT space FROM management_keys WHERE key_hash = ?" hash)))
    (and row (col row "space"))))

(defmethod stored-management-keys (space)
  (mapcar (lambda (row) (make-key :id (col row "id") :hash (col row "key_hash")
                                  :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT * FROM management_keys WHERE space = ? ORDER BY created_at" space)))
