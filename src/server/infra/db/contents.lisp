(defpackage #:koya-server/infra/db/contents
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection
                #:exec #:fetch #:fetch-one #:col #:with-db-transaction)
  (:import-from #:koya-server/infra/db/content-query #:build-where #:build-order-by)
  (:import-from #:koya-server/domain/query
                #:query-limit #:query-offset #:query-orders #:query-filters)
  (:import-from #:koya-server/domain/content
                #:make-content #:content-id #:content-published #:content-draft #:content-draft-key
                #:content-space #:content-model
                #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
                #:content-status)
  (:import-from #:koya/core/json
                #:parse-json #:to-json)
  (:import-from #:koya-server/usecases/ports/contents
                #:insert-content #:update-content #:delete-content #:get-content #:find-content
                #:find-contents-by-ids #:list-contents #:count-contents
                #:find-object-content #:unique-value-taken-p #:space-contents
                #:contents-mentioning))
(in-package #:koya-server/infra/db/contents)

;;; Content rows, the published and draft data stored as JSON. A row is written
;;; as the content it is handed; what a write makes of a content is the
;;; domain's, and its revision the use case's.

(defun row->content (row)
  (flet ((json (name) (let ((v (col row name))) (and v (parse-json v)))))
    (make-content :id (col row "id") :space (col row "space") :model (col row "model")
                  :published (json "published") :draft (json "draft")
                  :draft-key (col row "draft_key")
                  :created-at (col row "created_at") :updated-at (col row "updated_at")
                  :published-at (col row "published_at") :revised-at (col row "revised_at"))))

(defun json-column (value) (and value (to-json value)))

(defmethod get-content (id)
  (let ((row (fetch-one "SELECT * FROM contents WHERE id = ?" id)))
    (and row (row->content row))))

(defmethod find-contents-by-ids (space model ids)
  (let ((table (make-hash-table :test 'equal))
        (ids (remove-duplicates ids :test #'equal)))
    (when ids
      (dolist (row (apply #'fetch (format nil "SELECT * FROM contents WHERE space = ? AND model = ? AND id IN (~{~*?~^, ~})" ids)
                          space model ids))
        (let ((content (row->content row)))
          (setf (gethash (content-id content) table) content))))
    table))

(defmethod find-content (space model id)
  (let ((row (fetch-one "SELECT * FROM contents WHERE id = ? AND space = ? AND model = ?" id space model)))
    (and row (row->content row))))

(defmethod insert-content (content)
  (exec "INSERT INTO contents (id, space, model, status, published, draft, draft_key, created_at, updated_at, published_at, revised_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        (content-id content) (content-space content) (content-model content) (content-status content)
        (json-column (content-published content)) (json-column (content-draft content))
        (content-draft-key content)
        (content-created-at content) (content-updated-at content)
        (content-published-at content) (content-revised-at content)))

(defmethod update-content (content)
  (exec "UPDATE contents SET status = ?, published = ?, draft = ?, draft_key = ?, updated_at = ?,
           published_at = ?, revised_at = ? WHERE id = ?"
        (content-status content)
        (json-column (content-published content)) (json-column (content-draft content))
        (content-draft-key content) (content-updated-at content)
        (content-published-at content) (content-revised-at content)
        (content-id content)))

(defmethod delete-content (id)
  ;; its revisions go with it, ON DELETE CASCADE
  (exec "DELETE FROM contents WHERE id = ?" id))

(defmethod contents-mentioning (space needle &key exclude-id)
  (mapcar #'row->content
          (apply #'fetch (format nil "SELECT * FROM contents WHERE space = ?~:[~; AND id <> ?~]
                                        AND (published LIKE ? OR draft LIKE ?)"
                                 exclude-id)
                 space (append (and exclude-id (list exclude-id))
                               (let ((like (format nil "%~a%" needle))) (list like like))))))

(defmethod find-object-content (space model)
  (let ((row (fetch-one "SELECT * FROM contents WHERE space = ? AND model = ? ORDER BY created_at LIMIT 1" space model)))
    (and row (row->content row))))

(defun status-clause (status)
  (ecase status
    (:published "published IS NOT NULL")
    (:all "1 = 1")))

(defun data-column (status)
  (ecase status
    (:published "published")
    (:all "COALESCE(draft, published)")))

(defmethod list-contents (space model schema-model query &key (status :published) only-status)
  (let ((column (data-column status)))
    (multiple-value-bind (where-sql where-params) (build-where (query-filters query) schema-model column)
      (let* ((base (format nil "FROM contents WHERE space = ? AND model = ? AND ~a~@[~a~]~@[ AND ~a~]"
                           (status-clause status) (and only-status " AND status = ?") where-sql))
             (params (append (list space model) (and only-status (list only-status)) where-params))
             (total (col (apply #'fetch-one (format nil "SELECT COUNT(*) AS n ~a" base) params) "n"))
             (rows (apply #'fetch
                          (format nil "SELECT * ~a ORDER BY ~a LIMIT ? OFFSET ?"
                                  base (build-order-by (query-orders query) schema-model column))
                          ;; SQLite reads a negative LIMIT as none
                          (append params (list (or (query-limit query) -1) (query-offset query))))))
        (values (mapcar #'row->content rows) total)))))

(defmethod count-contents (space model)
  (col (fetch-one "SELECT COUNT(*) AS n FROM contents WHERE space = ? AND model = ?" space model) "n"))

(defmethod unique-value-taken-p (space model field value &key exclude-id)
  (let ((expr (format nil "json_extract(~~a, '$.~a')" field)))
    (and (fetch-one (format nil "SELECT 1 FROM contents WHERE space = ? AND model = ? AND id != ?
                                 AND (~a = ? OR ~a = ?) LIMIT 1"
                            (format nil expr "published") (format nil expr "draft"))
                    space model (or exclude-id "") value value)
         t)))

(defmethod space-contents (space)
  (mapcar #'row->content
          (fetch "SELECT * FROM contents WHERE space = ? ORDER BY created_at, id" space)))
