(defpackage #:koya-server/infra/db/contents
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection
                #:exec #:fetch #:fetch-one #:fetch-value #:col)
  (:import-from #:koya-server/infra/db/sql
                #:sql #:bound #:fragment #:all-of #:in-list #:like-pattern #:json-at)
  (:import-from #:koya-server/infra/db/content-query #:build-where #:build-order-by)
  (:import-from #:koya-server/domain/query
                #:query-limit #:query-offset #:query-orders #:query-filters #:query-search #:search-filters)
  (:import-from #:koya-server/domain/content
                #:make-content #:content-id #:content-published #:content-draft #:content-draft-key
                #:content-space #:content-model
                #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
                #:content-status #:content-published-p #:content-draft-p)
  (:import-from #:koya-core/json
                #:parse-json #:to-json)
  (:import-from #:koya-core/case
                #:jvalue->data #:data->jobject)
  (:import-from #:koya-server/domain/html #:data-text)
  (:import-from #:koya-server/usecases/ports/contents
                #:insert-content #:update-content #:delete-content #:find-content
                #:find-contents-by-ids #:find-contents-by-slug #:find-content-ids-by-slug #:list-contents #:count-contents
                #:find-object-content #:find-object-content-id #:unique-value-taken-p #:slug-taken-p #:space-contents #:model-contents
                #:contents-mentioning)
  (:export #:json-column #:text-column))
(in-package #:koya-server/infra/db/contents)

(defparameter +columns+
  (sql "id, space, model, status, published, draft, draft_key, created_at, updated_at, published_at, revised_at"))

(defun row->content (row)
  (flet ((json (name) (let ((v (col row name))) (and v (jvalue->data (parse-json v) :intern t)))))
    (make-content :id (col row "id") :space (col row "space") :model (col row "model")
                  :status (col row "status")
                  :published (json "published") :draft (json "draft")
                  :draft-key (col row "draft_key")
                  :created-at (col row "created_at") :updated-at (col row "updated_at")
                  :published-at (col row "published_at") :revised-at (col row "revised_at"))))

(defun json-column (data) (to-json (data->jobject data)))

(defun text-column (data) (json-column (data-text data)))

(defun version-columns (content)
  (let ((published (content-published-p content))
        (draft (content-draft-p content)))
    (list (and published (json-column (content-published content)))
          (and draft (json-column (content-draft content)))
          (and published (text-column (content-published content)))
          (and draft (text-column (content-draft content))))))

(defmethod find-contents-by-ids (space model ids)
  (let ((table (make-hash-table :test 'equal))
        (ids (remove-duplicates ids :test #'equal)))
    (when ids
      (dolist (row (fetch (fragment "SELECT ~a FROM contents WHERE space = ~a AND model = ~a AND id IN ~a"
                                    +columns+ (bound space) (bound model) (in-list ids))))
        (let ((content (row->content row)))
          (setf (gethash (content-id content) table) content))))
    table))

(defmethod find-content (space model id)
  (let ((row (fetch-one (fragment "SELECT ~a FROM contents WHERE id = ~a AND space = ~a AND model = ~a"
                                  +columns+ (bound id) (bound space) (bound model)))))
    (and row (row->content row))))

(defmethod insert-content (content published-slug draft-slug)
  (destructuring-bind (published draft published-text draft-text) (version-columns content)
    (and (fetch-one "INSERT INTO contents (id, space, model, status, published, draft, draft_key, created_at, updated_at, published_at, revised_at,
                                           published_text, draft_text, published_slug, draft_slug)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                     ON CONFLICT (space, id) DO NOTHING
                     RETURNING id"
                    (content-id content) (content-space content) (content-model content) (content-status content)
                    published draft
                    (content-draft-key content)
                    (content-created-at content) (content-updated-at content)
                    (content-published-at content) (content-revised-at content)
                    published-text draft-text
                    published-slug draft-slug)
         t)))

(defmethod update-content (content published-slug draft-slug)
  (destructuring-bind (published draft published-text draft-text) (version-columns content)
    (exec "UPDATE contents SET status = ?, published = ?, draft = ?, draft_key = ?, updated_at = ?,
             published_at = ?, revised_at = ?, published_text = ?, draft_text = ?, published_slug = ?, draft_slug = ?
           WHERE space = ? AND id = ?"
          (content-status content)
          published draft
          (content-draft-key content) (content-updated-at content)
          (content-published-at content) (content-revised-at content)
          published-text draft-text
          published-slug draft-slug
          (content-space content) (content-id content))))

(defmethod delete-content (space id)
  (exec "DELETE FROM contents WHERE space = ? AND id = ?" space id))

(defmethod contents-mentioning (space needle &key exclude-id)
  (let ((like (like-pattern needle)))
    (mapcar #'row->content
            (fetch (fragment "SELECT ~a FROM contents WHERE ~a"
                             +columns+
                             (all-of (list (sql "space = ?" space)
                                           (and exclude-id (sql "id <> ?" exclude-id))
                                           (sql "(published LIKE ? ESCAPE '\\' OR draft LIKE ? ESCAPE '\\')" like like))))))))

(defun by-slug (columns space model slug)
  (fetch (fragment "SELECT ~a FROM contents WHERE space = ~a AND model = ~a AND (published_slug = ~a OR draft_slug = ~a)"
                   columns (bound space) (bound model) (bound slug) (bound slug))))

(defun object-row (columns space model)
  (fetch-one (fragment "SELECT ~a FROM contents WHERE space = ~a AND model = ~a ORDER BY created_at LIMIT 1"
                       columns (bound space) (bound model))))

(defmethod find-contents-by-slug (space model slug)
  (mapcar #'row->content (by-slug +columns+ space model slug)))

(defmethod find-content-ids-by-slug (space model slug)
  (mapcar (lambda (row) (col row "id")) (by-slug (sql "id") space model slug)))

(defmethod find-object-content-id (space model)
  (let ((row (object-row (sql "id") space model)))
    (and row (col row "id"))))

(defmethod find-object-content (space model)
  (let ((row (object-row +columns+ space model)))
    (and row (row->content row))))

(defun status-clause (status)
  (ecase status
    (:published (sql "published IS NOT NULL"))
    (:all nil)))

(defun data-column (status)
  (ecase status
    (:published (values (sql "published") (sql "published_text")))
    (:all (values (sql "COALESCE(draft, published)") (sql "COALESCE(draft_text, published_text)")))))

(defmethod list-contents (space model schema-model query &key (status :published) only-status)
  (multiple-value-bind (column text-column) (data-column status)
    (let* ((where (all-of (list (sql "space = ? AND model = ?" space model)
                                (status-clause status)
                                (and only-status (sql "status = ?" only-status))
                                (build-where (query-filters query) schema-model column
                                             :and (and (query-search query)
                                                       (search-filters schema-model (query-search query)))
                                             :text-column text-column))))
           (total (fetch-value (fragment "SELECT COUNT(*) FROM contents WHERE ~a" where)))
           (rows (fetch (fragment "SELECT ~a FROM contents WHERE ~a ORDER BY ~a LIMIT ~a OFFSET ~a"
                                  +columns+ where (build-order-by (query-orders query) schema-model column)
                                  (bound (or (query-limit query) -1)) (bound (query-offset query))))))
      (values (mapcar #'row->content rows) total))))

(defmethod count-contents (space model)
  (fetch-value "SELECT COUNT(*) FROM contents WHERE space = ? AND model = ?" space model))

(defmethod unique-value-taken-p (space model field value &key exclude-id)
  (and (fetch-one (fragment "SELECT 1 FROM contents WHERE space = ~a AND model = ~a AND id != ~a
                               AND (~a = ~a OR ~a = ~a) LIMIT 1"
                            (bound space) (bound model) (bound (or exclude-id ""))
                            (json-at (sql "published") field) (bound value)
                            (json-at (sql "draft") field) (bound value)))
       t))

(defmethod slug-taken-p (space model slug &key exclude-id)
  (and (fetch-one "SELECT 1 FROM contents WHERE space = ? AND model = ? AND id != ?
                     AND (published_slug = ? OR draft_slug = ?) LIMIT 1"
                  space model (or exclude-id "") slug slug)
       t))

(defmethod model-contents (space model)
  (mapcar #'row->content
          (fetch (fragment "SELECT ~a FROM contents WHERE space = ~a AND model = ~a ORDER BY created_at, rowid"
                           +columns+ (bound space) (bound model)))))

(defmethod space-contents (space)
  (mapcar #'row->content
          (fetch (fragment "SELECT ~a FROM contents WHERE space = ~a ORDER BY created_at, rowid"
                           +columns+ (bound space)))))
