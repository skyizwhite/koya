(defpackage #:koya-server/pages/s/<space>/webhooks
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
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
                #:~layout #:~empty-state #:~icon #:space-url #:content-url)
  (:export #:@get #:webhook-log-url))
(in-package #:koya-server/pages/s/<space>/webhooks)

;;; One log per space, holding the last +KEEP-PER-SPACE+ webhook calls it made:
;;; whether the receiver accepted each one, and what it answered. The same page
;;; serves every narrower view through ?label= (one webhook) and ?model= (one
;;; model). A space's webhooks fire for every model, so a model's view holds
;;; their calls as well as that model's own webhooks'.

(defparameter +page-size+ 20 "Rows per page, as everywhere else in the admin UI.")

(defun blank-p (value) (or (null value) (zerop (length value))))

(defun filtered-p (label model) (not (and (blank-p label) (blank-p model))))

(defun webhook-log-url (space &key label model page)
  "This space's log, narrowed to LABEL and/or MODEL, at PAGE."
  (let ((query (append (unless (blank-p label) (list (format nil "label=~a" (quri:url-encode label))))
                       (unless (blank-p model) (list (format nil "model=~a" (quri:url-encode model))))
                       (when (and page (> page 1)) (list (format nil "page=~a" page))))))
    (format nil "~a/webhooks~@[?~{~a~^&~}~]" (space-url space) query)))

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

;;; The filters, as a plain GET form: the two selects both show what is filtered
;;; now and are how it is set, and Filter applies them. Submitting on change
;;; instead would cost the keyboard its choice -- arrowing a closed select fires
;;; change on every step -- so the button stays. Submitting drops ?page= and
;;; starts at the first again.
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

(defcomp ~filters (&key space schema label model)
  ;; SCHEMA comes from @GET: loading it reads and parses every model of the space,
  ;; so it is loaded once a request, not once a lookup
  (let ((labels (union-options (webhook-labels schema) (delivery-labels space) label))
        (models (union-options (model-names schema) (delivery-models space) model)))
    (hsx
     (<> (unless (and (null labels) (null models))
           (hsx
            (form :method "get" :action (format nil "~a/webhooks" (space-url space))
                  :class "mb-6 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-md border border-line bg-panel px-4 py-3"
              (~filter-select :name "label" :label "Webhook" :all "All webhooks"
                              :options labels :selected label)
              (~filter-select :name "model" :label "Model" :all "All models"
                              :options models :selected model)
              (button :type "submit" :class "btn" (~icon :name :search) "Filter")
              (when (filtered-p label model)
                (hsx (a :href (webhook-log-url space) :class "btn" (~icon :name :close) "Clear"))))))))))

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
         (span :class "min-w-0"
           (span :class "font-medium" (delivery-event delivery))
           (span :class "text-muted" " · ")
           (span (delivery-model delivery))
           (code :class "ml-2 truncate text-xs text-muted" (delivery-label delivery))))
       (span :class "shrink-0 whitespace-nowrap text-sm text-muted"
         (short-time (delivery-created-at delivery))))
     (div :class "space-y-2 border-t border-line bg-base/50 px-4 py-3 text-sm"
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

(defcomp ~log-page (&key space schema label model page)
  (let* ((total (count-deliveries space :label label :model model))
         (pages (max 1 (ceiling total +page-size+)))
         (page (min page pages))
         (items (list-deliveries space :label label :model model
                                       :limit +page-size+ :offset (* (1- page) +page-size+))))
    (hsx
     (~layout :space space :crumbs (list (cons "Webhooks" nil))
       (h1 :class "mb-2 text-2xl font-bold" "Webhooks")
       (p :class "mb-4 text-sm text-muted"
         (format nil "~a call~:p~a." total
                 (cond ((not (filtered-p label model)) "")
                       ((= total 1) " matches")
                       (t " match")))
         (format nil " Only the newest ~a of the space are kept." +keep-per-space+))
       (~filters :space space :schema schema :label label :model model)
       (if (null items)
           (hsx (~empty-state (if (filtered-p label model)
                                  "Nothing matches these filters."
                                  "Nothing has been delivered yet.")))
           (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                  (loop :for delivery :in items :collect
                    (hsx (li (~delivery :space space :delivery delivery)))))))
       (when (> pages 1)
         (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                (when (> page 1)
                  (hsx (a :href (webhook-log-url space :label label :model model :page (1- page))
                          :class "btn" (~icon :name :prev) "Previous")))
                (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                (when (< page pages)
                  (hsx (a :href (webhook-log-url space :label label :model model :page (1+ page))
                          :class "btn" "Next" (~icon :name :next)))))))))))

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
