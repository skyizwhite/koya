(defpackage #:koya-server/usecases/listing
  (:use #:cl)
  (:import-from #:koya-core/json #:json-array-p #:blank-p)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields #:model-field #:field-name #:field-type
                #:+system-fields+ #:field-option)
  (:import-from #:koya-server/usecases/ports/contents
                #:list-contents #:count-contents #:find-object-content #:find-contents-by-ids)
  (:import-from #:koya-server/domain/content #:content-data #:content-id #:content-label)
  (:import-from #:koya-server/usecases/ports/media #:find-media-by-ids)
  (:import-from #:koya-server/domain/query #:make-query)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:export #:parse-sort
           #:content-page
           #:page-media
           #:all-contents
           #:count-contents
           #:find-object-content
           #:reference-options
           #:reference-labels))
(in-package #:koya-server/usecases/listing)

(defun sortable-p (model name)
  (and (not (blank-p name))
       (let ((field (model-field model name)))
         (if field
             (not (member (field-type field) '(:custom :repeater)))
             (member name +system-fields+ :test #'string=)))))

(defun parse-sort (raw model)
  (let* ((desc (and (not (blank-p raw)) (char= (char raw 0) #\-)))
         (name (and (not (blank-p raw)) (if desc (subseq raw 1) raw))))
    (when (sortable-p model name)
      (values name (if desc :desc :asc)))))

(defun sort-orders (name direction)
  (if name (list (cons name direction)) (list (cons "createdAt" :desc))))

(defun content-page (space model &key (page 1) page-size search-text status sort-name sort-direction)
  (let ((query (make-query :limit page-size
                           :offset (* (1- page) page-size)
                           :orders (sort-orders sort-name sort-direction)
                           :search (unless (blank-p search-text) search-text))))
    (multiple-value-bind (contents total)
        (list-contents space (model-name model) model query :status :all :only-status status)
      (values contents total (max 1 (ceiling total page-size))))))

(defun page-media (space model contents)
  (find-media-by-ids
   space
   (loop :for content :in contents
         :for data := (content-data content :draft t)
         :nconc (loop :for field :in (model-fields model)
                      :for value := (and data (gethash (field-name field) data))
                      :when (and (eq (field-type field) :media) (stringp value) (plusp (length value)))
                        :collect value
                      :when (and (eq (field-type field) :media) (json-array-p value) (plusp (length value))
                                 (stringp (aref value 0)))
                        :collect (aref value 0)))))

(defun all-contents (space model query)
  (list-contents space (model-name model) model query :status :all))

(defun reference-options (space field)
  (when (eq (field-type field) :reference)
    (let ((target (find-model space (field-option field :model))))
      (when target
        (sort (mapcar (lambda (content) (cons (content-id content) (content-label content target)))
                      (list-contents space (model-name target) target (make-query :limit nil) :status :all))
              #'string-lessp :key #'cdr)))))

(defun referenced-ids (field contents)
  (loop :for content :in contents
        :for data := (content-data content :draft t)
        :for value := (and data (gethash (field-name field) data))
        :nconc (cond ((stringp value) (list value))
                     ((vectorp value) (remove-if-not #'stringp (coerce value 'list))))))

(defun reference-labels (space model contents)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) table)
      (when (eq (field-type field) :reference)
        (let ((target (find-model space (field-option field :model)))
              (labels (make-hash-table :test 'equal)))
          (when target
            (maphash (lambda (id content) (setf (gethash id labels) (content-label content target)))
                     (find-contents-by-ids space (model-name target) (referenced-ids field contents))))
          (setf (gethash (field-name field) table) labels))))))
