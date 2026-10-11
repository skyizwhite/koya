(defpackage #:koya-server/domain/content
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-fields #:model-label #:model-slug-field #:field-name #:field-type #:field-option
                #:map-data-fields)
  (:import-from #:koya-core/validate
                #:blank-value-p #:datetime-string-p)
  (:import-from #:koya-core/json
                #:json-null #:json-equal #:copy-object)
  (:import-from #:koya-core/time
                #:now-iso #:parse-iso #:format-iso)
  (:import-from #:local-time
                #:timestamp-minimize-part #:+utc-zone+)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string #:strong-random)
  (:import-from #:koya-server/domain/errors
                #:fail #:conflict)
  (:export #:content #:make-content #:content-p
           #:content-id #:content-space #:content-model #:content-status
           #:content-published #:content-draft #:content-draft-key
           #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
           #:content-data
           #:status-of
           #:new-draft-key
           #:new-content-id
           #:new-content
           #:drafted
           #:published
           #:unpublished
           #:discarded
           #:keyed
           #:+statuses+
           #:+operations+
           #:next-status
           #:check-transition
           #:content-label
           #:merge-data
           #:same-data-p
           #:default-data
           #:initial-data
           #:to-the-minute
           #:slug-value
           #:content-slugs
           #:only-one))
(in-package #:koya-server/domain/content)

(defstruct content
  id space model published draft draft-key created-at updated-at published-at revised-at)

(defun content-status (content)
  (status-of (content-published content) (content-draft content)))

(defun content-data (content &key draft)
  (if draft
      (or (content-draft content) (content-published content))
      (content-published content)))

(defparameter +statuses+ '("draft" "published" "published+draft"))

(defun status-of (published draft)
  (cond ((and published draft) "published+draft")
        (published "published")
        (t "draft")))

(defparameter +operations+ '(:save :publish :unpublish :discard :delete))

(defparameter +transitions+
  '(("draft" :save "draft")
    ("draft" :publish "published")
    ("draft" :delete nil)
    ("published" :save "published+draft")
    ("published" :publish "published")
    ("published" :unpublish "draft")
    ("published" :delete nil)
    ("published+draft" :save "published+draft")
    ("published+draft" :publish "published")
    ("published+draft" :unpublish "draft")
    ("published+draft" :discard "published")
    ("published+draft" :delete nil)))

(defparameter +refusals+
  '(("draft" :unpublish "not_published" "This content is not published")
    ("draft" :discard "not_published" "Only a published content has a draft to discard; delete it instead")
    ("published" :discard "no_draft" "This content has no draft to discard")))

(defun find-entry (table status op)
  (find-if (lambda (entry) (and (string= (first entry) status) (eq (second entry) op))) table))

(defun next-status (status op)
  (let ((entry (find-entry +transitions+ status op)))
    (values (third entry) (and entry t))))

(defun check-transition (content op)
  (let ((status (content-status content)))
    (multiple-value-bind (next allowed) (next-status status op)
      (if allowed
          next
          (destructuring-bind (code message) (cddr (find-entry +refusals+ status op))
            (fail 'conflict message :code code))))))

(defun new-draft-key ()
  (byte-array-to-hex-string (random-data 16)))

(defun new-content-id ()
  (string-downcase (format nil "~36,12,'0R" (strong-random (expt 36 12)))))

(defun touched (content now)
  (setf (content-updated-at content) now)
  content)

(defun new-content (id space model data &key publish (now (now-iso)) created-at updated-at published-at revised-at)
  (touched (make-content :id id :space space :model model
                         :published (and publish data)
                         :draft (and (not publish) data)
                         :draft-key (and (not publish) (new-draft-key))
                         :created-at (or created-at now)
                         :published-at (and publish (or published-at now))
                         :revised-at (and publish (or revised-at now)))
           (or updated-at now)))

(defun drafted (content data &key (now (now-iso)))
  (let ((next (copy-content content)))
    (setf (content-draft next) data
          (content-draft-key next) (new-draft-key))
    (touched next now)))

(defun published (content data &key (now (now-iso)) published-at)
  (let ((next (copy-content content)))
    (setf (content-published next) data
          (content-draft next) nil
          (content-draft-key next) nil
          (content-published-at next) (or published-at (content-published-at content) now)
          (content-revised-at next) now)
    (touched next now)))

(defun unpublished (content &key (now (now-iso)))
  (let ((next (copy-content content)))
    (setf (content-draft next) (content-data content :draft t)
          (content-draft-key next) (new-draft-key)
          (content-published next) nil
          (content-published-at next) nil
          (content-revised-at next) nil)
    (touched next now)))

(defun discarded (content &key (now (now-iso)))
  (let ((next (copy-content content)))
    (setf (content-draft next) nil
          (content-draft-key next) nil)
    (touched next now)))

(defun keyed (content)
  (if (content-draft-key content)
      content
      (let ((next (copy-content content)))
        (setf (content-draft-key next) (new-draft-key))
        next)))

(defun content-label (content model)
  (let* ((label (model-label model))
         (data (and label (content-data content :draft t)))
         (value (and data (gethash label data))))
    (if (and (stringp value) (plusp (length value)))
        value
        (content-id content))))

(defun merge-data (base patch)
  (let ((out (copy-object base)))
    (maphash (lambda (k v) (if (eq v json-null) (remhash k out) (setf (gethash k out) v))) patch)
    out))

(defun booleans-filled (model data)
  (map-data-fields (model-fields model) data
                   (lambda (field object outer)
                     (declare (ignore outer))
                     (when (and (eq (field-type field) :boolean)
                                (member (gethash (field-name field) object json-null) (list nil json-null)))
                       (setf (gethash (field-name field) object) nil)))))

(defun same-data-p (model a b)
  (json-equal (booleans-filled model a) (booleans-filled model b)))

(defun default-data (model)
  (let ((data (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) data)
      (when (and (eq (field-type field) :boolean) (field-option field :default))
        (setf (gethash (field-name field) data) t)))))

(defun fill-default (field object)
  (when (and (eq (field-type field) :boolean) (field-option field :default)
             (not (nth-value 1 (gethash (field-name field) object))))
    (setf (gethash (field-name field) object) t)))

(defun keep-to-the-minute (field object)
  (when (eq (field-type field) :datetime)
    (let* ((value (gethash (field-name field) object))
           (timestamp (and (datetime-string-p value) (parse-iso value))))
      (when timestamp
        (setf (gethash (field-name field) object)
              (format-iso (timestamp-minimize-part timestamp :sec :timezone +utc-zone+)))))))

(defun initial-data (model data)
  (map-data-fields (model-fields model) data
                   (lambda (field object outer)
                     (declare (ignore outer))
                     (fill-default field object)
                     (keep-to-the-minute field object))))

(defun to-the-minute (model data)
  (map-data-fields (model-fields model) data
                   (lambda (field object outer)
                     (declare (ignore outer))
                     (keep-to-the-minute field object))))

(defun slug-value (model data)
  (let* ((field (model-slug-field model))
         (value (and field data (gethash (field-name field) data))))
    (and (stringp value) (not (blank-value-p value)) value)))

(defun content-slugs (model content)
  (list (slug-value model (content-published content))
        (slug-value model (content-draft content))))

(defun only-one (contents)
  (and contents (null (rest contents)) (first contents)))
