(defpackage #:koya-server/domain/content
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-fields #:model-label #:field-name #:field-type #:field-option)
  (:import-from #:koya-core/validate
                #:blank-value-p)
  (:import-from #:koya-core/json
                #:json-null)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string)
  (:export #:content #:make-content #:content-p
           #:content-id #:content-space #:content-model #:content-status
           #:content-published #:content-draft #:content-draft-key
           #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
           #:content-data
           #:status-of
           #:new-draft-key
           #:new-content
           #:drafted
           #:published
           #:unpublished
           #:discarded
           #:keyed
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
  id space model published draft draft-key created-at updated-at published-at revised-at)

(defun content-status (content)
  "One of +STATUSES+, told from what the content holds."
  (status-of (content-published content) (content-draft content)))

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

;;; What a write leaves a content as. Each of these is the content after one
;;; step of its life, as a new struct; the store is handed the result and
;;; keeps it (ports/contents). A draft carries a key that lets a preview link
;;; read it; the key changes with every draft, so an old link stops working.

(defun new-draft-key ()
  (byte-array-to-hex-string (random-data 16)))

(defun touched (content now)
  (setf (content-updated-at content) now)
  content)

(defun new-content (id space model data &key publish (now (now-iso)) created-at updated-at published-at revised-at)
  "A content as it is first written: DATA published, with PUBLISH, or its draft
under a fresh key. The system timestamps default to NOW; an import gives its own."
  (touched (make-content :id id :space space :model model
                         :published (and publish data)
                         :draft (and (not publish) data)
                         :draft-key (and (not publish) (new-draft-key))
                         :created-at (or created-at now)
                         :published-at (and publish (or published-at now))
                         :revised-at (and publish (or revised-at now)))
           (or updated-at now)))

(defun drafted (content data &key (now (now-iso)))
  "CONTENT with DATA as its draft, under a fresh key."
  (let ((next (copy-content content)))
    (setf (content-draft next) data
          (content-draft-key next) (new-draft-key))
    (touched next now)))

(defun published (content data &key (now (now-iso)) published-at)
  "CONTENT with DATA live and no draft. The first publish date is kept unless
PUBLISHED-AT replaces it; the revision date is NOW."
  (let ((next (copy-content content)))
    (setf (content-published next) data
          (content-draft next) nil
          (content-draft-key next) nil
          (content-published-at next) (or published-at (content-published-at content) now)
          (content-revised-at next) now)
    (touched next now)))

(defun unpublished (content &key (now (now-iso)))
  "CONTENT taken off the air: what was live becomes its draft unless it has one,
under a fresh key, and it has no publish date."
  (let ((next (copy-content content)))
    (setf (content-draft next) (content-data content :draft t)
          (content-draft-key next) (new-draft-key)
          (content-published next) nil
          (content-published-at next) nil)
    (touched next now)))

(defun discarded (content &key (now (now-iso)))
  "CONTENT without its draft: what is live is all there is."
  (let ((next (copy-content content)))
    (setf (content-draft next) nil
          (content-draft-key next) nil)
    (touched next now)))

(defun keyed (content)
  "CONTENT with a draft key, made now if it had none: a preview link for a
published content."
  (if (content-draft-key content)
      content
      (let ((next (copy-content content)))
        (setf (content-draft-key next) (new-draft-key))
        next)))

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
