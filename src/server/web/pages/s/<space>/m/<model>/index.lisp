(defpackage #:koya-server/web/pages/s/<space>/m/<model>/index
  (:use #:cl #:hsx)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:cl-ppcre #:regex-replace-all)
  (:import-from #:koya/core/schema
                #:model-kind #:model-name #:model-fields #:field-name #:field-type
                #:webhook-covers-p)
  (:import-from #:koya/core/json #:json-null)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:find-space #:find-model #:space-webhooks)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-status #:content-data #:+statuses+ #:content-label)
  (:import-from #:koya-server/web/http #:path-param #:redirect-to #:param #:form-values #:blank-p)
  (:import-from #:koya-server/web/paging #:+page-size+ #:page-number)
  (:import-from #:koya-server/web/display #:short-time)
  (:import-from #:koya-server/web/urls #:content-url #:model-url)
  (:import-from #:koya-server/web/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/elements #:~status-badge #:~empty-state)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast #:~toast-oob #:action-refusal)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/usecases/contents/listing
                #:parse-sort #:content-page #:page-media #:count-contents #:find-object-content)
  (:import-from #:koya-server/usecases/contents/labels #:reference-labels)
  (:import-from #:koya-server/usecases/contents/bulk #:bulk-action-p #:apply-to-each)
  (:import-from #:koya-server/web/forms #:number->string)
  (:import-from #:koya-server/web/presenters #:media-url)
  (:import-from #:koya-server/web/pages/s/<space>/webhooks #:webhook-log-url)
  (:import-from #:koya-server/domain/media #:media-alt)
  (:export #:@get #:bulk-contents #:browse-contents))
(in-package #:koya-server/web/pages/s/<space>/m/<model>/index)

(defun list-url (space model &key search-text status sort-key (page 1))
  "This model's list with the search, filter, sort and page it is being read at."
  (render-uri (make-uri :path (model-url space model)
                        :query (append (unless (blank-p search-text) `(("q" . ,search-text)))
                                       (unless (blank-p status) `(("status" . ,status)))
                                       (unless (blank-p sort-key) `(("sort" . ,sort-key)))
                                       (when (> page 1) `(("page" . ,page)))))))

(defparameter +preview-length+ 120
  "Longest field preview carried into the list, in characters: a guard against
putting a whole richtext body in the HTML. The visible cut is the browser's.")

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
  "Bounds for a list column, per field type. The minimum keeps a column readable
and lets a wide model outgrow the page; the maximum stops one long text field
taking the whole width.")

(defun column-width (field)
  "Width bounds for FIELD's column, as classes on the cell's inner box."
  (or (cdr (assoc (field-type field) +column-widths+)) "min-w-24 max-w-48"))

(defparameter +row-height+ "h-14"
  "Two text-sm lines plus padding. On the row, not the cell, so that a shorter
preview is centred with the badge and the chevron.")

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

(defcomp ~media-cell (&key field id media)
  "The image itself, at the row's height. It is the original file -- koya keeps
no smaller copy -- so it is loaded lazily, and a list of a model with large
images costs what the images cost, once, then comes from the cache."
  (let ((found (gethash id media)))
    (hsx
     (td :class (clsx "py-2 pr-4" (if found "" "text-muted"))
       (div :class (column-width field)
         (if found
             (hsx (img :src (media-url found :absolute nil) :alt (media-alt found)
                       :loading "lazy" :decoding "async"
                       :class "h-10 w-10 rounded object-cover"))
             (hsx (div :class "line-clamp-2 break-all" (format nil "~a (missing)" id)))))))))

(defcomp ~preview-cell (&key field content ref-labels media)
  (let* ((data (content-data content :draft t))
         (value (and data (gethash (field-name field) data))))
    (if (and (eq (field-type field) :media) (stringp value) (plusp (length value)))
        (hsx (~media-cell :field field :id value :media media))
        (let ((preview (field-preview field data ref-labels)))
          (hsx (td :class (clsx "py-2 pr-4" (if preview "" "text-muted"))
                 (div :class (clsx "line-clamp-2" (column-width field)) (or preview "—"))))))))

(defun browse-url (space model state &key (search-text (getf state :search-text)) (status (getf state :status))
                                             (sort-key (getf state :sort-key)) (page (getf state :page)) clear)
  "The action that draws #contents for STATE, with any part of it replaced."
  (browse-contents :space space :model model :q (or search-text "") :status (or status "")
                   :sort (or sort-key "") :page page :clear (if clear "1" "")))

(defcomp ~sort-input (&key sort-key oob)
  "The sort the filters send along. A header's link changes it, so the answer to one
puts it back out of band -- this input alone, not the box being typed in."
  (hsx (input :type "hidden" :id "filter-sort" :name "sort" :value (or sort-key "")
              :hx-swap-oob (and oob "true"))))

(defcomp ~filters (&key space model search-text status sort-key oob)
  "The search box and the status filter. Typing, or picking a status, draws the
list again at its first page; the box is outside what is drawn, so it keeps its
focus. Without JavaScript it is a GET form."
  (hsx
   (form :id "filters" :method "get" :action (model-url space model)
         :hx-get (browse-contents :space space :model model) :hx-target "#contents" :hx-swap "outerHTML"
         ;; find is the first match only: one search box and one select, so each is named
         :hx-trigger "input changed delay:300ms from:'find input[type=search]', change from:'find select', submit"
         :hx-swap-oob (and oob "true")
         :class "mb-6 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-md border border-line bg-panel px-4 py-3"
     (~sort-input :sort-key sort-key)
     (input :type "search" :name "q" :value (or search-text "") :placeholder "Search text and ids"
            :aria-label "Search" :class "input w-64 max-w-full")
     (span :class "flex items-center gap-2"
       (label :for "status" :class "text-sm text-muted" "Status")
       (select :id "status" :name "status" :class "text-sm"
         (option :value "" :selected (blank-p status) "All")
         (loop :for value :in +statuses+ :collect
           (hsx (option :value value :selected (equal value status) value))))))))

(defcomp ~column-header (&key space model field state)
  "The header sorts by its field; clicking the sorted one turns it around."
  (let* ((name (field-name field))
         (active (equal name (getf state :sort-name)))
         (next (if (and active (eq (getf state :sort-direction) :asc)) (format nil "-~a" name) name)))
    (hsx
     (th :class "py-2 pr-4 font-medium"
       (a :href (list-url space model :search-text (getf state :search-text) :status (getf state :status) :sort-key next)
          :hx-get (browse-url space model state :sort-key next :page 1) :hx-target "#contents" :hx-swap "outerHTML"
          :class "flex items-center gap-1 hover:text-fg"
         (span :class (clsx "truncate" (column-width field)) name)
         (when active
           (hsx (span :class "shrink-0 text-accent" (if (eq (getf state :sort-direction) :asc) "↑" "↓")))))))))

(defcomp ~bulk-bar (&key space model state)
  "What can be done to a selection. Hidden until there is one (koya-editor.js).
Each button is an action on the selection form's boxes."
  (flet ((url (op)
           (bulk-contents :space space :model model :op op
                          :q (or (getf state :search-text) "") :status (or (getf state :status) "")
                          :sort (or (getf state :sort-key) "") :page (getf state :page))))
    (hsx
     (div :data-bulk-bar t :hidden t
          :class "mb-3 flex flex-wrap items-center gap-2 rounded-md border border-line bg-panel px-4 py-2 text-sm"
       (span :data-bulk-count t :class "mr-2 text-muted" "0 selected")
       (button :type "submit" :class "btn" :hx-post (url "publish") :hx-target "#contents" :hx-swap "outerHTML"
         (~icon :name :publish) "Publish")
       (button :type "submit" :class "btn" :hx-post (url "unpublish") :hx-target "#contents" :hx-swap "outerHTML"
         (~icon :name :unpublish) "Unpublish")
       (button :type "submit" :class "btn btn-danger" :hx-post (url "delete") :hx-target "#contents" :hx-swap "outerHTML"
               :hx-confirm "Delete the selected contents? This cannot be undone."
         (~icon :name :delete) "Delete")))))

(defun read-state (params model)
  "What the list is being read at, from the query string: page, search, status, sort."
  (let ((status (let ((s (param params "status"))) (and (member s +statuses+ :test #'equal) s))))
    (multiple-value-bind (sort-name sort-direction) (parse-sort (param params "sort") model)
      (list :page (page-number params) :search-text (param params "q") :status status
            :sort-name sort-name :sort-direction sort-direction
            :sort-key (and sort-name (if (eq sort-direction :desc) (format nil "-~a" sort-name) sort-name))))))

(defun fetch-page (space model state)
  "(values CONTENTS TOTAL PAGES) of STATE's page."
  (content-page space model :page (getf state :page) :page-size +page-size+
                            :search-text (getf state :search-text)
                            :status (getf state :status)
                            :sort-name (getf state :sort-name) :sort-direction (getf state :sort-direction)))

(defun filtered-p (state)
  (not (and (blank-p (getf state :search-text)) (blank-p (getf state :status)))))

(defcomp ~content-count (&key space model state total oob)
  (hsx (span :id "content-count" :class "ml-3 text-base font-normal text-muted" :hx-swap-oob (and oob "true")
         (if (filtered-p state)
             (format nil "~a of ~a" total (count-contents space (model-name model)))
             (format nil "~a content~:p" total)))))

(defcomp ~content-list (&key space model state contents pages)
  "What a search, a sort, a page or a bulk action draws again: the table and its pager."
  (let* ((model-name (model-name model))
         (fields (model-fields model))
         (ref-labels (reference-labels space model contents))
         (media (page-media space model contents))
         (page (getf state :page))
         (search-text (getf state :search-text))
         (status (getf state :status)))
    (flet ((page-link (n)
             (hsx (a :href (list-url space model-name :search-text search-text :status status
                                                      :sort-key (getf state :sort-key) :page n)
                     :hx-get (browse-url space model-name state :page n) :hx-target "#contents" :hx-swap "outerHTML"
                     :class "btn"
                     (if (< n page)
                         (hsx (<> (~icon :name :prev) "Previous"))
                         (hsx (<> "Next" (~icon :name :next))))))))
      (hsx
       (div :id "contents"
         (when (filtered-p state)
           (hsx (p :class "-mt-3 mb-3 text-sm"
                  (a :href (list-url space model-name :sort-key (getf state :sort-key))
                     :hx-get (browse-url space model-name state :search-text "" :status "" :page 1 :clear t)
                     :hx-target "#contents" :hx-swap "outerHTML"
                     :class "text-muted hover:text-fg hover:underline"
                    "Clear the search and filter"))))
         (if (null contents)
             (hsx (~empty-state (cond ((not (blank-p search-text)) "Nothing matches this search.")
                                      ((not (blank-p status)) "No contents with this status.")
                                      (t "No contents yet."))))
             (hsx (form :data-bulk t
                    (~bulk-bar :space space :model model-name :state state)
                    (div :class "overflow-x-auto rounded-md border border-line bg-panel"
                      (table :class "w-full text-sm"
                        (thead (tr :class "border-b border-line text-left text-muted"
                                 (th :class "py-2 pl-4 pr-2"
                                   (input :type "checkbox" :data-bulk-all t
                                          :aria-label "Select every content on this page"))
                                 (th :class "py-2 pr-4 font-medium whitespace-nowrap" "status")
                                 (loop :for field :in fields :collect
                                   (hsx (~column-header :space space :model model-name :field field :state state)))
                                 (th)))
                        (tbody :class "divide-y divide-line"
                          (loop :for content :in contents :collect
                            ;; the whole row opens the editor: the link in its last cell
                            ;; covers the row, and the box sits above it
                            (hsx (tr :class (clsx "group relative transition hover:bg-base" +row-height+)
                                   (td :class "relative z-10 py-2 pl-4 pr-2"
                                     (input :type "checkbox" :name "id" :data-bulk-item t
                                            :value (content-id content)
                                            :aria-label (format nil "Select ~a" (content-label content model))))
                                   (td :class "py-2 pr-4 whitespace-nowrap"
                                     (~status-badge :status (content-status content)))
                                   (loop :for field :in fields :collect
                                     (hsx (~preview-cell :field field :content content :ref-labels ref-labels :media media)))
                                   (td :class "py-2 pl-4 pr-4 text-right text-muted group-hover:text-accent"
                                     (a :href (content-url space model-name (content-id content))
                                        :class "after:absolute after:inset-0"
                                        :aria-label (format nil "Open ~a" (content-label content model))
                                       "›")))))))))))
         (when (> pages 1)
           (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                  (when (> page 1) (page-link (1- page)))
                  (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                  (when (< page pages) (page-link (1+ page)))))))))))

(defcomp ~list-page (&key space model state contents total pages)
  (let ((model-name (model-name model)))
    (hsx
     (~layout :space space :crumbs (list (cons model-name nil))
       (div :class "mb-6 flex flex-wrap items-center justify-between gap-3"
         (h1 :class "text-2xl font-bold" model-name
           (~content-count :space space :model model :state state :total total))
         (div :class "flex items-center gap-2"
           ;; only where a hook can fire, or the log can hold nothing
           (when (some (lambda (h) (webhook-covers-p h model-name)) (space-webhooks space))
             (hsx (a :href (webhook-log-url space :model model-name) :class "btn"
                     (~icon :name :webhook) "Webhooks")))
           (a :href (content-url space model-name "new") :class "btn btn-primary"
              (~icon :name :plus) "New content")))
       (~filters :space space :model model-name :search-text (getf state :search-text)
                 :status (getf state :status) :sort-key (getf state :sort-key))
       (~content-list :space space :model model :state state :contents contents :pages pages)))))

(defun answer-list (space model state &key message kind clear)
  "#contents for STATE (at its last page when it asks for one past the end), the
count, the sort the filters send, and the URL the list is now read at."
  (multiple-value-bind (contents total pages) (fetch-page space model state)
    (when (> (getf state :page) pages)
      (setf (getf state :page) pages)
      (multiple-value-setq (contents total pages) (fetch-page space model state)))
    (let ((model-name (model-name model)))
      (set-response-header :hx-replace-url
                           (list-url space model-name :search-text (getf state :search-text) :status (getf state :status)
                                                      :sort-key (getf state :sort-key) :page (getf state :page)))
      (hsx (<> (~content-list :space space :model model :state state :contents contents :pages pages)
               (~content-count :space space :model model :state state :total total :oob t)
               (if clear
                   (hsx (~filters :space space :model model-name :sort-key (getf state :sort-key) :oob t))
                   (hsx (~sort-input :sort-key (getf state :sort-key) :oob t)))
               (if message (hsx (~toast-oob :message message :kind kind)) (hsx (<>))))))))

(defun @get (params)
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
           (let ((state (read-state params model)))
             (multiple-value-bind (contents total pages) (fetch-page space model state)
               (if (> (getf state :page) pages)
                   ;; past the end: a link to a page that has since emptied
                   (redirect-to (list-url space model-name :search-text (getf state :search-text)
                                                           :status (getf state :status)
                                                           :sort-key (getf state :sort-key) :page pages)
                                302)
                   (hsx (~list-page :space space :model model :state state
                                    :contents contents :total total :pages pages)))))))))

(defun bulk-message (action done skipped failed message)
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

(defaction bulk-contents :post (params)
  (let* ((space (param params "space"))
         (model (and space (find-space space) (find-model space (or (param params "model") ""))))
         (op (param params "op"))
         (ids (form-values params "id")))
    (cond ((or (null model) (not (bulk-action-p op)))
           (action-refusal "Unknown model or action." 404))
          (t
           (multiple-value-bind (message kind)
               (if (null ids)
                   (values "Nothing was selected." :error)
                   (multiple-value-bind (done skipped failed first) (apply-to-each space model ids op)
                     (values (bulk-message op done skipped failed first) (if (plusp failed) :error :ok))))
             ;; a page emptied by a delete shows the last one there still is
             (answer-list space model (read-state params model) :message message :kind kind))))))

(defaction browse-contents :get (params)
  (let* ((space (param params "space"))
         (model (and space (find-space space) (find-model space (or (param params "model") "")))))
    (if (and model (eq (model-kind model) :list))
        (answer-list space model (read-state params model) :clear (equal (param params "clear") "1"))
        (action-refusal "Unknown model." 404))))
