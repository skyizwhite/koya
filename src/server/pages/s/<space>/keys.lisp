(defpackage #:koya-server/pages/s/<space>/keys
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store #:find-space #:space-webhook-secret #:rotate-webhook-secret)
  (:import-from #:koya-server/db/delivery-keys #:create-delivery-key #:list-delivery-keys #:delete-delivery-key)
  (:import-from #:koya-server/db/management-keys
                #:create-management-key #:list-management-keys #:delete-management-key)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:param #:short-time #:set-flash #:redirect-to
                #:~layout #:~empty-state #:~icon #:space-url)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/s/<space>/keys)

;;; Every key of one space: the delivery keys that read its published content and
;;; the management keys that drive the admin API for it. Both belong to the space
;;; and are kept apart because what they may do is not the same -- a delivery key
;;; is handed to a front end, a management key deploys schemas.

(defcomp ~new-key (&key key)
  (hsx (div :class "mb-4 rounded-md border border-ok/40 bg-ok/5 px-4 py-3 text-sm"
         (p :class "font-medium text-ok" "New key created. Copy it now; it will not be shown again.")
         (code :class "mt-2 block select-all break-all rounded bg-panel px-2 py-1 font-mono" key))))

(defcomp ~key-table (&key space keys delete-action)
  (if (null keys)
      (hsx (~empty-state "No keys yet."))
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
                              (input :type "hidden" :name "action" :value delete-action)
                              (input :type "hidden" :name "id" :value (getf key :id))
                              ;; the cell is narrow, so the icon stands for the label
                              (button :type "submit" :class "btn btn-danger btn-icon" :aria-label "Delete key"
                                (~icon :name :delete)))))))))))))

(defcomp ~create-key (&key space action placeholder)
  (hsx (form :method "post" :action (format nil "~a/keys" (space-url space)) :class "mt-4 flex items-end gap-3"
         (input :type "hidden" :name "action" :value action)
         (div :class "flex-1"
           (label :class "label" "Label")
           (input :type "text" :name "label" :class "input mt-1.5" :placeholder placeholder))
         (button :type "submit" :class "btn btn-primary" (~icon :name :plus) "Create key"))))

(defcomp ~keys-page (&key space new-delivery-key new-management-key)
  (hsx
   (~layout :space space :crumbs (list (cons "Keys" nil))
     (h1 :class "mb-8 text-2xl font-bold" "Keys")
     (section
       (h2 :class "mb-1 text-lg font-bold" "Delivery keys")
       (p :class "mb-4 text-sm text-muted"
         "Read-only access to this space's published content.")
       (when new-delivery-key (hsx (~new-key :key new-delivery-key)))
       (~key-table :space space :keys (list-delivery-keys space) :delete-action "delete")
       (~create-key :space space :action "create" :placeholder "e.g. production site"))
     (section :class "mt-12"
       (h2 :class "mb-1 text-lg font-bold" "Management keys")
       (p :class "mb-4 text-sm text-muted"
         "Read and write content, and deploy schema changes.")
       (when new-management-key (hsx (~new-key :key new-management-key)))
       (~key-table :space space :keys (list-management-keys space) :delete-action "delete-management")
       (~create-key :space space :action "create-management" :placeholder "e.g. deploys from CI"))
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
  (find-space (path-param params :space)))

(defun page-title (space) (format nil "Keys · ~a · koya" space))

(defun @get (params)
  (with-owner
    (let ((space (ensure-space params)))
      (cond ((null space) (set-response-status 404) (hsx (~layout (h1 "Space not found"))))
            (t (set-title (page-title space))
               (hsx (~keys-page :space space)))))))

(defun @post (params)
  (with-owner-post
    (let ((space (ensure-space params))
          (action (param params "action"))
          (label (or (param params "label") ""))
          (id (or (param params "id") "")))
      (cond ((null space) (set-response-status 404) (hsx (~layout (h1 "Space not found"))))
            ;; create renders directly because the plaintext key is shown only
            ;; once; delete and rotate redirect so a reload cannot repeat them
            ((equal action "create")
             (set-title (page-title space))
             (hsx (~keys-page :space space :new-delivery-key (create-delivery-key space :label label))))
            ((equal action "create-management")
             (set-title (page-title space))
             (hsx (~keys-page :space space :new-management-key (create-management-key space :label label))))
            ((equal action "delete")
             (delete-delivery-key space id)
             (set-flash "Key deleted.")
             (redirect-to (format nil "~a/keys" (space-url space))))
            ((equal action "delete-management")
             (delete-management-key space id)
             (set-flash "Key deleted.")
             (redirect-to (format nil "~a/keys" (space-url space))))
            ((equal action "rotate-webhook-secret")
             (rotate-webhook-secret space)
             (set-flash "Webhook secret rotated.")
             (redirect-to (format nil "~a/keys" (space-url space))))
            (t (set-response-status 400) (hsx (~layout :space space (p "Unknown action"))))))))
