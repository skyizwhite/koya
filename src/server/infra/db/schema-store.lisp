(defpackage #:koya-server/infra/db/schema-store
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection
                #:*db* #:*on-rollback* #:exec #:fetch #:col #:with-db #:with-db-transaction)
  (:import-from #:koya-core/schema
                #:make-schema #:schema-webhooks #:schema-models #:webhook->jobject
                #:jobject->webhook #:model-name #:model-kind #:model->jobject #:jobject->model
                #:model-forget-renames #:schema-model #:schema-custom-fields
                #:custom-field->jobject #:jobject->custom-field #:field-path-parts)
  (:import-from #:koya-core/json
                #:parse-json #:to-json #:json-array-p)
  (:import-from #:koya-server/infra/db/schema-deploys #:record-deploy)
  (:import-from #:koya-server/infra/db/contents #:text-column)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-server/usecases/ports/spaces
                #:load-schema #:save-schema #:list-spaces #:find-space #:insert-space
                #:delete-space #:find-model #:space-webhooks #:space-webhook-secret
                #:set-webhook-secret))
(in-package #:koya-server/infra/db/schema-store)

(defvar *schemas* (cons nil (make-hash-table :test 'equal)))

(defun schema-cache ()
  (unless (eq (car *schemas*) *db*)
    (setf *schemas* (cons *db* (make-hash-table :test 'equal))))
  (cdr *schemas*))

(defun forget-schema (space-name)
  (with-db (remhash space-name (schema-cache))))

(defun forget-schemas ()
  (with-db (clrhash (schema-cache))))

(pushnew 'forget-schemas *on-rollback*)

(defun load-space-models (space-name)
  (mapcar (lambda (row) (jobject->model (parse-json (col row "definition"))))
          (fetch "SELECT definition FROM models WHERE space = ? ORDER BY position, name" space-name)))

(defun read-schema (space-name)
  (let ((row (first (fetch "SELECT webhooks, custom_fields FROM spaces WHERE name = ?" space-name))))
    (and row
         (make-schema :webhooks (coerce (parse-json (col row "webhooks")) 'list)
                      :custom-fields (map 'list #'jobject->custom-field (parse-json (col row "custom_fields")))
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

(defmethod space-webhook-secret (space-name)
  (let ((row (fetch "SELECT webhook_secret FROM spaces WHERE name = ?" space-name)))
    (and row (col (first row) "webhook_secret"))))

(defmethod set-webhook-secret (space-name secret)
  (exec "UPDATE spaces SET webhook_secret = ? WHERE name = ?" secret space-name))

(defmethod insert-space (name webhook-secret)
  (exec "INSERT INTO spaces (name, webhooks, webhook_secret, position, created_at)
         VALUES (?, '[]', ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM spaces), ?)"
        name webhook-secret (now-iso))
  (forget-schema name)
  name)

(defmethod delete-space (name)
  (exec "DELETE FROM spaces WHERE name = ?" name)
  (forget-schema name))

(defun rename-model-rows (space from to)
  (exec "INSERT INTO models (space, name, kind, definition, position)
         SELECT space, ?, kind, definition, position FROM models WHERE space = ? AND name = ?"
        to space from)
  (exec "UPDATE contents SET model = ? WHERE space = ? AND model = ?" to space from)
  (exec "DELETE FROM models WHERE space = ? AND name = ?" space from))

(defun rewrite-content-data (space model fn)
  (dolist (row (fetch "SELECT id, published, draft FROM contents WHERE space = ? AND model = ?" space model))
    (let* ((published (let ((v (col row "published"))) (and v (parse-json v))))
           (draft (let ((v (col row "draft"))) (and v (parse-json v))))
           (in-published (and published (funcall fn published)))
           (in-draft (and draft (funcall fn draft))))
      (when (or in-published in-draft)
        (exec "UPDATE contents SET published = ?, draft = ?, published_text = ?, draft_text = ? WHERE space = ? AND id = ?"
              (and published (to-json published)) (and draft (to-json draft))
              (text-column published) (text-column draft) space (col row "id")))))
  (dolist (row (fetch "SELECT r.id, r.data FROM content_revisions r
                        JOIN contents c ON c.space = r.space AND c.id = r.content_id
                        WHERE c.space = ? AND c.model = ?"
                      space model))
    (let ((data (parse-json (col row "data"))))
      (when (funcall fn data)
        (exec "UPDATE content_revisions SET data = ? WHERE id = ?" (to-json data) (col row "id"))))))

(defun rename-key (object from to)
  (multiple-value-bind (value presentp) (gethash from object)
    (when presentp
      (remhash from object)
      (setf (gethash to object) value)
      t)))

(defun rename-content-field (space model from to)
  (rewrite-content-data space model (lambda (data) (rename-key data from to))))

(defun drop-inner-key (data outer kind inner)
  (let ((value (and data (gethash outer data))))
    (cond ((and (null kind) (hash-table-p value))
           (remhash inner value))
          ((and kind (json-array-p value))
           (let ((dropped nil))
             (loop :for row :across value
                   :when (and (hash-table-p row) (equal (gethash "fieldId" row) kind) (remhash inner row))
                     :do (setf dropped t))
             dropped)))))

(defun drop-inner-field (space model outer kind inner)
  (rewrite-content-data space model (lambda (data) (drop-inner-key data outer kind inner))))

(defun drop-content-field (space model field)
  (multiple-value-bind (outer kind inner) (field-path-parts field)
    (if inner
        (drop-inner-field space model outer kind inner)
        (drop-top-field space model field))))

(defun drop-top-field (space model field)
  (let ((path (format nil "$.~a" field)))
    (exec "UPDATE contents SET published = json_remove(published, ?), draft = json_remove(draft, ?),
                                published_text = json_remove(published_text, ?), draft_text = json_remove(draft_text, ?)
           WHERE space = ? AND model = ?"
          path path path path space model)
    (exec "UPDATE content_revisions SET data = json_remove(data, ?)
           WHERE space = ? AND content_id IN (SELECT id FROM contents WHERE space = ? AND model = ?)"
          path space space model)))

(defun drop-model-contents (space model)
  (exec "DELETE FROM contents WHERE space = ? AND model = ?" space model))

(defun apply-changes (space-name changes)
  (dolist (change changes)
    (case (getf change :op)
      (:rename-model (rename-model-rows space-name (getf change :from) (getf change :model)))
      (:rename-field (rename-content-field space-name (getf change :model)
                                           (getf change :from) (getf change :field)))
      ((:remove-field :change-field-type)
       (drop-content-field space-name (getf change :model) (getf change :field)))
      (:change-kind (drop-model-contents space-name (getf change :model))))))

(defmethod save-schema (space-name schema changes &key (by ""))
  (with-db-transaction
    (progn
      (forget-schema space-name)
      (apply-changes space-name changes)
      (record-deploy space-name changes :by by)
      (exec "UPDATE spaces SET webhooks = ?, custom_fields = ? WHERE name = ?"
            (to-json (map 'vector #'webhook->jobject (schema-webhooks schema)))
            (to-json (map 'vector #'custom-field->jobject (schema-custom-fields schema)))
            space-name)
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
