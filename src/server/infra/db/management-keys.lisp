(defpackage #:koya-server/infra/db/management-keys
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/infra/db/delivery-keys #:hash-key)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string)
  (:import-from #:koya-server/usecases/ports/keys
                #:create-management-key #:stored-management-keys #:import-management-key
                #:management-key-label #:list-management-keys #:delete-management-key
                #:space-for-management-key))
(in-package #:koya-server/infra/db/management-keys)

;;; Management keys authenticate the admin API (schema deploys, content and media
;;; management from a site's REPL or its startup) in place of the owner secret,
;;; which only logs into the admin UI. A key belongs to one space and reaches
;;; nothing outside it, so a site's .env can only affect its own space. Like
;;; delivery keys, only the SHA-256 is stored and the plaintext is shown once, on
;;; the space's keys page.
;;;
;;; Delivery keys live in a table of their own (db/delivery-keys). The two are the same
;;; shape today but not the same thing: one WHERE clause standing between a key
;;; that is handed to a front end and the right to deploy a schema is not a
;;; separation worth having.

(defmethod create-management-key (space &key (label ""))
  (let ((key (format nil "koya_mgmt_~a" (byte-array-to-hex-string (random-data 24))))
        (id (make-ulid)))
    (exec "INSERT INTO management_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
          id space (hash-key key) label (now-iso))
    (values key id)))

(defmethod list-management-keys (space)
  (mapcar (lambda (row) (list :id (col row "id") :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT id, label, created_at FROM management_keys WHERE space = ? ORDER BY created_at" space)))

(defmethod delete-management-key (space id)
  (exec "DELETE FROM management_keys WHERE space = ? AND id = ?" space id))

(defmethod management-key-label (key)
  (and (stringp key)
       (let ((row (fetch-one "SELECT label FROM management_keys WHERE key_hash = ?" (hash-key key))))
         (and row (col row "label")))))

(defmethod space-for-management-key (key)
  (and (stringp key)
       (let ((row (fetch-one "SELECT space FROM management_keys WHERE key_hash = ?" (hash-key key))))
         (and row (col row "space")))))

(defmethod stored-management-keys (space)
  (mapcar (lambda (row) (list :id (col row "id") :hash (col row "key_hash")
                              :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT * FROM management_keys WHERE space = ? ORDER BY created_at" space)))

(defmethod import-management-key (space &key id hash label created-at)
  (exec "INSERT INTO management_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
        id space hash (or label "") created-at))
