(defpackage #:koya-server/db/schema-store
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:col #:with-db-transaction)
  (:import-from #:koya/core/schema
                #:make-schema #:schema-webhooks #:schema-models
                #:webhook->jobject #:jobject->webhook #:slug-name-p
                #:model-name #:model-kind #:model->jobject #:jobject->model #:check-schema)
  (:import-from #:koya/core/json
                #:parse-json #:to-json)
  (:import-from #:koya/core/diff
                #:diff-schemas)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string)
  (:export #:load-schema
           #:save-schema
           #:list-spaces
           #:find-space
           #:create-space
           #:delete-space
           #:find-model
           #:space-webhooks
           #:space-webhook-secret
           #:rotate-webhook-secret))
(in-package #:koya-server/db/schema-store)

;;; The server keeps the deployed schema in the SPACES and MODELS tables. A model's
;;; definition is stored as its wire-format JSON, so the tables never change
;;; shape when the schema does.
;;;
;;; A space is made and deleted in the admin UI, never by a deploy: it owns the
;;; contents, media, keys and webhook secret, so its life is longer than any one
;;; schema. A deploy addresses one existing space and changes only its models and
;;; webhooks.

(defun load-space-models (space-name)
  (mapcar (lambda (row) (jobject->model (parse-json (col row "definition"))))
          (fetch "SELECT definition FROM models WHERE space = ? ORDER BY position, name" space-name)))

(defun load-schema (space-name)
  "The schema of SPACE-NAME -- its webhooks and models -- or NIL when no such space."
  (let ((row (first (fetch "SELECT webhooks FROM spaces WHERE name = ?" space-name))))
    (and row
         (make-schema :webhooks (coerce (parse-json (col row "webhooks")) 'list)
                      :models (load-space-models space-name)))))

(defun list-spaces ()
  "Every space as a plist (:name :models n), in display order."
  (mapcar (lambda (row)
            (list :name (col row "name") :models (col row "models")))
          (fetch "SELECT s.name, (SELECT COUNT(*) FROM models m WHERE m.space = s.name) AS models
                  FROM spaces s ORDER BY s.position, s.name")))

(defun find-space (name)
  "The space's name when it exists, NIL otherwise. Handlers use it to tell a
missing space from an empty one."
  (and (first (fetch "SELECT name FROM spaces WHERE name = ?" name)) name))

(defun space-webhooks (name)
  "The webhooks every model of the space fires. Read on its own, without the
models, because every content change needs them."
  (let ((row (first (fetch "SELECT webhooks FROM spaces WHERE name = ?" name))))
    (and row (map 'list #'jobject->webhook (parse-json (col row "webhooks"))))))

(defun find-model (space-name model-name)
  (let ((schema (load-schema space-name)))
    (and schema (koya/core/schema:schema-model schema model-name))))

(defun new-secret () (byte-array-to-hex-string (random-data 24)))

(defun space-webhook-secret (space-name)
  "The secret sent as X-KOYA-WEBHOOK-KEY with every webhook of SPACE-NAME."
  (let ((row (fetch "SELECT webhook_secret FROM spaces WHERE name = ?" space-name)))
    (and row (col (first row) "webhook_secret"))))

(defun rotate-webhook-secret (space-name)
  (let ((secret (new-secret)))
    (exec "UPDATE spaces SET webhook_secret = ? WHERE name = ?" secret space-name)
    secret))

(defun create-space (name)
  "Make a space. NAME is its id: it is in every URL and in the delivery API, so it
never changes. Returns the name, or signals on a bad or taken one."
  (let ((name (string-downcase (string-trim " " name))))
    (unless (slug-name-p name)
      (error "Space name ~s must be lowercase letters, digits and hyphens" name))
    (when (find-space name)
      (error "Space ~a already exists" name))
    (exec "INSERT INTO spaces (name, webhooks, webhook_secret, position, created_at)
           VALUES (?, '[]', ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM spaces), ?)"
          name (new-secret) (now-iso))
    name))

(defun delete-space (name)
  "Delete a space with everything in it: models, contents, media rows, keys and
the webhook log. The media files themselves are removed by the caller."
  (exec "DELETE FROM spaces WHERE name = ?" name))

(defun save-schema (space-name schema)
  "Replace the schema of SPACE-NAME with SCHEMA. Models that disappear are deleted
(their contents go with them). Returns the list of changes applied."
  (check-schema schema)
  (with-db-transaction
    (let* ((old (load-schema space-name))
           (changes (diff-schemas old schema)))
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
                      (to-json (model->jobject model)) position))
      changes)))
