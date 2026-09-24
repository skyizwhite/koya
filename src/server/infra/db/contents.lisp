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
                #:status-of)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:koya-server/infra/db/content-revisions #:record-revision)
  (:import-from #:koya/core/json
                #:parse-json #:to-json)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string)
  (:import-from #:koya-server/usecases/ports/contents
                #:create-content #:save-draft #:publish-content #:unpublish-content
                #:discard-draft #:delete-content #:get-content #:find-content
                #:find-contents-by-ids #:list-contents #:count-contents #:ensure-draft-key
                #:find-object-content #:unique-value-taken-p #:space-contents #:import-content
                #:contents-mentioning))
(in-package #:koya-server/infra/db/contents)

;;; Content rows, the published and draft data stored as JSON.
;;;
;;; Every write records a revision in the same transaction (content-revisions);
;;; BY names who made it, as usecases/actor's *ACTOR* does. IMPORT-CONTENT is
;;; the exception: an imported content brings its own history.

(defun row->content (row)
  (flet ((json (name) (let ((v (col row name))) (and v (parse-json v)))))
    (make-content :id (col row "id") :space (col row "space") :model (col row "model")
                  :status (col row "status") :published (json "published") :draft (json "draft")
                  :draft-key (col row "draft_key")
                  :created-at (col row "created_at") :updated-at (col row "updated_at")
                  :published-at (col row "published_at") :revised-at (col row "revised_at"))))

(defun new-draft-key ()
  (byte-array-to-hex-string (random-data 16)))

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

(defmethod create-content (space model data &key publish (id (make-ulid))
                                                 created-at updated-at published-at revised-at by)
  (let ((now (now-iso)))
    (with-db-transaction
      (exec "INSERT INTO contents (id, space, model, status, published, draft, draft_key, created_at, updated_at, published_at, revised_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            id space model (if publish "published" "draft")
            (and publish (to-json data)) (and (not publish) (to-json data))
            (and (not publish) (new-draft-key))
            (or created-at now) (or updated-at now)
            (and publish (or published-at now)) (and publish (or revised-at now)))
      (record-revision id (if publish "publish" "draft") data :by by))
    (get-content id)))

(defmethod save-draft (id data &key by)
  (let ((content (or (get-content id) (error "content ~a not found" id))))
    (with-db-transaction
      (exec "UPDATE contents SET draft = ?, draft_key = ?, status = ?, updated_at = ? WHERE id = ?"
            (to-json data) (new-draft-key) (status-of (content-published content) t) (now-iso) id)
      (record-revision id "draft" data :by by))
    (get-content id)))

(defmethod publish-content (id &optional data &key published-at by)
  (let* ((content (or (get-content id) (error "content ~a not found" id)))
         (data (or data (content-draft content) (content-published content)))
         (now (now-iso)))
    (with-db-transaction
      (exec "UPDATE contents SET published = ?, draft = NULL, draft_key = NULL, status = 'published', updated_at = ?,
               published_at = COALESCE(?, published_at, ?), revised_at = ? WHERE id = ?"
            (to-json data) now published-at now now id)
      (record-revision id "publish" data :by by))
    (get-content id)))

(defmethod unpublish-content (id &key by)
  (let* ((content (or (get-content id) (error "content ~a not found" id)))
         (data (or (content-draft content) (content-published content))))
    (with-db-transaction
      (exec "UPDATE contents SET published = NULL, draft = ?, draft_key = ?, status = 'draft', updated_at = ?, published_at = NULL WHERE id = ?"
            (to-json data) (new-draft-key) (now-iso) id)
      ;; unpublishing what was never live changes nothing the history tells
      (when (content-published content)
        (record-revision id "unpublish" data :by by)))
    (get-content id)))

(defmethod discard-draft (id &key by)
  (let ((content (or (get-content id) (error "content ~a not found" id))))
    (unless (content-published content) (error "content ~a is not published; delete it instead" id))
    (with-db-transaction
      (exec "UPDATE contents SET draft = NULL, draft_key = NULL, status = 'published', updated_at = ? WHERE id = ?"
            (now-iso) id)
      (when (content-draft content)
        (record-revision id "discard" (content-published content) :by by)))
    (get-content id)))

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

(defmethod ensure-draft-key (id)
  (let ((content (or (get-content id) (error "content ~a not found" id))))
    (or (content-draft-key content)
        (let ((key (new-draft-key)))
          (exec "UPDATE contents SET draft_key = ? WHERE id = ?" key id)
          key))))

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

(defmethod import-content (content)
  (exec "INSERT INTO contents (id, space, model, status, published, draft, draft_key, created_at, updated_at, published_at, revised_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        (content-id content) (content-space content) (content-model content)
        (status-of (content-published content) (content-draft content))
        (let ((v (content-published content))) (and v (to-json v)))
        (let ((v (content-draft content))) (and v (to-json v)))
        (content-draft-key content)
        (content-created-at content) (content-updated-at content)
        (content-published-at content) (content-revised-at content)))
