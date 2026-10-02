(defpackage #:koya-server/web/pages/s/<space>/webhooks
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/lib/binds #:on-search #:on-follow)
  (:import-from #:koya-core/schema
                #:schema-models #:schema-webhooks #:model-name #:webhook-label)
  (:import-from #:koya-server/usecases/webhooks
                #:list-deliveries #:count-deliveries #:delivery-labels #:delivery-models
                #:+deliveries-kept+)
  (:import-from #:koya-server/domain/webhook-delivery
                #:delivery-label #:delivery-url #:delivery-model #:delivery-event
                #:delivery-content-id #:delivery-ok #:delivery-status #:delivery-response
                #:delivery-error #:delivery-duration-ms #:delivery-created-at)
  (:import-from #:koya-server/web/lib/http #:path-param #:param #:blank-p)
  (:import-from #:koya-server/web/lib/paging #:+page-size+ #:page-number #:last-page #:page-offset)
  (:import-from #:koya-server/web/lib/display #:short-time)
  (:import-from #:koya-server/web/lib/urls #:space-url #:content-url #:webhook-log-url)
  (:import-from #:koya-server/web/lib/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout #:~missing)
  (:import-from #:koya-server/web/ui/elements #:~empty-state #:~pager #:~replace-url)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast #:action-refusal)
  (:import-from #:koya-server/usecases/schema #:load-schema)
  (:export #:@get #:browse-deliveries))
(in-package #:koya-server/web/pages/s/<space>/webhooks)

(defun filtered-p (label model) (not (and (blank-p label) (blank-p model))))

(defcomp ~outcome (&key delivery)
  (let* ((status (delivery-status delivery))
         (ok (delivery-ok delivery))
         (class (cond (ok "bg-ok/10 text-ok")
                      (status "bg-danger/10 text-danger")
                      (t "bg-warn/10 text-warn"))))
    (hsx (span :class (clsx "badge whitespace-nowrap" class)
           (cond (status (format nil "~a" status))
                 (t "no response"))))))

(defun union-options (current logged selected)
  (let ((options (append current
                         (sort (remove-if (lambda (value) (member value current :test #'string=)) logged)
                               #'string<))))
    (if (or (blank-p selected) (member selected options :test #'string=))
        options
        (append options (list selected)))))

(defun model-names (schema)
  (and schema (mapcar #'model-name (schema-models schema))))

(defun webhook-labels (schema)
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

(defcomp ~filters-clear (&key space label model)
  (hsx
   (span :id "filters-clear"
     (when (filtered-p label model)
       (hsx (a :href (webhook-log-url space)
               :nm-bind (on-follow (browse-deliveries :space space :clear "1"))
               :class "btn"
              "Clear"))))))

(defcomp ~filters (&key space schema label model)
  (let ((labels (union-options (webhook-labels schema) (delivery-labels space) label))
        (models (union-options (model-names schema) (delivery-models space) model)))
    (hsx
     (<> (unless (and (null labels) (null models))
           (hsx
            (form :id "filters" :method "get" :action (format nil "~a/webhooks" (space-url space))
                  :nm-data "...koya.search()" :nm-bind (on-search (browse-deliveries :space space) :typing nil)
                  :class "mb-6 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-md border border-line bg-panel px-4 py-3"
              (~filter-select :name "label" :label "Webhook" :all "All webhooks"
                              :options labels :selected label)
              (~filter-select :name "model" :label "Model" :all "All models"
                              :options models :selected model)
              (~filters-clear :space space :label label :model model))))))))

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
         (span :class "text-muted transition-transform group-open:rotate-90" (~icon :name :next))
         (~outcome :delivery delivery)
         (span :class "min-w-0"
           (span :class "font-medium" (delivery-label delivery))
           (code :class "block truncate text-xs text-muted sm:ml-2 sm:inline" (delivery-model delivery))))
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

(defcomp ~delivery-count (&key space label model)
  (let ((total (count-deliveries space :label label :model model)))
    (hsx (p :id "delivery-count" :class "mb-4 text-sm text-muted"
           (format nil "~a call~:p~a. The newest ~a of the space are kept." total
                   (cond ((not (filtered-p label model)) "")
                         ((= total 1) " matches")
                         (t " match"))
                   +deliveries-kept+)))))

(defcomp ~deliveries (&key space label model page)
  (let* ((total (count-deliveries space :label label :model model))
         (pages (last-page total))
         (page (min page pages))
         (items (list-deliveries space :label label :model model
                                       :limit +page-size+ :offset (page-offset page))))
    (hsx
     (div :id "deliveries"
       (if (null items)
           (hsx (~empty-state (if (filtered-p label model)
                                  "Nothing matches these filters."
                                  "Nothing has been delivered yet.")))
           (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                  (loop :for delivery :in items :collect
                    (hsx (li (~delivery :space space :delivery delivery)))))))
       (~pager :page page :pages pages
               :href (lambda (n) (webhook-log-url space :label label :model model :page n))
               :browse (lambda (n) (browse-deliveries :space space :label (or label "") :model (or model "") :page n)))))))

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
         (pages (and schema (last-page (count-deliveries space :label label :model model))))
         (page (and schema (min (page-number params) pages))))
    (cond ((null schema) (action-refusal "Space not found." 404))
          (t
           (hsx (<> (~deliveries :space space :label label :model model :page page)
                    (~replace-url :url (webhook-log-url space :label label :model model :page page))
                    (~delivery-count :space space :label label :model model)
                    (if clear
                        (hsx (~filters :space space :schema schema))
                        (hsx (~filters-clear :space space :label label :model model)))))))))

(defun @get (params)
  (let* ((name (path-param params :space))
         (schema (load-schema name)))
    (cond ((null schema) (hsx (~missing :what "Space")))
          (t
           (set-title (format nil "Webhooks · ~a · koya" name))
           (hsx (~log-page :space name
                           :schema schema
                           :label (param params "label")
                           :model (param params "model")
                           :page (page-number params)))))))
