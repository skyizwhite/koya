(defpackage #:koya-server/infra/db/schema-store
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:*db* #:exec #:fetch #:col #:with-db #:with-db-transaction)
  (:import-from #:koya/core/schema
                #:make-schema #:schema-webhooks #:schema-models #:webhook->jobject
                #:jobject->webhook #:model-name #:model-kind #:model->jobject #:jobject->model
                #:model-forget-renames #:schema-model)
  (:import-from #:koya/core/json
                #:parse-json #:to-json)
  (:import-from #:koya-server/infra/db/schema-deploys #:record-deploy)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string)
  (:import-from #:koya-server/usecases/ports/spaces
                #:load-schema #:save-schema #:list-spaces #:find-space #:insert-space
                #:delete-space #:find-model #:space-webhooks #:space-webhook-secret
                #:rotate-webhook-secret #:set-webhook-secret))
(in-package #:koya-server/infra/db/schema-store)

;;; The server keeps the deployed schema in the SPACES and MODELS tables. A model's
;;; definition is stored as its wire-format JSON, so the tables never change
;;; shape when the schema does.
;;;
;;; A space is made and deleted in the admin UI, never by a deploy: it owns the
;;; contents, media, keys and webhook secret, so its life is longer than any one
;;; schema. A deploy addresses one existing space and changes only its models and
;;; webhooks.
;;;
;;; A schema is read from its rows once and kept until a deploy or a deletion
;;; replaces it: every content delivered, every reference resolved and every
;;; label drawn asks for a model, and parsing the models each time was most of
;;; the work of a page. The cache is the connection's, so a test that opens a
;;; fresh database starts empty.

(defvar *schemas* (cons nil (make-hash-table :test 'equal))
  "(connection . hash of space name -> schema, or :none for a name that is no space).")

(defun schema-cache ()
  (unless (eq (car *schemas*) *db*)
    (setf *schemas* (cons *db* (make-hash-table :test 'equal))))
  (cdr *schemas*))

(defun forget-schema (space-name)
  (with-db (remhash space-name (schema-cache))))

(defun load-space-models (space-name)
  (mapcar (lambda (row) (jobject->model (parse-json (col row "definition"))))
          (fetch "SELECT definition FROM models WHERE space = ? ORDER BY position, name" space-name)))

(defun read-schema (space-name)
  (let ((row (first (fetch "SELECT webhooks FROM spaces WHERE name = ?" space-name))))
    (and row
         (make-schema :webhooks (coerce (parse-json (col row "webhooks")) 'list)
                      :models (load-space-models space-name)))))

(defmethod load-schema (space-name)
  (with-db
    (let* ((cache (schema-cache))
           (schema (or (gethash space-name cache)
                       (setf (gethash space-name cache) (or (read-schema space-name) :none)))))
      (and (not (eq schema :none)) schema))))

(defmethod list-spaces ()
  (mapcar (lambda (row)
            (list :name (col row "name") :models (col row "models")))
          (fetch "SELECT s.name, (SELECT COUNT(*) FROM models m WHERE m.space = s.name) AS models
                  FROM spaces s ORDER BY s.position, s.name")))

(defmethod find-space (name)
  (and (first (fetch "SELECT name FROM spaces WHERE name = ?" name)) name))

(defmethod space-webhooks (name)
  (let ((row (first (fetch "SELECT webhooks FROM spaces WHERE name = ?" name))))
    (and row (map 'list #'jobject->webhook (parse-json (col row "webhooks"))))))

(defmethod find-model (space-name model-name)
  (let ((schema (load-schema space-name)))
    (and schema (schema-model schema model-name))))

(defun new-secret () (byte-array-to-hex-string (random-data 24)))

(defmethod space-webhook-secret (space-name)
  (let ((row (fetch "SELECT webhook_secret FROM spaces WHERE name = ?" space-name)))
    (and row (col (first row) "webhook_secret"))))

(defmethod rotate-webhook-secret (space-name)
  (let ((secret (new-secret)))
    (exec "UPDATE spaces SET webhook_secret = ? WHERE name = ?" secret space-name)
    secret))

(defmethod set-webhook-secret (space-name secret)
  (exec "UPDATE spaces SET webhook_secret = ? WHERE name = ?" secret space-name))

(defmethod insert-space (name)
  (exec "INSERT INTO spaces (name, webhooks, webhook_secret, position, created_at)
         VALUES (?, '[]', ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM spaces), ?)"
        name (new-secret) (now-iso))
  (forget-schema name)
  name)

(defmethod delete-space (name)
  (exec "DELETE FROM spaces WHERE name = ?" name)
  (forget-schema name))

;;; Renames. A :WAS matched by the diff is carried through to the stored content
;;; in the same transaction as the schema write.

(defun rename-model-rows (space from to)
  "Move a model's row and its contents from FROM to TO. The contents move before
the old row goes: they reference it ON DELETE CASCADE."
  (exec "INSERT INTO models (space, name, kind, definition, position)
         SELECT space, ?, kind, definition, position FROM models WHERE space = ? AND name = ?"
        to space from)
  (exec "UPDATE contents SET model = ? WHERE space = ? AND model = ?" to space from)
  (exec "DELETE FROM models WHERE space = ? AND name = ?" space from))

(defun rename-key (object from to)
  "Move key FROM to TO in OBJECT, if it holds one. Returns true when it changed."
  (multiple-value-bind (value presentp) (gethash from object)
    (when presentp
      (remhash from object)
      (setf (gethash to object) value)
      t)))

(defun rename-content-field (space model from to)
  "Rewrite the key FROM to TO in the published data, the draft and the revisions
of every content of MODEL."
  (dolist (row (fetch "SELECT id, published, draft FROM contents WHERE space = ? AND model = ?"
                      space model))
    (let* ((published (let ((v (col row "published"))) (and v (parse-json v))))
           (draft (let ((v (col row "draft"))) (and v (parse-json v))))
           (in-published (and published (rename-key published from to)))
           (in-draft (and draft (rename-key draft from to))))
      (when (or in-published in-draft)
        (exec "UPDATE contents SET published = ?, draft = ? WHERE id = ?"
              (and published (to-json published)) (and draft (to-json draft)) (col row "id")))))
  ;; the same field in the history, so an old version still restores into it
  (dolist (row (fetch "SELECT r.id, r.data FROM content_revisions r JOIN contents c ON c.id = r.content_id
                        WHERE c.space = ? AND c.model = ?"
                      space model))
    (let ((data (parse-json (col row "data"))))
      (when (rename-key data from to)
        (exec "UPDATE content_revisions SET data = ? WHERE id = ?" (to-json data) (col row "id"))))))

(defun apply-renames (space-name changes)
  "Carry out a deploy's renames. Model renames come first in CHANGES, so a field
rename names its model by the new name."
  (dolist (change changes)
    (case (getf change :op)
      (:rename-model (rename-model-rows space-name (getf change :from) (getf change :model)))
      (:rename-field (rename-content-field space-name (getf change :model)
                                           (getf change :from) (getf change :field))))))

(defmethod save-schema (space-name schema changes &key (by ""))
  (with-db-transaction
    (progn
      ;; first, and again once written: what a rename reads in between must be
      ;; the rows, and a transaction that rolls back must leave the cache empty
      (forget-schema space-name)
      (apply-renames space-name changes)
      ;; in the transaction: a deploy that rolls back must not be in the log
      (record-deploy space-name changes :by by)
      (exec "UPDATE spaces SET webhooks = ? WHERE name = ?"
            (to-json (map 'vector #'webhook->jobject (schema-webhooks schema))) space-name)
      (let ((keep (mapcar #'model-name (schema-models schema))))
        (dolist (row (fetch "SELECT name FROM models WHERE space = ?" space-name))
          (unless (member (col row "name") keep :test #'string=)
            (exec "DELETE FROM models WHERE space = ? AND name = ?" space-name (col row "name")))))
      (loop :for model :in (schema-models schema)
            :for position :from 0
            :do (exec "INSERT INTO models (space, name, kind, definition, position) VALUES (?, ?, ?, ?, ?)
                       ON CONFLICT(space, name) DO UPDATE SET kind = excluded.kind,
                         definition = excluded.definition, position = excluded.position"
                      space-name (model-name model) (string-downcase (symbol-name (model-kind model)))
                      (to-json (model->jobject (model-forget-renames model))) position))
      (forget-schema space-name))))
