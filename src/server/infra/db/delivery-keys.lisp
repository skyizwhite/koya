(defpackage #:koya-server/infra/db/delivery-keys
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/domain/key #:make-key)
  (:import-from #:koya-core/ulid
                #:make-ulid)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string #:digest-sequence)
  (:import-from #:babel
                #:string-to-octets)
  (:import-from #:koya-server/usecases/ports/keys
                #:create-delivery-key #:stored-delivery-keys #:import-delivery-key
                #:list-delivery-keys #:delete-delivery-key #:space-for-delivery-key)
  (:export #:hash-key))
(in-package #:koya-server/infra/db/delivery-keys)

;;; Delivery keys. The plaintext key is shown once at creation; only its
;;; SHA-256 is stored. Keys are random enough that no salt or slow hash is needed.

(defun hash-key (key)
  "SHA-256 of KEY as hex. UTF-8, not ASCII: a header with any character in it must
fail to match, not fail to hash."
  (byte-array-to-hex-string (digest-sequence :sha256 (string-to-octets key :encoding :utf-8))))

(defmethod create-delivery-key (space &key (label ""))
  (let* ((key (format nil "koya_~a" (byte-array-to-hex-string (random-data 24))))
         (id (make-ulid)))
    (exec "INSERT INTO delivery_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
          id space (hash-key key) label (now-iso))
    (values key id)))

(defmethod list-delivery-keys (space)
  (mapcar (lambda (row) (make-key :id (col row "id") :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT id, label, created_at FROM delivery_keys WHERE space = ? ORDER BY created_at" space)))

(defmethod delete-delivery-key (space id)
  (exec "DELETE FROM delivery_keys WHERE space = ? AND id = ?" space id))

(defmethod space-for-delivery-key (key)
  (and (stringp key)
       (let ((row (fetch-one "SELECT space FROM delivery_keys WHERE key_hash = ?" (hash-key key))))
         (and row (col row "space")))))

(defmethod stored-delivery-keys (space)
  (mapcar (lambda (row) (make-key :id (col row "id") :hash (col row "key_hash")
                                  :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT * FROM delivery_keys WHERE space = ? ORDER BY created_at" space)))

(defmethod import-delivery-key (space &key id hash label created-at)
  (exec "INSERT INTO delivery_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
        id space hash (or label "") created-at))
