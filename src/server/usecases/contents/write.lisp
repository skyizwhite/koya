(defpackage #:koya-server/usecases/contents/write
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-kind #:model-fields #:field-name #:field-option #:model-name)
  (:import-from #:koya/core/validate
                #:validate-content #:validation-error #:blank-value-p #:content-id-p)
  (:import-from #:koya/core/time
                #:parse-iso)
  (:import-from #:koya/core/json
                #:json-null #:json-equal)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya-server/domain/errors
                #:fail #:conflict #:invalid-input)
  (:import-from #:koya-server/usecases/ports/store
                #:with-transaction)
  (:import-from #:koya-server/usecases/ports/spaces
                #:space-webhook-secret)
  (:import-from #:koya-server/usecases/contents/lookup
                #:resolve-model #:resolve-content)
  (:import-from #:koya-server/usecases/ports/contents
                #:insert-content #:update-content #:delete-content #:record-revision
                #:find-object-content #:unique-value-taken-p #:get-content)
  (:import-from #:koya-server/usecases/contents/references
                #:content-references)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-published #:content-draft #:content-draft-key #:content-data
                #:merge-data #:fill-defaults #:fill-slugs
                #:new-content #:drafted #:published #:unpublished #:discarded #:keyed)
  (:import-from #:koya-server/usecases/contents/delivery #:deliver)
  (:import-from #:koya-server/usecases/webhooks/notify #:notify-webhooks)
  (:import-from #:koya-server/usecases/actor
                #:*actor*)
  (:export #:check-content
           #:create
           #:update-draft
           #:publish
           #:unpublish
           #:discard
           #:destroy
           #:draft-key))
(in-package #:koya-server/usecases/contents/write)

;;; Content operations shared by the admin API and the admin UI: lookup,
;;; validation, persistence and webhook notification. What a write makes of a
;;; content is the domain's (domain/content); this decides whether it may
;;; happen, hands the result to the store and records it in the history.
;;;
;;; Each write runs inside WITH-TRANSACTION, which holds the store, so a
;;; uniqueness check and the insert after it cannot interleave with another
;;; request. Webhooks fire inside that scope, asynchronously.
;;;
;;; Every write names its caller, *ACTOR*, for the content's history.

(defun check-content (space-name model data &key partial exclude-id)
  "Validate DATA against MODEL, including :unique fields. Signals VALIDATION-ERROR."
  (fill-slugs model data)
  (let ((errors (validate-content model data :partial partial)))
    (dolist (field (model-fields model))
      (when (field-option field :unique)
        (multiple-value-bind (value found) (gethash (field-name field) data)
          (when (and found (not (blank-value-p value))
                     (unique-value-taken-p space-name (model-name model) (field-name field) value
                                           :exclude-id exclude-id))
            (setf errors (append errors (list (list :field (field-name field) :code "unique"
                                                    :message "must be unique"))))))))
    (when errors
      (error 'validation-error :errors errors))
    data))

(defun check-timestamp (name value)
  "VALUE is an ISO 8601 string or NIL. Signals INVALID-INPUT naming the wire field
NAME otherwise."
  (cond ((null value) nil)
        ((parse-iso value) value)
        (t (fail 'invalid-input (format nil "\"~a\" must be an ISO 8601 datetime" name)))))

(defun check-published-at (value)
  (check-timestamp "publishedAt" value))

(defun check-new-id (id)
  (cond ((null id) nil)
        ((not (content-id-p id)) (fail 'invalid-input "\"id\" must be 1-64 letters, digits, '-' or '_'"))
        ((get-content id) (fail 'conflict (format nil "Content ~a already exists" id)))
        (t id)))

(defun published-view (space model content)
  (and (content-published content)
       (deliver content model space)))

(defun draft-view (space model content)
  "The draft (or, without one, published) data as the delivery API would show it."
  (deliver content model space :draft t))

(defun notify (space model id event &key old new)
  (notify-webhooks space model id event
                   :secret (space-webhook-secret space)
                   :old old
                   :new new))

(defun store (content event data)
  "Keep CONTENT as it now is, and EVENT, what left it so, in its history."
  (update-content content)
  (record-revision (content-id content) event data :by *actor*)
  content)

(defun create (space model data &key publish id created-at updated-at published-at revised-at)
  "Create a content. ID and the system timestamps CREATED-AT, UPDATED-AT,
PUBLISHED-AT and REVISED-AT (ISO 8601) may be given explicitly, e.g. when
importing. For object-kind models the single existing content is updated instead,
and only PUBLISHED-AT applies."
  (let* ((space-name space)
         (model-name (model-name model))
         (created-at (check-timestamp "createdAt" created-at))
         (updated-at (check-timestamp "updatedAt" updated-at))
         (published-at (check-published-at published-at))
         (revised-at (check-timestamp "revisedAt" revised-at)))
    (with-transaction
      (check-content space-name model (fill-defaults model data))
      (flet ((insert ()
               (let ((content (new-content (or (check-new-id id) (make-ulid)) space-name model-name data
                                           :publish publish
                                           :created-at created-at :updated-at updated-at
                                           :published-at published-at :revised-at revised-at)))
                 (insert-content content)
                 (record-revision (content-id content) (if publish "publish" "draft") data :by *actor*)
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
  "Save a draft: PATCH is merged onto the current draft (or published data) unless
REPLACE. Returns the content and what came of it: :SAVED; :UNCHANGED when that is
what the content holds already, and nothing is written; or :PUBLISHED when it is
the published data again, and the draft is dropped -- a draft that changes nothing
is none, and would only leave a discard with nothing to show in the history."
  (let* ((space-name space)
         (model-name (model-name model))
         (content (resolve-content space-name model-name id))
         (current (content-data content :draft t))
         (live (content-published content))
         (data (if replace patch (merge-data current patch))))
    (cond ((json-equal data current) (values content :unchanged))
          ((and live (json-equal data live))
           (values (store (discarded content) "discard" live) :published))
          (t
           (with-transaction
             (check-content space-name model data :exclude-id id)
             (let ((saved (store (drafted content data) "draft" data)))
               (notify space model id :draft :old (published-view space model saved) :new (draft-view space model saved))
               (values saved :saved)))))))

(defun publish (space model id &optional data &key published-at)
  "Publish DATA, or the current draft. PUBLISHED-AT (ISO 8601) overrides the publish date. Fires webhooks."
  (let* ((space-name space)
         (model-name (model-name model))
         (content (resolve-content space-name model-name id))
         (data (or data (content-data content :draft t)))
         (published-at (check-published-at published-at))
         (old (published-view space model content)))
    (with-transaction
      (check-content space-name model data :exclude-id id)
      (let ((live (store (published content data :published-at published-at) "publish" data)))
        (notify space model id :publish :old old :new (published-view space model live))
        live))))

(defun check-unreferenced (space-name model-name id verb)
  "Refuse with a CONFLICT coded in_use while another content refers to ID: taking
it away would leave that content pointing at nothing."
  (let ((references (content-references space-name model-name id)))
    (when (plusp references)
      (fail 'conflict (format nil "This content is referenced by ~a other content~:p; remove ~:*~[~;that reference~:;those references~] before you ~a it"
                              references verb)
            :code "in_use"))))

(defun unpublish (space model id)
  (let* ((space-name space)
         (model-name (model-name model))
         (content (resolve-content space-name model-name id))
         (old (published-view space model content)))
    (let ((result (with-transaction
                    ;; a draft is out of the delivery API already; unpublishing it takes nothing away
                    (when (content-published content)
                      (check-unreferenced space-name model-name (content-id content) "unpublish"))
                    (let ((next (unpublished content)))
                      (update-content next)
                      ;; unpublishing what was never live changes nothing the history tells
                      (when (content-published content)
                        (record-revision id "unpublish" (content-draft next) :by *actor*))
                      next))))
      (when old (notify space model id :unpublish :old old))
      result)))

(defun discard (space model id)
  "Throw away the draft of a published content. No webhook: what is published does not change."
  (let* ((space-name space)
         (model-name (model-name model))
         (content (resolve-content space-name model-name id)))
    (unless (content-published content)
      (fail 'conflict "Only a published content has a draft to discard; delete it instead" :code "not_published"))
    (let ((next (discarded content)))
      (update-content next)
      (when (content-draft content)
        (record-revision id "discard" (content-published content) :by *actor*))
      next)))

(defun destroy (space model id)
  (let* ((space-name space)
         (model-name (model-name model))
         (content (resolve-content space-name model-name id))
         (old (published-view space model content)))
    (with-transaction
      (check-unreferenced space-name model-name (content-id content) "delete")
      (delete-content id))
    (when old (notify space model id :delete :old old))
    t))

(defun draft-key (space-name model-name id)
  "The draft key of content ID, for previews, made on first use."
  (resolve-model space-name model-name)
  (let* ((content (resolve-content space-name model-name id))
         (keyed (keyed content)))
    (unless (eq keyed content) (update-content keyed))
    (content-draft-key keyed)))
