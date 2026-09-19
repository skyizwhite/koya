(defpackage #:koya-server/db/schema-store
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:col #:with-db-transaction)
  (:import-from #:koya/core/schema
                #:make-schema #:make-space #:schema-spaces #:space-name #:space-webhooks #:space-models
                #:model-name #:model-kind #:model->jobject #:jobject->model #:check-schema)
  (:import-from #:koya/core/json
                #:parse-json #:to-json)
  (:import-from #:koya/core/diff
                #:diff-schemas)
  (:import-from #:koya/core/time
                #:now-iso)
  (:export #:load-schema
           #:save-schema
           #:find-space
           #:find-model))
(in-package #:koya-server/db/schema-store)

;;; The server keeps the pushed schema in the SPACES and MODELS tables. A model's
;;; definition is stored as its wire-format JSON, so the tables never change
;;; shape when the schema does.

(defun load-space-models (space-name)
  (mapcar (lambda (row) (jobject->model (parse-json (col row "definition"))))
          (fetch "SELECT definition FROM models WHERE space = ? ORDER BY position, name" space-name)))

(defun load-schema ()
  "Read the whole schema from the database."
  (make-schema
   (mapcar (lambda (row)
             (let ((name (col row "name")))
               (make-space name
                           :webhooks (coerce (parse-json (col row "webhooks")) 'list)
                           :models (load-space-models name))))
           (fetch "SELECT name, webhooks FROM spaces ORDER BY position, name"))))

(defun find-space (name)
  (koya/core/schema:schema-space (load-schema) name))

(defun find-model (space-name model-name)
  (let ((space (find-space space-name)))
    (and space (koya/core/schema:space-model space model-name))))

(defun save-space (space position now)
  (exec "INSERT INTO spaces (name, webhooks, position, created_at) VALUES (?, ?, ?, ?)
         ON CONFLICT(name) DO UPDATE SET webhooks = excluded.webhooks, position = excluded.position"
        (space-name space) (to-json (coerce (space-webhooks space) 'vector)) position now)
  (let ((keep (mapcar #'model-name (space-models space))))
    (dolist (row (fetch "SELECT name FROM models WHERE space = ?" (space-name space)))
      (unless (member (col row "name") keep :test #'string=)
        (exec "DELETE FROM models WHERE space = ? AND name = ?" (space-name space) (col row "name")))))
  (loop :for model :in (space-models space)
        :for position :from 0
        :do (exec "INSERT INTO models (space, name, kind, definition, position) VALUES (?, ?, ?, ?, ?)
                   ON CONFLICT(space, name) DO UPDATE SET kind = excluded.kind,
                     definition = excluded.definition, position = excluded.position"
                  (space-name space) (model-name model) (string-downcase (symbol-name (model-kind model)))
                  (to-json (model->jobject model)) position)))

(defun save-schema (schema)
  "Replace the stored schema with SCHEMA. Spaces and models that disappear are
deleted (contents of deleted models go with them). Returns the list of changes applied."
  (check-schema schema)
  (with-db-transaction
    (let* ((old (load-schema))
           (changes (diff-schemas old schema))
           (now (now-iso))
           (keep (mapcar #'space-name (schema-spaces schema))))
      (dolist (old-space (schema-spaces old))
        (unless (member (space-name old-space) keep :test #'string=)
          (exec "DELETE FROM spaces WHERE name = ?" (space-name old-space))))
      (loop :for space :in (schema-spaces schema)
            :for position :from 0
            :do (save-space space position now))
      changes)))
