(defpackage #:koya-server/pages/s/<space>/m/<model>/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:cl-ppcre #:regex-replace-all)
  (:import-from #:koya/core/schema
                #:model-kind #:model-name #:model-fields #:model-field
                #:field-name #:field-type #:field-option
                #:webhook-covers-p #:+system-fields+)
  (:import-from #:koya/core/json #:json-null)
  (:import-from #:koya-server/db/schema-store #:find-space #:find-model #:space-webhooks)
  (:import-from #:koya-server/db/contents
                #:list-contents #:count-contents #:find-object-content
                #:content-id #:content-status #:content-data)
  (:import-from #:koya-server/lib/query #:make-query)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:redirect-to #:set-flash
                #:param #:short-time #:content-label
                #:~layout #:~status-badge #:~empty-state #:~icon #:content-url #:model-url)
  (:import-from #:koya-server/lib/content-service
                #:publish #:unpublish #:destroy)
  (:import-from #:koya-server/lib/forms #:number->string #:form-values)
  (:import-from #:koya-server/lib/http #:api-error #:api-error-message)
  (:import-from #:koya/core/validate #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/db/contents #:find-content #:content-published #:content-draft)
  (:import-from #:koya-server/pages/s/<space>/webhooks #:webhook-log-url)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/s/<space>/m/<model>/index)

(defparameter +page-size+ 100
  "Contents per page of the list, newest created first.")

(defun page-number (params)
  (max 1 (or (ignore-errors (parse-integer (or (param params "page") "1"))) 1)))

;;; Search, status and sort, all in the query string so that a list as someone is
;;; reading it is a link they can send or keep. They go through the same query
;;; machinery as the delivery API -- lib/query builds the WHERE and the ORDER BY
;;; over the JSON -- rather than a second way of asking the same questions.

(defparameter +searchable-types+ '(:text :textarea :slug :richtext)
  "Field types a search looks inside. A :RICHTEXT field is searched as the HTML it
is stored as, so a query that reads like markup can match a tag; the rest is the
text as it was typed.")

(defparameter +statuses+ '("draft" "published" "published+draft")
  "The status filter's choices: the three badges the list shows, so what is
filtered and what is read are the same word.")

(defun blank-p (value) (or (null value) (zerop (length value))))

(defun search-filters (model search-text)
  "Filter groups matching SEARCH-TEXT against every searchable field of MODEL, and
against its id whole, OR'ed together by BUILD-WHERE.

The id is matched whole rather than as a substring: ULIDs made in the same period
share a long prefix, so any short query would match every content by id and the
search would look broken. Pasting an id finds its content, which is what the id
is there for; finding one from a fragment of it is not."
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
  "(values NAME DIRECTION) for ?sort=, or NIL when it names nothing this model can
be sorted by -- a stale link orders by the default rather than failing."
  (let* ((desc (and (not (blank-p raw)) (char= (char raw 0) #\-)))
         (name (and (not (blank-p raw)) (if desc (subseq raw 1) raw))))
    (when (sortable-p model name)
      (values name (if desc :desc :asc)))))

(defun sort-orders (name direction)
  "ORDERS for the query. Without a sort the list is newest created first."
  (if name (list (cons name direction)) (list (cons "createdAt" :desc))))

(defun list-url (space model &key search-text status sort-key (page 1))
  "This model's list, as it is being read: the search, the filter, the sort and
the page it is on."
  (let ((query (append (unless (blank-p search-text) (list (format nil "q=~a" (quri:url-encode search-text))))
                       (unless (blank-p status) (list (format nil "status=~a" (quri:url-encode status))))
                       (unless (blank-p sort-key) (list (format nil "sort=~a" (quri:url-encode sort-key))))
                       (when (> page 1) (list (format nil "page=~a" page))))))
    (format nil "~a~@[?~{~a~^&~}~]" (model-url space model) query)))

(defparameter +preview-length+ 120
  "Longest field preview carried into the list, in characters.
A cell is two lines tall and ellipsises whatever does not fit, so this is only a
guard against putting a whole richtext body in the HTML: it sits above what the
widest column can show, which leaves the visible cut to the browser.")

(defparameter +column-widths+
  '((:text      . "min-w-32 max-w-56")
    (:textarea  . "min-w-36 max-w-64")
    (:richtext  . "min-w-36 max-w-64")
    (:number    . "min-w-16 max-w-24")
    (:boolean   . "min-w-16 max-w-20")
    (:date      . "min-w-24 max-w-28")
    (:datetime  . "min-w-32 max-w-40")
    (:select    . "min-w-24 max-w-36")
    (:media     . "min-w-24 max-w-36")
    (:reference . "min-w-32 max-w-48")
    (:slug      . "min-w-32 max-w-48"))
  "Bounds for a list column, per field type, as classes on the cell's inner box.
The minimum keeps a column readable and lets a wide model outgrow the page
rather than squeezing every column thin; the maximum stops one long text field
from taking the whole width. Between the two the preview sizes to its content.
They are deliberately tight: a preview gets two lines, so a narrow column still
shows a useful amount of text and more of the model fits on screen.")

(defun column-width (field)
  "Width bounds for FIELD's column, as classes on the cell's inner box."
  (or (cdr (assoc (field-type field) +column-widths+)) "min-w-24 max-w-48"))

(defparameter +row-height+ "h-14"
  "Two text-sm lines plus the cells' padding: the height of every row.
A preview is clamped to two lines, so no row outgrows it, and the height is set
on the row rather than the cell so that the cells' own middle alignment centres
a shorter preview — and the status badge and the chevron with it.")

(defun reference-labels (space model)
  "Field name -> hash of referenced id -> label, for every reference field of MODEL.
Components render lazily, so this is passed explicitly rather than bound dynamically."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) table)
      (when (eq (field-type field) :reference)
        (let ((target (find-model space (field-option field :model)))
              (targets (make-hash-table :test 'equal)))
          (when target
            (dolist (content (list-contents space (model-name target) target
                                            (make-query :limit 1000) :status :all))
              (setf (gethash (content-id content) targets) (content-label content target))))
          (setf (gethash (field-name field) table) targets))))))

(defun reference-label (field id ref-labels)
  (let ((table (and ref-labels (gethash (field-name field) ref-labels))))
    (or (and table (stringp id) (gethash id table)) id)))

(defun collapse-whitespace (string)
  (string-trim " " (regex-replace-all "\\s+" string " ")))

(defun strip-html (html)
  "Plain text of HTML: tags dropped, block boundaries become spaces, common entities decoded."
  (let ((text (regex-replace-all "<[^>]*>" html " ")))
    (dolist (pair '(("&nbsp;" . " ") ("&lt;" . "<") ("&gt;" . ">") ("&quot;" . "\"") ("&#39;" . "'") ("&amp;" . "&")))
      (setf text (regex-replace-all (car pair) text (cdr pair))))
    (collapse-whitespace text)))

(defun truncate-text (string &optional (limit +preview-length+))
  (if (> (length string) limit)
      (format nil "~a…" (subseq string 0 limit))
      string))

(defun scalar-preview (field value ref-labels)
  "Preview of one non-empty VALUE of FIELD as plain text. LABELS resolves references."
  (case (field-type field)
    (:richtext (strip-html value))
    (:datetime (short-time value))
    (:boolean (if value "Yes" "No"))
    (:number (if (realp value) (number->string value) (princ-to-string value)))
    (:reference (collapse-whitespace (princ-to-string (reference-label field value ref-labels))))
    (t (collapse-whitespace (princ-to-string value)))))

(defun field-preview (field data ref-labels)
  "Plain-text preview of FIELD in DATA, or NIL when the field is empty."
  (let ((value (and data (gethash (field-name field) data))))
    (cond ((eq value json-null) nil)
          ((eq (field-type field) :boolean)
           ;; a stored false is NIL, so only a missing key is "empty"
           (and data (nth-value 1 (gethash (field-name field) data))
                (scalar-preview field value ref-labels)))
          ((null value) nil)
          ((and (vectorp value) (not (stringp value)))
           (and (plusp (length value))
                (truncate-text (format nil "~{~a~^, ~}"
                                       (map 'list (lambda (v) (scalar-preview field v ref-labels)) value)))))
          ((and (stringp value) (zerop (length value))) nil)
          (t (truncate-text (scalar-preview field value ref-labels))))))

(defcomp ~preview-cell (&key field content ref-labels)
  (let ((preview (field-preview field (content-data content :draft t) ref-labels)))
    (hsx (td :class (clsx "py-2 pr-4" (if preview "" "text-muted"))
           (div :class (clsx "line-clamp-2" (column-width field)) (or preview "—"))))))

(defcomp ~filters (&key space model search-text status sort-key)
  "The search box and the status filter, as a plain GET form: what is filtered is
shown, and setting it is the same control. Submitting drops ?page= and starts at
the first again, and keeps the sort, which is the column headers' business."
  (hsx
   (form :method "get" :action (model-url space model)
         :class "mb-6 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-md border border-line bg-panel px-4 py-3"
     (if (blank-p sort-key) (hsx (<>)) (hsx (input :type "hidden" :name "sort" :value sort-key)))
     (input :type "search" :name "q" :value (or search-text "") :placeholder "Search text and ids"
            :class "input w-64 max-w-full")
     (span :class "flex items-center gap-2"
       (label :for "status" :class "text-sm text-muted" "Status")
       (select :id "status" :name "status" :class "text-sm"
         (option :value "" :selected (blank-p status) "All")
         (loop :for value :in +statuses+ :collect
           (hsx (option :value value :selected (equal value status) value)))))
     (button :type "submit" :class "btn" (~icon :name :search) "Filter")
     (if (and (blank-p search-text) (blank-p status))
         (hsx (<>))
         (hsx (a :href (list-url space model :sort-key sort-key) :class "btn" (~icon :name :close) "Clear"))))))

(defcomp ~column-header (&key space model field search-text status sort-name sort-direction)
  "A column header is the sort control: it orders by its own field, and clicking
the one already sorted turns it around."
  (let* ((name (field-name field))
         (active (equal name sort-name))
         (next (if (and active (eq sort-direction :asc)) (format nil "-~a" name) name)))
    (hsx
     (th :class "py-2 pr-4 font-medium"
       (a :href (list-url space model :search-text search-text :status status :sort-key next)
          :class "flex items-center gap-1 hover:text-fg"
         (span :class (clsx "truncate" (column-width field)) name)
         (if active
             (hsx (span :class "shrink-0 text-accent" (if (eq sort-direction :asc) "↑" "↓")))
             (hsx (<>))))))))

(defcomp ~bulk-bar ()
  "What can be done to a selection. Hidden until there is one (koya-editor.js),
and the count it shows is written into the delete question as well."
  (hsx
   (div :data-bulk-bar t :hidden t
        :class "mb-3 flex flex-wrap items-center gap-2 rounded-md border border-line bg-panel px-4 py-2 text-sm"
     (span :data-bulk-count t :class "mr-2 text-muted" "0 selected")
     (button :type "submit" :name "action" :value "publish" :class "btn" (~icon :name :publish) "Publish")
     (button :type "submit" :name "action" :value "unpublish" :class "btn" (~icon :name :unpublish) "Unpublish")
     (button :type "submit" :name "action" :value "delete" :class "btn btn-danger"
             :data-confirm "Delete the selected contents? This cannot be undone."
             :data-bulk-confirm "Delete the selected contents ({n})? This cannot be undone."
       (~icon :name :delete) "Delete"))))

(defun @get (params)
  (with-owner
    (let* ((space (path-param params :space))
           (model-name (path-param params :model))
           (model (and (find-space space) (find-model space model-name))))
      (cond ((null model)
             (set-response-status 404)
             (hsx (~layout :space space (h1 :class "text-xl font-bold" "Model not found"))))
            ((eq (model-kind model) :object)
             (let ((content (find-object-content space model-name)))
               (redirect-to (content-url space model-name (if content (content-id content) "new")) 302)))
            (t
             (set-title (format nil "~a · ~a · koya" model-name space))
             (let* ((page (page-number params))
                    (search-text (param params "q"))
                    (status (let ((s (param params "status")))
                              (and (member s +statuses+ :test #'equal) s)))
                    (raw-sort (param params "sort"))
                    (filtered (not (and (blank-p search-text) (blank-p status)))))
              (multiple-value-bind (sort-name sort-direction) (parse-sort raw-sort model)
               (let ((query (make-query :limit +page-size+
                                        :offset (* (1- page) +page-size+)
                                        :orders (sort-orders sort-name sort-direction)
                                        :filters (unless (blank-p search-text) (search-filters model search-text)))))
                (multiple-value-bind (contents total)
                    (list-contents space model-name model query :status :all :only-status status)
                 (let* ((fields (model-fields model))
                        (ref-labels (reference-labels space model))
                        (pages (max 1 (ceiling total +page-size+)))
                        (sort-key (and sort-name (if (eq sort-direction :desc) (format nil "-~a" sort-name) sort-name)))
                        (link (lambda (page) (list-url space model-name :search-text search-text :status status
                                                                       :sort-key sort-key :page page))))
                   (if (> page pages)
                       ;; past the end: deleting a whole page lands here, and so
                       ;; does a link kept from when there was more to read
                       (redirect-to (funcall link pages) 302)
                   (hsx
                    (~layout :space space :crumbs (list (cons model-name nil))
                      (div :class "mb-6 flex items-center justify-between"
                        (h1 :class "text-2xl font-bold" model-name
                          (span :class "ml-3 text-base font-normal text-muted"
                            (if filtered
                                (format nil "~a of ~a" total (count-contents space model-name))
                                (format nil "~a content~:p" total))))
                        (div :class "flex items-center gap-2"
                          ;; the space's log, narrowed to what this model set off;
                          ;; without a hook that can fire, that log can hold nothing
                          (if (some (lambda (h) (webhook-covers-p h model-name)) (space-webhooks space))
                              (hsx (a :href (webhook-log-url space :model model-name) :class "btn"
                                      (~icon :name :webhook) "Webhooks"))
                              (hsx (<>)))
                          (a :href (content-url space model-name "new") :class "btn btn-primary"
                             (~icon :name :plus) "New content")))
                      (~filters :space space :model model-name :search-text search-text :status status :sort-key sort-key)
                      (if (null contents)
                          (hsx (~empty-state (cond ((not (blank-p search-text)) "Nothing matches this search.")
                                                   ((not (blank-p status)) "No contents with this status.")
                                                   (t "No contents yet."))))
                          (hsx (form :method "post" :action (model-url space model-name) :data-bulk t
                                 (input :type "hidden" :name "q" :value (or search-text ""))
                                 (input :type "hidden" :name "status" :value (or status ""))
                                 (input :type "hidden" :name "sort" :value (or sort-key ""))
                                 (input :type "hidden" :name "page" :value (princ-to-string page))
                                 (~bulk-bar)
                                 (div :class "overflow-x-auto rounded-md border border-line bg-panel"
                                 (table :class "w-full text-sm"
                                   (thead (tr :class "border-b border-line text-left text-muted"
                                            (th :class "py-2 pl-4 pr-2"
                                              (input :type "checkbox" :data-bulk-all t
                                                     :aria-label "Select every content on this page"))
                                            (th :class "py-2 pr-4 font-medium whitespace-nowrap" "status")
                                            (loop :for field :in fields :collect
                                              (hsx (~column-header :space space :model model-name :field field
                                                                   :search-text search-text :status status
                                                                   :sort-name sort-name :sort-direction sort-direction)))
                                            (th)))
                                   (tbody :class "divide-y divide-line"
                                     (loop :for content :in contents :collect
                                       ;; the whole row opens the editor (see koya-editor.js)
                                       (hsx (tr :class (clsx "group cursor-pointer transition hover:bg-base" +row-height+)
                                                :data-href (content-url space model-name (content-id content))
                                                :tabindex "0" :role "link"
                                              ;; the row opens the editor, but not from inside the box
                                              (td :class "py-2 pl-4 pr-2"
                                                (input :type "checkbox" :name "id" :data-bulk-item t
                                                       :value (content-id content)
                                                       :aria-label (format nil "Select ~a" (content-label content model))))
                                              (td :class "py-2 pr-4 whitespace-nowrap"
                                                (~status-badge :status (content-status content)))
                                              (loop :for field :in fields :collect
                                                (hsx (~preview-cell :field field :content content :ref-labels ref-labels)))
                                              (td :class "py-2 pl-4 pr-4 text-right text-muted group-hover:text-accent" "›"))))))))))
                      (when (> pages 1)
                        (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                               (if (> page 1)
                                   (hsx (a :href (funcall link (1- page)) :class "btn" (~icon :name :prev) "Previous"))
                                   (hsx (<>)))
                               (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                               (if (< page pages)
                                   (hsx (a :href (funcall link (1+ page)) :class "btn" "Next" (~icon :name :next)))
                                   (hsx (<>)))))))))))))))))))

;;; Bulk actions. Each content goes through content-service one at a time, so the
;;; validation, the system timestamps and the webhooks are the same as for a
;;; single one, and each is its own transaction: a content that cannot be
;;; published -- a field made required after its draft was written -- leaves the
;;; rest to go through and is counted.

(defun bulk-action-function (action)
  (cond ((equal action "publish") #'publish)
        ((equal action "unpublish") #'unpublish)
        ((equal action "delete") #'destroy)))

(defun nothing-to-do-p (action content)
  "True when ACTION would change nothing about CONTENT. A selection is made with
one tick of the header box, so it holds whatever the page held: publishing what
is already published would give every one of them a new revisedAt and a webhook
for a change that did not happen, and unpublishing what is already a draft would
issue it a new draft key and break a preview link someone is holding."
  (and content
       (cond ((equal action "publish") (and (content-published content) (null (content-draft content))))
             ((equal action "unpublish") (null (content-published content)))
             (t nil))))

(defun failure-message (condition)
  "What to tell the owner about one that did not go through. A validation failure
is the field that stopped it, not the condition's own report."
  (typecase condition
    (validation-error
     (format nil "~{~a~^, ~}"
             (mapcar (lambda (e) (format nil "~a ~a" (getf e :field) (getf e :message)))
                     (validation-error-errors condition))))
    (api-error (api-error-message condition))
    (t (princ-to-string condition))))

(defun apply-to-each (space model ids action)
  "Do ACTION to each of IDS. Returns (values DONE SKIPPED FAILED FIRST-MESSAGE)."
  (let ((function (bulk-action-function action))
        (model-name (model-name model))
        (done 0)
        (skipped 0)
        (failed 0)
        (message nil))
    (dolist (id ids (values done skipped failed message))
      (handler-case
          (if (nothing-to-do-p action (find-content space model-name id))
              (incf skipped)
              (progn (funcall function space model id)
                     (incf done)))
        (error (e) (incf failed) (unless message (setf message (failure-message e))))))))

(defun bulk-flash (action done skipped failed message)
  (let ((verb (cond ((equal action "publish") "Published")
                    ((equal action "unpublish") "Unpublished")
                    (t "Deleted")))
        (already (if (equal action "publish") "already published" "not published")))
    (format nil "~a ~a content~:p.~@[ ~a.~]~@[ ~a.~]"
            verb done
            (when (plusp skipped)
              (format nil "~a ~:[was~;were~] ~a" skipped (> skipped 1) already))
            (when (plusp failed)
              (format nil "~a could not be~@[: ~a~]" failed message)))))

(defun @post (params)
  (with-owner-post
    (let* ((space (path-param params :space))
           (model-name (path-param params :model))
           (model (and (find-space space) (find-model space model-name)))
           (action (param params "action"))
           (ids (form-values params "id"))
           (back (list-url space model-name
                           :search-text (param params "q")
                           :status (param params "status")
                           :sort-key (param params "sort")
                           :page (page-number params))))
      (cond ((null model)
             (set-response-status 404)
             (hsx (~layout :space space (h1 :class "text-xl font-bold" "Model not found"))))
            ((null (bulk-action-function action))
             (set-response-status 400)
             (hsx (~layout :space space (p "Unknown action"))))
            ((null ids)
             (set-flash "Nothing was selected." :error)
             (redirect-to back))
            (t
             (multiple-value-bind (done skipped failed message) (apply-to-each space model ids action)
               (set-flash (bulk-flash action done skipped failed message)
                          (if (plusp failed) :error :ok)))
             (redirect-to back))))))
