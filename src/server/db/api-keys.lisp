(defpackage #:koya-server/db/api-keys
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string #:digest-sequence #:ascii-string-to-byte-array)
  (:export #:create-api-key
           #:list-api-keys
           #:delete-api-key
           #:space-for-api-key
           #:hash-api-key))
(in-package #:koya-server/db/api-keys)

;;; Delivery API keys. The plaintext key is shown once at creation; only its
;;; SHA-256 is stored. Keys are random enough that no salt or slow hash is needed.

(defun hash-api-key (key)
  (byte-array-to-hex-string (digest-sequence :sha256 (ascii-string-to-byte-array key))))

(defun create-api-key (space &key (label ""))
  "Create a key for SPACE. Returns (values plaintext-key id)."
  (let* ((key (format nil "koya_~a" (byte-array-to-hex-string (random-data 24))))
         (id (make-ulid)))
    (exec "INSERT INTO api_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
          id space (hash-api-key key) label (now-iso))
    (values key id)))

(defun list-api-keys (space)
  "Plists (:id :label :created-at) of the keys of SPACE."
  (mapcar (lambda (row) (list :id (col row "id") :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT id, label, created_at FROM api_keys WHERE space = ? ORDER BY created_at" space)))

(defun delete-api-key (space id)
  (exec "DELETE FROM api_keys WHERE space = ? AND id = ?" space id))

(defun space-for-api-key (key)
  "The space name KEY grants access to, or NIL."
  (and (stringp key)
       (let ((row (fetch-one "SELECT space FROM api_keys WHERE key_hash = ?" (hash-api-key key))))
         (and row (col row "space")))))
