(defpackage #:koya-server/usecases/listing
  (:use #:cl)
  (:import-from #:koya-core/data #:blank-p)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields #:field-type #:field-many-p #:field-value)
  (:import-from #:koya-server/usecases/ports/contents
                #:list-contents #:count-contents #:find-object-content)
  (:import-from #:koya-server/domain/content #:content-data #:held-ids)
  (:import-from #:koya-server/usecases/ports/media #:find-media-by-ids)
  (:import-from #:koya-server/domain/query #:make-query #:sortable-p)
  (:export #:parse-sort
           #:content-page
           #:page-media
           #:all-contents
           #:count-contents
           #:find-object-content))
(in-package #:koya-server/usecases/listing)

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

(defun all-contents (space model query)
  (list-contents space (model-name model) model query :status :all))
