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
  (:import-from #:koya-server/db/content-revisions
                #:record-revision)
  (:import-from #:koya-server/db/schema-store
                #:load-schema)
  (:import-from #:koya/core/schema
                #:schema-models #:model-name #:model-fields #:field-name #:field-type #:field-option)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string)
  (:export #:make-content #:content-id #:content-space #:content-model #:content-status
           #:content-published #:content-draft #:content-draft-key
           #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
           #:content-data
           #:create-content
           #:save-draft
           #:publish-content
           #:unpublish-content
           #:discard-draft
           #:delete-content
           #:get-content
           #:find-content
           #:list-contents
           #:count-contents
           #:ensure-draft-key
           #:find-object-content
           #:unique-value-taken-p
           #:space-contents
           #:import-content
           #:content-references))
(in-package #:koya-server/db/contents)

;;; Content rows. PUBLISHED and DRAFT are JSON objects (hash tables) or NIL.
;;; status is one of "draft", "published", "published+draft".
;;;
;;; Every write records a revision in the same transaction (db/content-revisions);
;;; BY names who made it, as lib/auth's CALLING-IDENTITY does. IMPORT-CONTENT is
;;; the exception: an imported content brings its own history.

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

(defun new-draft-key ()
  (byte-array-to-hex-string (random-data 16)))

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

(defun create-content (space model data &key publish (id (make-ulid))
                                             created-at updated-at published-at revised-at by)
  "Insert DATA as a new content. With PUBLISH it is published immediately,
otherwise saved as a draft. The system timestamps default to now; imports may
supply any of CREATED-AT, UPDATED-AT, PUBLISHED-AT and REVISED-AT (ISO 8601).
PUBLISHED-AT and REVISED-AT are only stored when publishing."
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

(defun save-draft (id data &key by)
  "Replace the draft of content ID with DATA. A fresh draft key is issued each time,
so old preview links stop working."
  (let ((content (or (get-content id) (error "content ~a not found" id))))
    (with-db-transaction
      (exec "UPDATE contents SET draft = ?, draft_key = ?, status = ?, updated_at = ? WHERE id = ?"
            (to-json data) (new-draft-key) (status-for (content-published content) t) (now-iso) id)
      (record-revision id "draft" data :by by))
    (get-content id)))

(defun publish-content (id &optional data &key published-at by)
  "Publish DATA (or the current draft, or re-publish the published data) and clear the draft.
PUBLISHED-AT overrides the publish date; otherwise the first publish date is kept."
  (let* ((content (or (get-content id) (error "content ~a not found" id)))
         (data (or data (content-draft content) (content-published content)))
         (now (now-iso)))
    (with-db-transaction
      (exec "UPDATE contents SET published = ?, draft = NULL, draft_key = NULL, status = 'published', updated_at = ?,
               published_at = COALESCE(?, published_at, ?), revised_at = ? WHERE id = ?"
            (to-json data) now published-at now now id)
      (record-revision id "publish" data :by by))
    (get-content id)))

(defun unpublish-content (id &key by)
  "Take content ID off the delivery API, keeping its data as a draft."
  (let* ((content (or (get-content id) (error "content ~a not found" id)))
         (data (or (content-draft content) (content-published content))))
    (with-db-transaction
      (exec "UPDATE contents SET published = NULL, draft = ?, draft_key = ?, status = 'draft', updated_at = ?, published_at = NULL WHERE id = ?"
            (to-json data) (new-draft-key) (now-iso) id)
      ;; unpublishing what was never live changes nothing the history tells
      (when (content-published content)
        (record-revision id "unpublish" data :by by)))
    (get-content id)))

(defun discard-draft (id &key by)
  "Drop the draft of a published content ID, so it shows its published data again.
Errors when the content has no published version: there would be nothing left."
  (let ((content (or (get-content id) (error "content ~a not found" id))))
    (unless (content-published content) (error "content ~a is not published; delete it instead" id))
    (with-db-transaction
      (exec "UPDATE contents SET draft = NULL, draft_key = NULL, status = 'published', updated_at = ? WHERE id = ?"
            (now-iso) id)
      (when (content-draft content)
        (record-revision id "discard" (content-published content) :by by)))
    (get-content id)))

(defun delete-content (id)
  ;; its revisions go with it, ON DELETE CASCADE
  (exec "DELETE FROM contents WHERE id = ?" id))

(defun reference-fields (space target)
  "Hash of model name -> its :reference fields in SPACE's current schema that point at TARGET."
  (let ((table (make-hash-table :test 'equal))
        (schema (load-schema space)))
    (dolist (model (and schema (schema-models schema)) table)
      (let ((fields (remove-if-not (lambda (f) (and (eq (field-type f) :reference)
                                                    (equal (field-option f :model) target)))
                                   (model-fields model))))
        (when fields (setf (gethash (model-name model) table) fields))))))

(defun refers-p (fields json id)
  (let ((data (and json (parse-json json))))
    (and (hash-table-p data)
         (some (lambda (field)
                 (let ((value (gethash (field-name field) data)))
                   (typecase value
                     (string (string= value id))
                     (vector (find id value :test #'equal)))))
               fields))))

;; Only the fields in the schema count, as for media (see db/media): a deploy that
;; removes a reference field leaves its ids in the stored JSON, unread.
(defun content-references (space model id)
  "Number of other contents in SPACE whose published or draft data refers to
content ID of MODEL through a :reference field of the current schema."
  (let ((fields (reference-fields space model))
        (needle (format nil "%~a%" id)))
    (if (zerop (hash-table-count fields))
        0
        ;; LIKE only skips the contents that cannot refer to it; the fields decide
        (count-if (lambda (row)
                    (let ((fields (gethash (col row "model") fields)))
                      (and fields
                           (or (refers-p fields (col row "published") id)
                               (refers-p fields (col row "draft") id)))))
                  (fetch "SELECT model, published, draft FROM contents
                          WHERE space = ? AND id <> ? AND (published LIKE ? OR draft LIKE ?)"
                         space id needle needle)))))

(defun ensure-draft-key (id)
  "Return the draft key of content ID, generating one on first use."
  (let ((content (or (get-content id) (error "content ~a not found" id))))
    (or (content-draft-key content)
        (let ((key (new-draft-key)))
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

(defun list-contents (space model schema-model query &key (status :published) only-status)
  "Return (values contents total-count) for QUERY. STATUS :published restricts to
published data (delivery API); :all lists everything using draft data when present (admin).
ONLY-STATUS narrows to one value of the status column -- \"draft\", \"published\" or
\"published+draft\" -- which is the admin list's status filter; it is the badge the
list shows, so the three choices are the three badges."
  (let ((column (data-column status)))
    (multiple-value-bind (where-sql where-params) (build-where (query-filters query) schema-model column)
      (let* ((base (format nil "FROM contents WHERE space = ? AND model = ? AND ~a~@[~a~]~@[ AND ~a~]"
                           (status-clause status) (and only-status " AND status = ?") where-sql))
             (params (append (list space model) (and only-status (list only-status)) where-params))
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

(defun space-contents (space)
  "Every content of SPACE, oldest first: what an export carries."
  (mapcar #'row->content
          (fetch "SELECT * FROM contents WHERE space = ? ORDER BY created_at, id" space)))

(defun import-content (content)
  "Insert CONTENT as it is, every column included, and record no revision: the
importer brings the content's history along with it."
  (exec "INSERT INTO contents (id, space, model, status, published, draft, draft_key, created_at, updated_at, published_at, revised_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        (content-id content) (content-space content) (content-model content)
        (status-for (content-published content) (content-draft content))
        (let ((v (content-published content))) (and v (to-json v)))
        (let ((v (content-draft content))) (and v (to-json v)))
        (content-draft-key content)
        (content-created-at content) (content-updated-at content)
        (content-published-at content) (content-revised-at content)))
