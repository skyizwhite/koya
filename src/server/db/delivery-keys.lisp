(defpackage #:koya-server/db/delivery-keys
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string #:digest-sequence)
  (:import-from #:babel
                #:string-to-octets)
  (:export #:create-delivery-key
           #:stored-delivery-keys
           #:import-delivery-key
           #:list-delivery-keys
           #:delete-delivery-key
           #:space-for-delivery-key
           #:hash-key))
(in-package #:koya-server/db/delivery-keys)

;;; Delivery keys. The plaintext key is shown once at creation; only its
;;; SHA-256 is stored. Keys are random enough that no salt or slow hash is needed.

(defun hash-key (key)
  "SHA-256 of KEY as hex. UTF-8, not ASCII: a header with any character in it must
fail to match, not fail to hash."
  (byte-array-to-hex-string (digest-sequence :sha256 (string-to-octets key :encoding :utf-8))))

(defun create-delivery-key (space &key (label ""))
  "Create a key for SPACE. Returns (values plaintext-key id)."
  (let* ((key (format nil "koya_~a" (byte-array-to-hex-string (random-data 24))))
         (id (make-ulid)))
    (exec "INSERT INTO delivery_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
          id space (hash-key key) label (now-iso))
    (values key id)))

(defun list-delivery-keys (space)
  "Plists (:id :label :created-at) of the keys of SPACE."
  (mapcar (lambda (row) (list :id (col row "id") :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT id, label, created_at FROM delivery_keys WHERE space = ? ORDER BY created_at" space)))

(defun delete-delivery-key (space id)
  (exec "DELETE FROM delivery_keys WHERE space = ? AND id = ?" space id))

(defun space-for-delivery-key (key)
  "The space name KEY grants access to, or NIL."
  (and (stringp key)
       (let ((row (fetch-one "SELECT space FROM delivery_keys WHERE key_hash = ?" (hash-key key))))
         (and row (col row "space")))))

(defun stored-delivery-keys (space)
  "Plists (:id :hash :label :created-at) of the keys of SPACE as stored, for an
export: the hash is all there is, and all a moved key needs."
  (mapcar (lambda (row) (list :id (col row "id") :hash (col row "key_hash")
                              :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT * FROM delivery_keys WHERE space = ? ORDER BY created_at" space)))

(defun import-delivery-key (space &key id hash label created-at)
  (exec "INSERT INTO delivery_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
        id space hash (or label "") created-at))
