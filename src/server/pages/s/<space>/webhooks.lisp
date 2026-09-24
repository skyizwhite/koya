(defpackage #:koya-server/pages/s/<space>/webhooks
  (:use #:cl #:hsx)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/db/schema-store #:load-schema)
  (:import-from #:koya/core/schema
                #:schema-models #:schema-webhooks #:model-name #:webhook-label)
  (:import-from #:koya-server/db/webhook-deliveries
                #:list-deliveries #:count-deliveries #:+keep-per-space+
                #:delivery-labels #:delivery-models
                #:delivery-id #:delivery-label #:delivery-url #:delivery-model #:delivery-event
                #:delivery-content-id #:delivery-ok #:delivery-status #:delivery-response
                #:delivery-error #:delivery-duration-ms #:delivery-created-at)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:set-title #:param #:short-time
                #:~layout #:~empty-state #:~icon #:action-refusal #:space-url #:content-url)
  (:export #:@get #:webhook-log-url #:browse-deliveries))
(in-package #:koya-server/pages/s/<space>/webhooks)

;;; One log per space: the last +KEEP-PER-SPACE+ calls it made and what came
;;; back. ?label= narrows it to one webhook, ?model= to the calls one model set
;;; off -- which includes the space's own hooks, since they fire for every model.
;;; Filtering and paging are an action that draws #deliveries again in place and
;;; puts the filters and page back in the URL.

(defparameter +page-size+ 20)

(defun blank-p (value) (or (null value) (zerop (length value))))

(defun filtered-p (label model) (not (and (blank-p label) (blank-p model))))

(defun webhook-log-url (space &key label model page)
  "This space's log, narrowed to LABEL and/or MODEL, at PAGE."
  (render-uri (make-uri :path (format nil "~a/webhooks" (space-url space))
                        :query (append (unless (blank-p label) `(("label" . ,label)))
                                       (unless (blank-p model) `(("model" . ,model)))
                                       (when (and page (> page 1)) `(("page" . ,page)))))))

(defun page-number (params)
  (max 1 (or (ignore-errors (parse-integer (or (param params "page") "1"))) 1)))

(defcomp ~outcome (&key delivery)
  (let* ((status (delivery-status delivery))
         (ok (delivery-ok delivery))
         (class (cond (ok "bg-ok/10 text-ok")
                      (status "bg-danger/10 text-danger")
                      (t "bg-warn/10 text-warn"))))
    (hsx (span :class (clsx "badge whitespace-nowrap" class)
           (cond (status (format nil "~a" status))
                 (t "no response"))))))

;;; The filters: the two selects both show what is filtered now and are how it is
;;; set. Picking one draws the log again at its first page, in place: the selects
;;; are outside what is drawn, so arrowing through a closed one keeps its focus
;;; and only redraws the list at each step.
;;;
;;; The options are the schema's -- every model of the space, every webhook that
;;; can fire for it -- plus anything the log holds that the schema no longer
;;; does, so a model or hook renamed away is still reachable.

(defun union-options (current logged selected)
  "CURRENT in the schema's own order, then whatever else the log holds, sorted,
then SELECTED if even that has not offered it. The last is what keeps the
select showing the filter it is under: an option the browser cannot find is an
option it silently replaces with the first one, which here reads \"All\"."
  (let ((options (append current
                         (sort (remove-if (lambda (value) (member value current :test #'string=)) logged)
                               #'string<))))
    (if (or (blank-p selected) (member selected options :test #'string=))
        options
        (append options (list selected)))))

(defun model-names (schema)
  (and schema (mapcar #'model-name (schema-models schema))))

(defun webhook-labels (schema)
  "Every webhook that can fire for the space."
  (and schema
       (remove-duplicates (mapcar #'webhook-label (schema-webhooks schema))
                          :test #'string= :from-end t)))

(defcomp ~filter-select (&key name label all options selected)
  (hsx
   (span :class "flex items-center gap-2"
     (label :for name :class "text-sm text-muted" label)
     (select :id name :name name :class "text-sm"
       (option :value "" :selected (blank-p selected) all)
       (loop :for value :in options :collect
         (hsx (option :value value :selected (equal value selected) value)))))))

(defcomp ~filters (&key space schema label model oob)
  ;; SCHEMA comes from @GET: loading it reads and parses every model of the space,
  ;; so it is loaded once a request, not once a lookup
  (let ((labels (union-options (webhook-labels schema) (delivery-labels space) label))
        (models (union-options (model-names schema) (delivery-models space) model)))
    (hsx
     (<> (unless (and (null labels) (null models))
           (hsx
            (form :id "filters" :method "get" :action (format nil "~a/webhooks" (space-url space))
                  :hx-get (browse-deliveries :space space) :hx-target "#deliveries" :hx-swap "outerHTML"
                  ;; the change of either select, as it bubbles: from:'find select' would be the first alone
                  :hx-trigger "change, submit" :hx-swap-oob (and oob "true")
                  :class "mb-6 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-md border border-line bg-panel px-4 py-3"
              (~filter-select :name "label" :label "Webhook" :all "All webhooks"
                              :options labels :selected label)
              (~filter-select :name "model" :label "Model" :all "All models"
                              :options models :selected model))))))))

(defcomp ~field (&key label children)
  (hsx
   (div :class "flex gap-2"
     (span :class "w-24 shrink-0 text-muted" label)
     (div :class "min-w-0 flex-1 break-all" children))))

(defcomp ~body-block (&key text)
  (if (blank-p text)
      (hsx (span :class "text-muted" "(empty)"))
      (hsx (pre :class "mt-1 max-h-64 overflow-auto whitespace-pre-wrap break-all rounded border border-line bg-base px-2 py-1 font-mono text-xs"
             text))))

(defcomp ~delivery (&key space delivery)
  (hsx
   (details :class "group"
     (summary :class "row-toggle flex cursor-pointer items-center justify-between gap-3 px-4 py-3 hover:bg-base"
       (span :class "flex min-w-0 items-center gap-3"
         ;; the chevron turns down when the row is open
         (span :class "text-muted transition-transform group-open:rotate-90" (~icon :name :next))
         (~outcome :delivery delivery)
         ;; on a narrow screen the model goes under the webhook
         (span :class "min-w-0"
           (span :class "font-medium" (delivery-label delivery))
           (code :class "block truncate text-xs text-muted sm:ml-2 sm:inline" (delivery-model delivery))))
       ;; "2026-09-20 14:04 JST": on a narrow screen the date above the time and zone
       (let* ((time (short-time (delivery-created-at delivery)))
              (space-at (position #\Space time)))
         (hsx (span :class "shrink-0 whitespace-nowrap text-right text-sm text-muted"
                (span :class "block sm:inline" (subseq time 0 space-at))
                (span :class "block sm:ml-1 sm:inline" (if space-at (subseq time (1+ space-at)) ""))))))
     (div :class "space-y-2 border-t border-line bg-base/50 px-4 py-3 text-sm"
       (~field :label "event" (delivery-event delivery))
       (~field :label "POST" (code :class "text-xs" (delivery-url delivery)))
       (~field :label "content"
         (a :href (content-url space (delivery-model delivery) (delivery-content-id delivery))
            :class "hover:underline"
            (code :class "text-xs" (delivery-content-id delivery))))
       (~field :label "took"
         (if (delivery-duration-ms delivery)
             (hsx (format nil "~a ms" (delivery-duration-ms delivery)))
             (hsx (span :class "text-muted" "-"))))
       (unless (blank-p (delivery-error delivery))
         (hsx (~field :label "error"
                (span :class "text-danger" (delivery-error delivery)))))
       (~field :label "response" (~body-block :text (delivery-response delivery)))))))

(defcomp ~delivery-count (&key space label model oob)
  (let ((total (count-deliveries space :label label :model model)))
    (hsx (p :id "delivery-count" :class "mb-4 text-sm text-muted" :hx-swap-oob (and oob "true")
           (format nil "~a call~:p~a. The newest ~a of the space are kept." total
                   (cond ((not (filtered-p label model)) "")
                         ((= total 1) " matches")
                         (t " match"))
                   +keep-per-space+)))))

(defcomp ~deliveries (&key space label model page)
  "What a filter or a page draws again: the calls and their pager."
  (let* ((total (count-deliveries space :label label :model model))
         (pages (max 1 (ceiling total +page-size+)))
         (page (min page pages))
         (items (list-deliveries space :label label :model model
                                       :limit +page-size+ :offset (* (1- page) +page-size+))))
    (flet ((page-link (n)
             (hsx (a :href (webhook-log-url space :label label :model model :page n)
                     :hx-get (browse-deliveries :space space :label (or label "") :model (or model "") :page n)
                     :hx-target "#deliveries" :hx-swap "outerHTML" :class "btn"
                     (if (< n page)
                         (hsx (<> (~icon :name :prev) "Previous"))
                         (hsx (<> "Next" (~icon :name :next))))))))
      (hsx
       (div :id "deliveries"
         (when (filtered-p label model)
           (hsx (p :class "-mt-3 mb-3 text-sm"
                  (a :href (webhook-log-url space)
                     :hx-get (browse-deliveries :space space :clear "1") :hx-target "#deliveries" :hx-swap "outerHTML"
                     :class "text-muted hover:text-fg hover:underline"
                    "Clear the filters"))))
         (if (null items)
             (hsx (~empty-state (if (filtered-p label model)
                                    "Nothing matches these filters."
                                    "Nothing has been delivered yet.")))
             (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                    (loop :for delivery :in items :collect
                      (hsx (li (~delivery :space space :delivery delivery)))))))
         (when (> pages 1)
           (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                  (when (> page 1) (page-link (1- page)))
                  (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                  (when (< page pages) (page-link (1+ page)))))))))))

(defcomp ~log-page (&key space schema label model page)
  (hsx
   (~layout :space space :crumbs (list (cons "Webhooks" nil))
     (h1 :class "mb-2 text-2xl font-bold" "Webhooks")
     (~delivery-count :space space :label label :model model)
     (~filters :space space :schema schema :label label :model model)
     (~deliveries :space space :label label :model model :page page))))

(defaction browse-deliveries :get (params)
  (let* ((space (param params "space"))
         (schema (and space (load-schema space)))
         (clear (equal (param params "clear") "1"))
         (label (and (not clear) (param params "label")))
         (model (and (not clear) (param params "model")))
         (pages (and schema (max 1 (ceiling (count-deliveries space :label label :model model) +page-size+))))
         (page (and schema (min (page-number params) pages))))
    (cond ((null schema) (action-refusal "Space not found." 404))
          (t
           (set-response-header :hx-replace-url (webhook-log-url space :label label :model model :page page))
           (hsx (<> (~deliveries :space space :label label :model model :page page)
                    (~delivery-count :space space :label label :model model :oob t)
                    (if clear
                        (hsx (~filters :space space :schema schema :oob t))
                        (hsx (<>)))))))))

(defun @get (params)
  (with-owner
    (let* ((name (path-param params :space))
           (schema (load-schema name)))
      (cond ((null schema)
             (set-response-status 404)
             (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            (t
             (set-title (format nil "Webhooks · ~a · koya" name))
             (hsx (~log-page :space name
                             :schema schema
                             :label (param params "label")
                             :model (param params "model")
                             :page (page-number params))))))))
