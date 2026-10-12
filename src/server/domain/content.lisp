(defpackage #:koya-server/domain/content
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-fields #:model-label #:model-slug-field #:model-field #:field-type #:field-option
                #:map-data-fields #:field-value)
  (:import-from #:koya-core/validate
                #:blank-value-p #:datetime-string-p)
  (:import-from #:koya-core/data
                #:data-equal #:without-nulls #:array-p #:blank-p)
  (:import-from #:access
                #:access #:rem-plist-val)
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
           #:content-published-p
           #:content-draft-p
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
           #:held-ids
           #:content-slugs
           #:only-one))
(in-package #:koya-server/domain/content)

(defstruct content
  id space model status published draft draft-key created-at updated-at published-at revised-at)

(defparameter +statuses+ '("draft" "published" "published+draft"))

(defun status-of (published draft)
  (cond ((and published draft) "published+draft")
        (published "published")
        (t "draft")))

(defun content-published-p (content)
  (and (member (content-status content) '("published" "published+draft") :test #'string=) t))

(defun content-draft-p (content)
  (and (member (content-status content) '("draft" "published+draft") :test #'string=) t))

(defun content-data (content &key draft)
  (if (and draft (content-draft-p content))
      (content-draft content)
      (content-published content)))

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
                         :status (status-of publish (not publish))
                         :published (and publish data)
                         :draft (and (not publish) data)
                         :draft-key (and (not publish) (new-draft-key))
                         :created-at (or created-at now)
                         :published-at (and publish (or published-at now))
                         :revised-at (and publish (or revised-at now)))
           (or updated-at now)))

(defun drafted (content data &key (now (now-iso)))
  (let ((next (copy-content content)))
    (setf (content-status next) (next-status (content-status content) :save)
          (content-draft next) data
          (content-draft-key next) (new-draft-key))
    (touched next now)))

(defun published (content data &key (now (now-iso)) published-at)
  (let ((next (copy-content content)))
    (setf (content-status next) "published"
          (content-published next) data
          (content-draft next) nil
          (content-draft-key next) nil
          (content-published-at next) (or published-at (content-published-at content) now)
          (content-revised-at next) now)
    (touched next now)))

(defun unpublished (content &key (now (now-iso)))
  (let ((next (copy-content content)))
    (setf (content-status next) "draft"
          (content-draft next) (content-data content :draft t)
          (content-draft-key next) (new-draft-key)
          (content-published next) nil
          (content-published-at next) nil
          (content-revised-at next) nil)
    (touched next now)))

(defun discarded (content &key (now (now-iso)))
  (let ((next (copy-content content)))
    (setf (content-status next) "published"
          (content-draft next) nil
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
         (field (and label (model-field model label)))
         (value (and field (field-value (content-data content :draft t) field))))
    (if (and (stringp value) (plusp (length value)))
        value
        (content-id content))))

(defun merge-data (base patch)
  (let ((out (copy-list base)))
    (loop :for (key value) :on patch :by #'cddr
          :do (if (eq value :null)
                  (setf out (values (rem-plist-val key out :test #'eq)))
                  (setf (access out key :test #'eq) value)))
    out))

(defun booleans-filled (model data)
  (map-data-fields (model-fields model) data
                   (lambda (field value found object outer)
                     (declare (ignore found outer))
                     (when (and (eq (field-type field) :boolean) (member value '(nil :null)))
                       (setf (field-value object field) nil))
                     object)))

(defun same-data-p (model a b)
  (data-equal (booleans-filled model a) (booleans-filled model b)))

(defun default-data (model)
  (initial-data model nil))

(defun fill-default (field found object)
  (when (and (eq (field-type field) :boolean) (field-option field :default) (not found))
    (setf (field-value object field) t))
  object)

(defun keep-to-the-minute (field value object)
  (when (eq (field-type field) :datetime)
    (let ((timestamp (and (datetime-string-p value) (parse-iso value))))
      (when timestamp
        (setf (field-value object field)
              (format-iso (timestamp-minimize-part timestamp :sec :timezone +utc-zone+))))))
  object)

(defun initial-data (model data)
  (map-data-fields (model-fields model) (without-nulls data)
                   (lambda (field value found object outer)
                     (declare (ignore outer))
                     (keep-to-the-minute field value (fill-default field found object)))))

(defun to-the-minute (model data)
  (map-data-fields (model-fields model) (without-nulls data)
                   (lambda (field value found object outer)
                     (declare (ignore found outer))
                     (keep-to-the-minute field value object))))

(defun held-ids (value many)
  (remove-if-not (lambda (id) (and (stringp id) (not (blank-p id))))
                 (if many
                     (and (array-p value) (coerce value 'list))
                     (list value))))

(defun slug-value (model data)
  (let* ((field (model-slug-field model))
         (value (and field (field-value data field))))
    (and (stringp value) (not (blank-value-p value)) value)))

(defun content-slugs (model content)
  (list (slug-value model (content-published content))
        (slug-value model (content-draft content))))

(defun only-one (contents)
  (and contents (null (rest contents)) (first contents)))
