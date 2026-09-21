(defpackage #:koya-server/pages/s/<space>/webhooks
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/webhook-deliveries
                #:list-deliveries #:count-deliveries #:+keep-per-space+
                #:delivery-id #:delivery-label #:delivery-url #:delivery-model #:delivery-event
                #:delivery-content-id #:delivery-ok #:delivery-status #:delivery-response
                #:delivery-error #:delivery-duration-ms #:delivery-created-at)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:set-title #:param #:short-time
                #:~layout #:~empty-state #:~icon #:space-url #:content-url)
  (:export #:@get #:webhook-log-url))
(in-package #:koya-server/pages/s/<space>/webhooks)

;;; The last +KEEP-PER-SPACE+ webhook calls of a space: whether the receiver
;;; accepted each one, and what it answered.

(defparameter +page-size+ 25)

(defun webhook-log-url (space &optional label)
  (format nil "~a/webhooks~@[?label=~a~]" (space-url space)
          (and label (plusp (length label)) (quri:url-encode label))))

(defun page-link (space label page)
  (format nil "~a/webhooks?page=~a~@[&label=~a~]" (space-url space) page
          (and label (plusp (length label)) (quri:url-encode label))))

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

(defcomp ~field (&key label children)
  (hsx
   (div :class "flex gap-2"
     (span :class "w-24 shrink-0 text-muted" label)
     (div :class "min-w-0 flex-1 break-all" children))))

(defcomp ~body-block (&key text)
  (if (and text (plusp (length text)))
      (hsx (pre :class "mt-1 max-h-64 overflow-auto whitespace-pre-wrap break-all rounded border border-line bg-base px-2 py-1 font-mono text-xs"
             text))
      (hsx (span :class "text-muted" "(empty)"))))

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
       (if (plusp (length (delivery-error delivery)))
           (hsx (~field :label "error"
                  (span :class "text-danger" (delivery-error delivery))))
           (hsx (<>)))
       (~field :label "response" (~body-block :text (delivery-response delivery)))))))

(defcomp ~log-page (&key space label page)
  (let* ((total (count-deliveries space :label label))
         (pages (max 1 (ceiling total +page-size+)))
         (page (min page pages))
         (items (list-deliveries space :label label :limit +page-size+ :offset (* (1- page) +page-size+))))
    (hsx
     (~layout :space space :crumbs (list (cons "Webhooks" nil))
       (div :class "mb-6 flex items-center justify-between gap-3"
         (h1 :class "text-2xl font-bold" "Webhooks")
         (if label
             (hsx (a :href (format nil "~a/webhooks" (space-url space)) :class "btn"
                     (~icon :name :close) "All webhooks"))
             (hsx (<>))))
       (p :class "mb-6 text-sm text-muted"
         (if label
             (hsx (<> "The last calls to " (code label) "."))
             (hsx (<> "The last calls this space made.")))
         (format nil " Only the newest ~a are kept." +keep-per-space+))
       (if (null items)
           (hsx (~empty-state "Nothing has been delivered yet."))
           (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                  (loop :for delivery :in items :collect
                    (hsx (li (~delivery :space space :delivery delivery)))))))
       (if (> pages 1)
           (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                  (if (> page 1)
                      (hsx (a :href (page-link space label (1- page)) :class "btn" (~icon :name :prev) "Previous"))
                      (hsx (<>)))
                  (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                  (if (< page pages)
                      (hsx (a :href (page-link space label (1+ page)) :class "btn" "Next" (~icon :name :next)))
                      (hsx (<>)))))
           (hsx (<>)))))))

(defun @get (params)
  (with-owner
    (let* ((name (path-param params :space))
           (space (and (find-space name) name)))
      (cond ((null space)
             (set-response-status 404)
             (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            (t
             (set-title (format nil "Webhooks · ~a · koya" space))
             (hsx (~log-page :space space :label (param params "label") :page (page-number params))))))))
