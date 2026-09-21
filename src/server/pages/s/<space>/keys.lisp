(defpackage #:koya-server/pages/s/<space>/keys
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store #:find-space #:space-webhook-secret #:rotate-webhook-secret)
  (:import-from #:koya-server/db/api-keys #:create-api-key #:list-api-keys #:delete-api-key)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:param #:short-time #:set-flash #:redirect-to
                #:~layout #:~empty-state #:~icon #:space-url)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/s/<space>/keys)

(defcomp ~keys-page (&key space new-key)
  (hsx
   (~layout :space space :crumbs (list (cons "Delivery keys" nil))
     (h1 :class "mb-6 text-2xl font-bold" "Delivery keys")
     (p :class "mb-6 text-sm text-muted"
       "Sent as " (code "X-KOYA-API-KEY") " to read this space through the delivery API. Keys for the admin API are made under Settings.")
     (when new-key
       (hsx (div :class "mb-6 rounded-md border border-ok/40 bg-ok/5 px-4 py-3 text-sm"
              (p :class "font-medium text-ok" "New key created. Copy it now; it will not be shown again.")
              (code :class "mt-2 block select-all break-all rounded bg-panel px-2 py-1 font-mono" new-key))))
     (let ((keys (list-api-keys space)))
       (if (null keys)
           (hsx (~empty-state "No delivery keys yet."))
           ;; framed like the other lists
           (hsx (div :class "overflow-x-auto rounded-md border border-line bg-panel"
                  (table :class "w-full text-sm"
                    (thead (tr :class "border-b border-line text-left text-muted"
                             (th :class "py-2 pl-4 pr-4 font-medium" "label")
                             (th :class "py-2 pr-4 font-medium whitespace-nowrap" "created at")
                             (th)))
                    (tbody :class "divide-y divide-line"
                      (loop :for key :in keys :collect
                        (hsx (tr
                               (td :class "py-2 pl-4 pr-4 font-medium"
                                 (if (string= (getf key :label) "")
                                     (hsx (span :class "text-muted" "(no label)"))
                                     (getf key :label)))
                               (td :class "py-2 pr-4 whitespace-nowrap text-muted" (short-time (getf key :created-at)))
                               (td :class "py-2 pl-4 pr-4 text-right"
                                 (form :method "post" :action (format nil "~a/keys" (space-url space))
                                   (input :type "hidden" :name "action" :value "delete")
                                   (input :type "hidden" :name "id" :value (getf key :id))
                                   ;; the cell is narrow, so the icon stands for the label
                                   (button :type "submit" :class "btn btn-danger btn-icon" :aria-label "Delete key"
                                     (~icon :name :delete)))))))))))))
     (form :method "post" :action (format nil "~a/keys" (space-url space)) :class "mt-8 flex items-end gap-3"
       (input :type "hidden" :name "action" :value "create")
       (div :class "flex-1"
         (label :for "label" :class "label" "Label")
         (input :type "text" :id "label" :name "label" :class "input mt-1.5" :placeholder "e.g. production site"))
       (button :type "submit" :class "btn btn-primary" (~icon :name :plus) "Create key"))
     (section :class "mt-12"
       (h2 :class "mb-2 text-lg font-bold" "Webhook secret")
       (p :class "mb-3 text-sm text-muted"
         "Sent as " (code "X-KOYA-WEBHOOK-KEY") " with every webhook of this space. Verify it on the receiving end.")
       (div :class "flex items-center gap-3"
         (code :class "select-all break-all rounded border border-line bg-panel px-2 py-1 font-mono text-sm"
           (space-webhook-secret space))
         (form :method "post" :action (format nil "~a/keys" (space-url space))
           (input :type "hidden" :name "action" :value "rotate-webhook-secret")
           (button :type "submit" :class "btn" :onclick "return confirm('Rotate the webhook secret?')"
             (~icon :name :rotate) "Rotate")))))))

(defun ensure-space (params)
  (let ((name (path-param params :space)))
    (and (find-space name) name)))

(defun @get (params)
  (with-owner
    (let ((space (ensure-space params)))
      (cond ((null space) (set-response-status 404) (hsx (~layout (h1 "Space not found"))))
            (t (set-title (format nil "Delivery keys · ~a · koya" space))
               (hsx (~keys-page :space space)))))))

(defun @post (params)
  (with-owner-post
    (let ((space (ensure-space params))
          (action (param params "action")))
      (cond ((null space) (set-response-status 404) (hsx (~layout (h1 "Space not found"))))
            ((equal action "create")
             (set-title (format nil "Delivery keys · ~a · koya" space))
             (hsx (~keys-page :space space :new-key (create-api-key space :label (or (param params "label") "")))))
            ;; delete and rotate redirect so a reload cannot repeat them; create
            ;; renders directly because the plaintext key is shown only once
            ((equal action "delete")
             (delete-api-key space (or (param params "id") ""))
             (set-flash "Key deleted.")
             (redirect-to (format nil "~a/keys" (space-url space))))
            ((equal action "rotate-webhook-secret")
             (rotate-webhook-secret space)
             (set-flash "Webhook secret rotated.")
             (redirect-to (format nil "~a/keys" (space-url space))))
            (t (set-response-status 400) (hsx (~layout :space space (p "Unknown action"))))))))
