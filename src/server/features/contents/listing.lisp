(defpackage #:koya-server/features/contents/listing
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-name #:model-fields #:model-field #:field-name #:field-type #:+system-fields+)
  (:import-from #:koya-server/db/contents #:list-contents)
  (:import-from #:koya-server/domain/content #:content-data)
  (:import-from #:koya-server/db/media
                #:find-media-by-ids)
  (:import-from #:koya-server/domain/query #:make-query)
  (:import-from #:koya-server/lib/http
                #:blank-p)
  (:import-from #:koya-server/lib/paging
                #:+page-size+ #:page-offset #:last-page)
  (:export #:parse-sort
           #:content-page
           #:page-media))
(in-package #:koya-server/features/contents/listing)

;;; A model's contents a page at a time, searched, filtered by status and
;;; sorted. All three make a delivery API query (domain/query), which the store
;;; turns into a WHERE and an ORDER BY over the JSON.

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
  (and (not (blank-p name))
       (or (model-field model name)
           (member name +system-fields+ :test #'string=))))

(defun parse-sort (raw model)
  "(values NAME DIRECTION) for ?sort=, or NIL when it names nothing sortable: a
stale link falls back to the default order."
  (let* ((desc (and (not (blank-p raw)) (char= (char raw 0) #\-)))
         (name (and (not (blank-p raw)) (if desc (subseq raw 1) raw))))
    (when (sortable-p model name)
      (values name (if desc :desc :asc)))))

(defun sort-orders (name direction)
  "ORDERS for the query. Without a sort the list is newest created first."
  (if name (list (cons name direction)) (list (cons "createdAt" :desc))))

(defun content-page (space model &key (page 1) search-text status sort-name sort-direction)
  "(values CONTENTS TOTAL PAGES): PAGE of MODEL's contents, matching SEARCH-TEXT,
in STATUS (one of +STATUSES+, or NIL for any), in the order SORT-NAME and
SORT-DIRECTION give."
  (let ((query (make-query :limit +page-size+
                           :offset (page-offset page)
                           :orders (sort-orders sort-name sort-direction)
                           :filters (unless (blank-p search-text) (search-filters model search-text)))))
    (multiple-value-bind (contents total)
        (list-contents space (model-name model) model query :status :all :only-status status)
      (values contents total (last-page total)))))

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
