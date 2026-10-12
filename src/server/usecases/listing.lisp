(defpackage #:koya-server/usecases/listing
  (:use #:cl)
  (:import-from #:koya-core/data #:blank-p)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields #:model-field #:field-name #:field-type
                #:+system-fields+ #:field-option #:field-many-p #:map-data-fields #:field-value)
  (:import-from #:koya-server/usecases/ports/contents
                #:list-contents #:count-contents #:find-object-content #:find-contents-by-ids)
  (:import-from #:koya-server/domain/content #:content-data #:content-id #:content-label #:content-labels #:held-ids)
  (:import-from #:koya-server/usecases/ports/media #:find-media-by-ids)
  (:import-from #:koya-server/domain/query #:make-query)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:export #:parse-sort
           #:content-page
           #:page-media
           #:data-media
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
                      :for id := (and (eq (field-type field) :media)
                                      (first (held-ids (field-value data field) (field-many-p field))))
                      :when id :collect id))))

(defun data-media (space model data)
  (let ((ids '()))
    (map-data-fields (model-fields model) data
                     (lambda (field value found object outer)
                       (declare (ignore found outer))
                       (when (eq (field-type field) :media)
                         (dolist (id (held-ids value (field-many-p field)))
                           (push id ids)))
                       object))
    (if ids (find-media-by-ids space ids) (make-hash-table :test 'equal))))

(defun all-contents (space model query)
  (list-contents space (model-name model) model query :status :all))

(defun reference-options (space model-name)
  (let ((target (find-model space model-name)))
    (sort (mapcar (lambda (content) (cons (content-id content) (content-label content target)))
                  (list-contents space model-name target (make-query :limit nil) :status :all))
          #'string-lessp :key #'cdr)))

(defun referenced-ids (field contents)
  (loop :for content :in contents
        :for data := (content-data content :draft t)
        :for value := (field-value data field)
        :append (held-ids value (field-many-p field))))

(defun reference-labels (space model contents)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) table)
      (when (eq (field-type field) :reference)
        (let ((target (find-model space (field-option field :model))))
          (setf (gethash (field-name field) table)
                (content-labels (find-contents-by-ids space (model-name target) (referenced-ids field contents)) target)))))))
