(defpackage #:koya-server/domain/content
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-fields #:model-label #:field-name #:field-type #:field-option)
  (:import-from #:koya/core/validate
                #:blank-value-p)
  (:import-from #:koya/core/json
                #:json-null)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:export #:content #:make-content #:content-p
           #:content-id #:content-space #:content-model #:content-status
           #:content-published #:content-draft #:content-draft-key
           #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
           #:content-data
           #:status-of
           #:+statuses+
           #:content-label
           #:merge-data
           #:default-data
           #:fill-defaults
           #:fill-slugs
           #:slugify))
(in-package #:koya-server/domain/content)

;;; A content of a model. PUBLISHED and DRAFT are data objects (hash tables) or
;;; NIL; STATUS follows from which of them there are (STATUS-OF).

(defstruct content
  id space model status published draft draft-key created-at updated-at published-at revised-at)

(defun content-data (content &key draft)
  "The published data, or with DRAFT the draft data falling back to published."
  (if draft
      (or (content-draft content) (content-published content))
      (content-published content)))

(defparameter +statuses+ '("draft" "published" "published+draft")
  "Every status a content can be in: the three badges the admin UI's list shows.")

(defun status-of (published draft)
  (cond ((and published draft) "published+draft")
        (published "published")
        (t "draft")))

(defun content-label (content model)
  "What CONTENT is shown as: the value of the field MODEL declares as its :label,
else its id. No field is taken for a title unless the schema says so -- the
first text field of one model is another's subtitle."
  (let* ((label (model-label model))
         (data (and label (content-data content :draft t)))
         (value (and data (gethash label data))))
    (if (and (stringp value) (plusp (length value)))
        value
        (content-id content))))

(defun merge-data (base patch)
  "A new object with PATCH's keys applied on top of BASE. JSON null removes a key."
  (let ((out (make-hash-table :test 'equal)))
    (when base (maphash (lambda (k v) (setf (gethash k out) v)) base))
    (maphash (lambda (k v) (if (eq v json-null) (remhash k out) (setf (gethash k out) v))) patch)
    out))

(defun default-data (model)
  "What a new content of MODEL starts with: every :boolean field that declares
:default t, set to true. The other types have no defaults."
  (let ((data (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) data)
      (when (and (eq (field-type field) :boolean) (field-option field :default))
        (setf (gethash (field-name field) data) t)))))

(defun fill-defaults (model data)
  "Add the defaults of DEFAULT-DATA for keys DATA does not mention (destructively)."
  (maphash (lambda (key value)
             (unless (nth-value 1 (gethash key data))
               (setf (gethash key data) value)))
           (default-data model))
  data)

(defun slugify (string)
  "Lowercase ASCII slug: letters, digits and single hyphens."
  (let* ((lower (string-downcase string))
         (dashed (regex-replace-all "[^a-z0-9]+" lower "-")))
    (string-trim "-" dashed)))

(defun fill-slugs (model data)
  "Generate blank :slug fields from their :from source field (destructively)."
  (dolist (field (model-fields model))
    (when (eq (field-type field) :slug)
      (let ((current (gethash (field-name field) data))
            (source (gethash (field-option field :from) data)))
        (when (and (blank-value-p current) (stringp source) (not (blank-value-p source)))
          (let ((slug (slugify source)))
            (when (plusp (length slug))
              (setf (gethash (field-name field) data) slug)))))))
  data)
