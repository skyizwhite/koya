(defpackage #:koya-server/db/management-keys
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/db/api-keys
                #:hash-api-key)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string)
  (:export #:create-management-key
           #:list-management-keys
           #:delete-management-key
           #:management-key-p))
(in-package #:koya-server/db/management-keys)

;;; Management keys authenticate the admin API (schema deploys, content and media
;;; management from a site's REPL or its startup) in place of the owner secret,
;;; which now only logs into the admin UI. They are instance-wide: a schema deploy
;;; covers every space. Like delivery keys, only the SHA-256 is stored and the
;;; plaintext is shown once, on the settings page.

(defun create-management-key (&key (label ""))
  "Returns (values plaintext-key id)."
  (let ((key (format nil "koya_mgmt_~a" (byte-array-to-hex-string (random-data 24))))
        (id (make-ulid)))
    (exec "INSERT INTO management_keys (id, key_hash, label, created_at) VALUES (?, ?, ?, ?)"
          id (hash-api-key key) label (now-iso))
    (values key id)))

(defun list-management-keys ()
  "Plists (:id :label :created-at), oldest first."
  (mapcar (lambda (row) (list :id (col row "id") :label (col row "label") :created-at (col row "created_at")))
          (fetch "SELECT id, label, created_at FROM management_keys ORDER BY created_at")))

(defun delete-management-key (id)
  (exec "DELETE FROM management_keys WHERE id = ?" id))

(defun management-key-p (key)
  "True when KEY is a stored management key."
  (and (stringp key)
       (fetch-one "SELECT 1 FROM management_keys WHERE key_hash = ?" (hash-api-key key))
       t))
