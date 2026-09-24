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

(defun create-management-key (space &key (label ""))
  "Create a key for SPACE. Returns (values plaintext-key id)."
  (let ((key (format nil "koya_mgmt_~a" (byte-array-to-hex-string (random-data 24))))
        (id (make-ulid)))
    (exec "INSERT INTO management_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
          id space (hash-key key) label (now-iso))
    (values key id)))

(defun list-management-keys (space)
  "Plists (:id :label :created-at) of the keys of SPACE, oldest first."
  (mapcar (lambda (row) (list :id (col row "id") :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT id, label, created_at FROM management_keys WHERE space = ? ORDER BY created_at" space)))

(defun delete-management-key (space id)
  (exec "DELETE FROM management_keys WHERE space = ? AND id = ?" space id))

(defun management-key-label (key)
  "The label of the management key KEY, or NIL when it is not one. An unlabelled
key answers with the empty string it was made with."
  (and (stringp key)
       (let ((row (fetch-one "SELECT label FROM management_keys WHERE key_hash = ?" (hash-key key))))
         (and row (col row "label")))))

(defun space-for-management-key (key)
  "The space KEY manages, or NIL when it is not a management key."
  (and (stringp key)
       (let ((row (fetch-one "SELECT space FROM management_keys WHERE key_hash = ?" (hash-key key))))
         (and row (col row "space")))))

(defun stored-management-keys (space)
  "Plists (:id :hash :label :created-at) of the keys of SPACE as stored, for an
export: the hash is all there is, and all a moved key needs."
  (mapcar (lambda (row) (list :id (col row "id") :hash (col row "key_hash")
                              :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT * FROM management_keys WHERE space = ? ORDER BY created_at" space)))

(defun import-management-key (space &key id hash label created-at)
  (exec "INSERT INTO management_keys (id, space, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?)"
        id space hash (or label "") created-at))
