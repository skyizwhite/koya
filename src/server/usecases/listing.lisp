(defpackage #:koya-server/usecases/listing
  (:use #:cl)
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

;;; A model's contents a page at a time, searched, filtered by status and
;;; sorted. All three make a delivery API query (domain/query), which the store
;;; turns into a WHERE and an ORDER BY over the JSON.

(defun empty-p (string) (or (null string) (string= string "")))

(defparameter +searchable-types+ '(:text :textarea :slug :richtext)
  "Field types a search looks inside. :RICHTEXT is searched as the HTML it is
stored as, so a query that reads like markup can match a tag.")

(defun search-filters (model search-text)
  "Filter groups matching SEARCH-TEXT against every searchable field of MODEL and
against its id whole, OR'ed together by BUILD-WHERE. Whole, because ids made in
the same period share a prefix and a short query would match them all."
  (let ((text-fields (loop :for field :in (model-fields model)
                           :when (member (field-type field) +searchable-types+)
                             :collect (field-name field))))
    (cons (list (list "id" "equals" search-text))
          (mapcar (lambda (name) (list (list name "contains" search-text))) text-fields))))

(defun sortable-p (model name)
  (and (not (empty-p name))
       (or (model-field model name)
           (member name +system-fields+ :test #'string=))))

(defun parse-sort (raw model)
  "(values NAME DIRECTION) for ?sort=, or NIL when it names nothing sortable: a
stale link falls back to the default order."
  (let* ((desc (and (not (empty-p raw)) (char= (char raw 0) #\-)))
         (name (and (not (empty-p raw)) (if desc (subseq raw 1) raw))))
    (when (sortable-p model name)
      (values name (if desc :desc :asc)))))

(defun sort-orders (name direction)
  "ORDERS for the query. Without a sort the list is newest created first."
  (if name (list (cons name direction)) (list (cons "createdAt" :desc))))

(defun content-page (space model &key (page 1) page-size search-text status sort-name sort-direction)
  "(values CONTENTS TOTAL PAGES): PAGE of MODEL's contents, PAGE-SIZE to a page,
matching SEARCH-TEXT, in STATUS (one of +STATUSES+, or NIL for any), in the order
SORT-NAME and SORT-DIRECTION give."
  (let ((query (make-query :limit page-size
                           :offset (* (1- page) page-size)
                           :orders (sort-orders sort-name sort-direction)
                           :filters (unless (empty-p search-text) (search-filters model search-text)))))
    (multiple-value-bind (contents total)
        (list-contents space (model-name model) model query :status :all :only-status status)
      (values contents total (max 1 (ceiling total page-size))))))

(defun page-media (space model contents)
  "Hash of media id -> media for every media field of CONTENTS, the page's rows.
An id missing from it is no longer in the library."
  (find-media-by-ids
   space
   (loop :for content :in contents
         :for data := (content-data content :draft t)
         :nconc (loop :for field :in (model-fields model)
                      :for value := (and data (gethash (field-name field) data))
                      :when (and (eq (field-type field) :media) (stringp value) (plusp (length value)))
                        :collect value))))

(defun all-contents (space model query)
  "(values CONTENTS TOTAL): what QUERY asks for of MODEL's contents, drafts
included, each with its draft data where it has one."
  (list-contents space (model-name model) model query :status :all))

;;; What a reference field offers, and what the ids it holds are called.

(defun reference-options (space field)
  "Every content of FIELD's target model as (id . label), sorted by label, drafts
included: a reference may be set to one before it is published. Every one, so a
selected id is never taken for missing."
  (when (eq (field-type field) :reference)
    (let ((target (find-model space (field-option field :model))))
      (when target
        (sort (mapcar (lambda (content) (cons (content-id content) (content-label content target)))
                      (list-contents space (model-name target) target (make-query :limit nil) :status :all))
              #'string-lessp :key #'cdr)))))

(defun referenced-ids (field contents)
  "The ids FIELD holds across CONTENTS, one or an array each."
  (loop :for content :in contents
        :for data := (content-data content :draft t)
        :for value := (and data (gethash (field-name field) data))
        :nconc (cond ((stringp value) (list value))
                     ((vectorp value) (remove-if-not #'stringp (coerce value 'list))))))

(defun reference-labels (space model contents)
  "Field name -> hash of referenced id -> label, for every reference field of MODEL,
covering the ids CONTENTS hold. An id missing from it no longer resolves."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) table)
      (when (eq (field-type field) :reference)
        (let ((target (find-model space (field-option field :model)))
              (labels (make-hash-table :test 'equal)))
          (when target
            (maphash (lambda (id content) (setf (gethash id labels) (content-label content target)))
                     (find-contents-by-ids space (model-name target) (referenced-ids field contents))))
          (setf (gethash (field-name field) table) labels))))))
