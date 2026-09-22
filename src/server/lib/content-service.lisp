(defpackage #:koya-server/lib/content-service
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-kind #:model-fields #:field-name #:field-option)
  (:import-from #:koya/core/validate
                #:validate-content #:validation-error #:blank-value-p #:content-id-p)
  (:import-from #:koya/core/time
                #:parse-iso)
  (:import-from #:koya/core/json
                #:json-null)
  (:import-from #:koya-server/db/connection
                #:with-db-transaction)
  (:import-from #:koya-server/db/schema-store
                #:find-space #:find-model #:space-webhook-secret)
  (:import-from #:koya-server/db/contents
                #:create-content #:save-draft #:publish-content #:unpublish-content #:delete-content #:discard-draft
                #:find-content #:find-object-content #:unique-value-taken-p #:get-content
                #:content-id #:content-published #:content-draft #:content-published-at #:content-data)
  (:import-from #:koya-server/lib/presenter
                #:content->jobject)
  (:import-from #:koya-server/lib/webhook
                #:notify-webhooks)
  (:import-from #:koya-server/lib/http
                #:fail-api)
  (:import-from #:koya-server/lib/forms
                #:slugify)
  (:export #:resolve-model
           #:resolve-content
           #:default-data
           #:check-content
           #:merge-data
           #:create
           #:update-draft
           #:publish
           #:unpublish
           #:discard
           #:destroy))
(in-package #:koya-server/lib/content-service)

;;; Content operations shared by the admin API and the admin UI: lookup,
;;; validation, persistence and webhook notification.
;;;
;;; Each write runs inside WITH-DB-TRANSACTION, which holds the connection lock,
;;; so a uniqueness check and the insert after it cannot interleave with another
;;; request. Webhooks fire inside that scope, asynchronously.

(defun resolve-model (space-name model-name)
  "Return (values space-name model) or signal 404."
  (let* ((space (or (find-space space-name)
                    (fail-api 404 "not_found" (format nil "Space ~a does not exist" space-name))))
         (model (or (find-model space model-name)
                    (fail-api 404 "not_found" (format nil "Model ~a does not exist" model-name)))))
    (values space model)))

(defun resolve-content (space-name model-name id)
  (or (find-content space-name model-name id)
      (fail-api 404 "not_found" (format nil "Content ~a does not exist" id))))

(defun fill-slugs (model data)
  "Generate blank :slug fields from their :from source field (destructively)."
  (dolist (field (model-fields model))
    (when (eq (koya/core/schema:field-type field) :slug)
      (let ((current (gethash (field-name field) data))
            (source (gethash (field-option field :from) data)))
        (when (and (blank-value-p current) (stringp source) (not (blank-value-p source)))
          (let ((slug (slugify source)))
            (when (plusp (length slug))
              (setf (gethash (field-name field) data) slug)))))))
  data)

(defun default-data (model)
  "What a new content of MODEL starts with: every :boolean field that declares
:default t, set to true. The other types have no defaults."
  (let ((data (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) data)
      (when (and (eq (koya/core/schema:field-type field) :boolean) (field-option field :default))
        (setf (gethash (field-name field) data) t)))))

(defun fill-defaults (model data)
  "Add the defaults of DEFAULT-DATA for keys DATA does not mention (destructively)."
  (maphash (lambda (key value)
             (unless (nth-value 1 (gethash key data))
               (setf (gethash key data) value)))
           (default-data model))
  data)

(defun check-content (space-name model data &key partial exclude-id)
  "Validate DATA against MODEL, including :unique fields. Signals VALIDATION-ERROR."
  (fill-slugs model data)
  (let ((errors (validate-content model data :partial partial)))
    (dolist (field (model-fields model))
      (when (field-option field :unique)
        (multiple-value-bind (value found) (gethash (field-name field) data)
          (when (and found (not (blank-value-p value))
                     (unique-value-taken-p space-name (koya/core/schema:model-name model) (field-name field) value
                                           :exclude-id exclude-id))
            (setf errors (append errors (list (list :field (field-name field) :code "unique"
                                                    :message "must be unique"))))))))
    (when errors
      (error 'validation-error :errors errors))
    data))

(defun merge-data (base patch)
  "A new object with PATCH's keys applied on top of BASE. JSON null removes a key."
  (let ((out (make-hash-table :test 'equal)))
    (when base (maphash (lambda (k v) (setf (gethash k out) v)) base))
    (maphash (lambda (k v) (if (eq v json-null) (remhash k out) (setf (gethash k out) v))) patch)
    out))

(defun check-timestamp (name value)
  "VALUE is an ISO 8601 string or NIL. Signals 400 naming the wire field NAME otherwise."
  (cond ((null value) nil)
        ((parse-iso value) value)
        (t (fail-api 400 "bad_request" (format nil "\"~a\" must be an ISO 8601 datetime" name)))))

(defun check-published-at (value)
  (check-timestamp "publishedAt" value))

(defun check-new-id (id)
  (cond ((null id) nil)
        ((not (content-id-p id)) (fail-api 400 "bad_request" "\"id\" must be 1-64 letters, digits, '-' or '_'"))
        ((get-content id) (fail-api 409 "conflict" (format nil "Content ~a already exists" id)))
        (t id)))

(defun published-view (space model content)
  (and (content-published content)
       (content->jobject content model space)))

(defun draft-view (space model content)
  "The draft (or, without one, published) data as the delivery API would show it."
  (content->jobject content model space :draft t))

(defun notify (space model id event &key old new)
  (notify-webhooks space model id event
                   :secret (space-webhook-secret space)
                   :old old
                   :new new))

(defun create (space model data &key publish id created-at updated-at published-at revised-at)
  "Create a content. ID and the system timestamps CREATED-AT, UPDATED-AT,
PUBLISHED-AT and REVISED-AT (ISO 8601) may be given explicitly, e.g. when
importing. For object-kind models the single existing content is updated instead,
and only PUBLISHED-AT applies."
  (let* ((space-name space)
         (model-name (koya/core/schema:model-name model))
         (created-at (check-timestamp "createdAt" created-at))
         (updated-at (check-timestamp "updatedAt" updated-at))
         (published-at (check-published-at published-at))
         (revised-at (check-timestamp "revisedAt" revised-at)))
    (with-db-transaction
      (check-content space-name model (fill-defaults model data))
      (flet ((insert ()
               (let ((content (apply #'create-content space-name model-name data
                                     :publish publish
                                     :created-at created-at :updated-at updated-at
                                     :published-at published-at :revised-at revised-at
                                     (and (check-new-id id) (list :id id)))))
                 (if publish
                     (notify space model (content-id content) :publish :new (published-view space model content))
                     (notify space model (content-id content) :draft :new (draft-view space model content)))
                 content)))
        (if (eq (model-kind model) :object)
            (let ((existing (find-object-content space-name model-name)))
              (cond ((null existing) (insert))
                    (publish (publish space model (content-id existing) data :published-at published-at))
                    (t (update-draft space model (content-id existing) data :replace t))))
            (insert))))))

(defun update-draft (space model id patch &key replace)
  "Save a draft: PATCH is merged onto the current draft (or published data) unless REPLACE."
  (let* ((space-name space)
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (data (if replace patch (merge-data (content-data content :draft t) patch))))
    (with-db-transaction
      (check-content space-name model data :exclude-id id)
      (let ((saved (save-draft id data)))
        (notify space model id :draft :old (published-view space model saved) :new (draft-view space model saved))
        saved))))

(defun publish (space model id &optional data &key published-at)
  "Publish DATA, or the current draft. PUBLISHED-AT (ISO 8601) overrides the publish date. Fires webhooks."
  (let* ((space-name space)
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (data (or data (content-data content :draft t)))
         (published-at (check-published-at published-at))
         (old (published-view space model content)))
    (with-db-transaction
      (check-content space-name model data :exclude-id id)
      (let ((published (publish-content id data :published-at published-at)))
        (notify space model id :publish :old old :new (published-view space model published))
        published))))

(defun unpublish (space model id)
  (let* ((space-name space)
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (old (published-view space model content)))
    (let ((result (unpublish-content id)))
      (when old (notify space model id :unpublish :old old))
      result)))

(defun discard (space model id)
  "Throw away the draft of a published content. No webhook: what is published does not change."
  (let* ((space-name space)
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id)))
    (unless (content-published content)
      (fail-api 409 "not_published" "Only a published content has a draft to discard; delete it instead"))
    (discard-draft (content-id content))))

(defun destroy (space model id)
  (let* ((space-name space)
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (old (published-view space model content)))
    (delete-content id)
    (when old (notify space model id :delete :old old))
    t))
