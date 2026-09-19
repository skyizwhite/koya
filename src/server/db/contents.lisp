(defpackage #:koya-server/db/contents
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:fetch-one #:col #:with-db-transaction)
  (:import-from #:koya-server/lib/query
                #:query-limit #:query-offset #:query-orders #:query-filters
                #:build-where #:build-order-by)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:koya/core/json
                #:parse-json #:to-json)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string)
  (:export #:content-id #:content-space #:content-model #:content-status
           #:content-published #:content-draft #:content-draft-key
           #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
           #:content-data
           #:create-content
           #:save-draft
           #:publish-content
           #:unpublish-content
           #:delete-content
           #:get-content
           #:find-content
           #:list-contents
           #:count-contents
           #:ensure-draft-key
           #:find-object-content
           #:unique-value-taken-p))
(in-package #:koya-server/db/contents)

;;; Content rows. PUBLISHED and DRAFT are JSON objects (hash tables) or NIL.
;;; status is one of "draft", "published", "published+draft".

(defstruct content
  id space model status published draft draft-key created-at updated-at published-at revised-at)

(defun row->content (row)
  (flet ((json (name) (let ((v (col row name))) (and v (parse-json v)))))
    (make-content :id (col row "id") :space (col row "space") :model (col row "model")
                  :status (col row "status") :published (json "published") :draft (json "draft")
                  :draft-key (col row "draft_key")
                  :created-at (col row "created_at") :updated-at (col row "updated_at")
                  :published-at (col row "published_at") :revised-at (col row "revised_at"))))

(defun content-data (content &key draft)
  "The published data, or with DRAFT the draft data falling back to published."
  (if draft
      (or (content-draft content) (content-published content))
      (content-published content)))

(defun status-for (published draft)
  (cond ((and published draft) "published+draft")
        (published "published")
        (t "draft")))

(defun get-content (id)
  (let ((row (fetch-one "SELECT * FROM contents WHERE id = ?" id)))
    (and row (row->content row))))

(defun find-content (space model id)
  (let ((row (fetch-one "SELECT * FROM contents WHERE id = ? AND space = ? AND model = ?" id space model)))
    (and row (row->content row))))

(defun create-content (space model data &key publish (id (make-ulid)) published-at)
  "Insert DATA as a new content. With PUBLISH it is published immediately (at
PUBLISHED-AT when given, for imports), otherwise saved as a draft."
  (let ((now (now-iso)))
    (exec "INSERT INTO contents (id, space, model, status, published, draft, created_at, updated_at, published_at, revised_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
          id space model (if publish "published" "draft")
          (and publish (to-json data)) (and (not publish) (to-json data))
          now now (and publish (or published-at now)) (and publish now))
    (get-content id)))

(defun save-draft (id data)
  "Replace the draft of content ID with DATA."
  (let ((content (or (get-content id) (error "content ~a not found" id))))
    (exec "UPDATE contents SET draft = ?, status = ?, updated_at = ? WHERE id = ?"
          (to-json data) (status-for (content-published content) t) (now-iso) id)
    (get-content id)))

(defun publish-content (id &optional data &key published-at)
  "Publish DATA (or the current draft, or re-publish the published data) and clear the draft.
PUBLISHED-AT overrides the publish date; otherwise the first publish date is kept."
  (let* ((content (or (get-content id) (error "content ~a not found" id)))
         (data (or data (content-draft content) (content-published content)))
         (now (now-iso)))
    (exec "UPDATE contents SET published = ?, draft = NULL, status = 'published', updated_at = ?,
             published_at = COALESCE(?, published_at, ?), revised_at = ? WHERE id = ?"
          (to-json data) now published-at now now id)
    (get-content id)))

(defun unpublish-content (id)
  "Take content ID off the delivery API, keeping its data as a draft."
  (let* ((content (or (get-content id) (error "content ~a not found" id)))
         (data (or (content-draft content) (content-published content))))
    (exec "UPDATE contents SET published = NULL, draft = ?, status = 'draft', updated_at = ?, published_at = NULL WHERE id = ?"
          (to-json data) (now-iso) id)
    (get-content id)))

(defun delete-content (id)
  (exec "DELETE FROM contents WHERE id = ?" id))

(defun ensure-draft-key (id)
  "Return the draft key of content ID, generating one on first use."
  (let ((content (or (get-content id) (error "content ~a not found" id))))
    (or (content-draft-key content)
        (let ((key (byte-array-to-hex-string (random-data 16))))
          (exec "UPDATE contents SET draft_key = ? WHERE id = ?" key id)
          key))))

(defun find-object-content (space model)
  "The single content row of an object-kind model, or NIL."
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

(defun list-contents (space model schema-model query &key (status :published))
  "Return (values contents total-count) for QUERY. STATUS :published restricts to
published data (delivery API); :all lists everything using draft data when present (admin)."
  (let ((column (data-column status)))
    (multiple-value-bind (where-sql where-params) (build-where (query-filters query) schema-model column)
      (let* ((base (format nil "FROM contents WHERE space = ? AND model = ? AND ~a~@[ AND ~a~]"
                           (status-clause status) where-sql))
             (params (append (list space model) where-params))
             (total (col (apply #'fetch-one (format nil "SELECT COUNT(*) AS n ~a" base) params) "n"))
             (rows (apply #'fetch
                          (format nil "SELECT * ~a ORDER BY ~a LIMIT ? OFFSET ?"
                                  base (build-order-by (query-orders query) schema-model column))
                          (append params (list (query-limit query) (query-offset query))))))
        (values (mapcar #'row->content rows) total)))))

(defun count-contents (space model)
  (col (fetch-one "SELECT COUNT(*) AS n FROM contents WHERE space = ? AND model = ?" space model) "n"))

(defun unique-value-taken-p (space model field value &key exclude-id)
  "True when another content of MODEL already uses VALUE for FIELD (in draft or published data)."
  (let ((expr (format nil "json_extract(~~a, '$.~a')" field)))
    (and (fetch-one (format nil "SELECT 1 FROM contents WHERE space = ? AND model = ? AND id != ?
                                 AND (~a = ? OR ~a = ?) LIMIT 1"
                            (format nil expr "published") (format nil expr "draft"))
                    space model (or exclude-id "") value value)
         t)))
