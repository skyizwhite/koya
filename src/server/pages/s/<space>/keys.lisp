(defpackage #:koya-server/pages/s/<space>/keys
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store
                #:find-space #:space-webhook-secret #:rotate-webhook-secret)
  (:import-from #:koya-server/db/delivery-keys
                #:create-delivery-key #:list-delivery-keys #:delete-delivery-key)
  (:import-from #:koya-server/db/management-keys
                #:create-management-key #:list-management-keys #:delete-management-key)
  (:import-from #:koya-server/lib/http #:path-param #:param)
  (:import-from #:koya-server/lib/auth #:with-owner)
  (:import-from #:koya-server/lib/display #:short-time)
  (:import-from #:koya-server/document #:set-title)
  (:import-from #:koya-server/ui/layout #:~layout)
  (:import-from #:koya-server/ui/elements #:~empty-state)
  (:import-from #:koya-server/ui/icon #:~icon)
  (:import-from #:koya-server/ui/toast #:~toast-oob #:action-refusal)
  (:import-from #:ningle-actions #:defaction)
  (:export #:@get #:create-key #:delete-key #:rotate-secret))
(in-package #:koya-server/pages/s/<space>/keys)

;;; Every key of one space: the delivery keys that read its published content and
;;; the management keys that drive the admin API for it. Both belong to the space
;;; and are kept apart because what they may do is not the same -- a delivery key
;;; is handed to a front end, a management key deploys schemas.

;;; Creating, deleting and rotating are actions answered in place: the section
;;; they belong to is drawn again.

(defun key-kind (kind)
  "What differs between the two kinds of key, or NIL for anything else."
  (cond ((equal kind "delivery")
         (list :title "Delivery keys" :lead "Read-only access to this space's published content."
               :placeholder "e.g. production site"
               :list #'list-delivery-keys :create #'create-delivery-key :delete #'delete-delivery-key))
        ((equal kind "management")
         (list :title "Management keys" :lead "Read and write content, and deploy schema changes."
               :placeholder "e.g. deploys from CI"
               :list #'list-management-keys :create #'create-management-key :delete #'delete-management-key))))

(defun section-id (kind) (format nil "~a-keys" kind))

(defcomp ~new-key (&key key)
  (hsx (div :class "mb-4 rounded-md border border-ok/40 bg-ok/5 px-4 py-3 text-sm"
         (p :class "font-medium text-ok" "New key created. Copy it now; it will not be shown again.")
         (code :class "mt-2 block select-all break-all rounded bg-panel px-2 py-1 font-mono" key))))

(defcomp ~key-table (&key space kind keys)
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
                            (form :hx-post (delete-key :space space :kind kind)
                                  :hx-target (format nil "#~a" (section-id kind)) :hx-swap "outerHTML"
                                  :hx-confirm "Delete this key? Whatever uses it stops working."
                              (input :type "hidden" :name "id" :value (getf key :id))
                              ;; the cell is narrow, so the icon stands for the label
                              (button :type "submit" :class "btn btn-danger btn-icon" :aria-label "Delete key"
                                (~icon :name :delete)))))))))))))

(defcomp ~key-section (&key space kind new-key)
  (let ((k (key-kind kind)))
    (hsx
     (section :id (section-id kind)
       (h2 :class "mb-1 text-lg font-bold" (getf k :title))
       (p :class "mb-4 text-sm text-muted" (getf k :lead))
       (when new-key (hsx (~new-key :key new-key)))
       (~key-table :space space :kind kind :keys (funcall (getf k :list) space))
       (form :hx-post (create-key :space space :kind kind)
             :hx-target (format nil "#~a" (section-id kind)) :hx-swap "outerHTML"
             :class "mt-4 flex items-end gap-3"
         (div :class "flex-1"
           (label :class "label" "Label")
           (input :type "text" :name "label" :class "input mt-1.5" :placeholder (getf k :placeholder)))
         (button :type "submit" :class "btn btn-primary" (~icon :name :plus) "Create key"))))))

(defcomp ~webhook-secret (&key space)
  (hsx
   (section :id "webhook-secret" :class "mt-12"
     (h2 :class "mb-2 text-lg font-bold" "Webhook secret")
     (p :class "mb-3 text-sm text-muted"
       "Sent as " (code "X-KOYA-WEBHOOK-KEY") " with every webhook of this space. Verify it on the receiving end.")
     (div :class "flex items-center gap-3"
       (code :class "select-all break-all rounded border border-line bg-panel px-2 py-1 font-mono text-sm"
         (space-webhook-secret space))
       (form :hx-post (rotate-secret :space space)
             :hx-target "#webhook-secret" :hx-swap "outerHTML"
             :hx-confirm "Rotate the webhook secret? Receivers checking the old one start refusing."
         (button :type "submit" :class "btn" (~icon :name :rotate) "Rotate"))))))

(defcomp ~keys-page (&key space)
  (hsx
   (~layout :space space :crumbs (list (cons "Keys" nil))
     (h1 :class "mb-8 text-2xl font-bold" "Keys")
     (~key-section :space space :kind "delivery")
     (div :class "mt-12"
       (~key-section :space space :kind "management"))
     (~webhook-secret :space space))))

;;; --- Actions ------------------------------------------------------------------

(defun action-target (params)
  "The space and the kind of key an action names, when both exist."
  (let ((space (param params "space"))
        (kind (param params "kind")))
    (values (and space (find-space space) space)
            (and (key-kind kind) kind))))

(defaction create-key :post (params)
  (multiple-value-bind (space kind) (action-target params)
    (if (and space kind)
        (hsx (~key-section :space space :kind kind
                           :new-key (funcall (getf (key-kind kind) :create) space :label (or (param params "label") ""))))
        (action-refusal "Unknown space or kind of key." 404))))

(defaction delete-key :post (params)
  (multiple-value-bind (space kind) (action-target params)
    (if (and space kind)
        (progn (funcall (getf (key-kind kind) :delete) space (or (param params "id") ""))
               (hsx (<> (~key-section :space space :kind kind)
                        (~toast-oob :message "Key deleted."))))
        (action-refusal "Unknown space or kind of key." 404))))

(defaction rotate-secret :post (params)
  (let ((space (action-target params)))
    (if space
        (progn (rotate-webhook-secret space)
               (hsx (<> (~webhook-secret :space space)
                        (~toast-oob :message "Webhook secret rotated."))))
        (action-refusal "Unknown space." 404))))

;;; --- Page ---------------------------------------------------------------------

(defun ensure-space (params)
  (find-space (path-param params :space)))

(defun page-title (space) (format nil "Keys · ~a · koya" space))

(defun @get (params)
  (with-owner
    (let ((space (ensure-space params)))
      (cond ((null space) (set-response-status 404) (hsx (~layout (h1 "Space not found"))))
            (t (set-title (page-title space))
               (hsx (~keys-page :space space)))))))
