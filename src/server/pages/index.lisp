(defpackage #:koya-server/pages/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store
                #:list-spaces #:find-space #:create-space #:delete-space)
  (:import-from #:koya-server/lib/media-store #:remove-space-media)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:param #:set-flash #:redirect-to
                #:~layout #:~empty-state #:~icon #:space-url)
  (:export #:@get #:@head #:@post))
(in-package #:koya-server/pages/index)

;;; The spaces, and everything that makes or unmakes one. A space is a tenant --
;;; it owns the contents, media, keys and webhook secret -- so it is made here and
;;; never by a schema deploy, which only ever changes the models inside one.
;;;
;;; A space has nothing but its name, and the name is an id: it is in every URL
;;; and in the delivery API, so there is nothing here to edit.

(defcomp ~space-row (&key space)
  (let ((name (getf space :name)))
    (hsx
     (li :class "flex items-center justify-between gap-3 px-4 py-3"
       (a :href (space-url name) :class "min-w-0 flex-1 hover:underline"
         (span :class "block font-semibold" name)
         (span :class "block text-sm text-muted" (format nil "~a model~:p" (getf space :models))))
       (form :method "post" :class "shrink-0"
         (input :type "hidden" :name "action" :value "delete")
         (input :type "hidden" :name "name" :value name)
         (button :type "submit" :class "btn btn-danger btn-icon" :aria-label "Delete space"
                 :onclick (format nil "return confirm('Delete ~a with every model, content, media file and key in it? This cannot be undone.')" name)
           (~icon :name :delete)))))))

(defcomp ~spaces-page (&key spaces)
  (hsx
   (~layout
     (h1 :class "mb-6 text-2xl font-bold" "Spaces")
     (if (null spaces)
         (hsx (~empty-state
                (p "No spaces yet.")
                (p :class "mt-2" "Make one below, then deploy its models with "
                   (code "(koya:deploy)") " from your project's REPL.")))
         (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                (loop :for space :in spaces :collect (hsx (~space-row :space space))))))
     (form :method "post" :class "mt-8 flex items-end gap-3"
       (input :type "hidden" :name "action" :value "create")
       (div :class "flex-1"
         (label :for "name" :class "label" "Name")
         (input :type "text" :id "name" :name "name" :required t :autocomplete "off"
                :pattern "[a-z][a-z0-9-]*" :placeholder "website" :class "input mt-1.5 max-w-xs")
         (p :class "mt-1 text-xs text-muted" "In every URL and in the delivery API. Cannot be changed later."))
       (button :type "submit" :class "btn btn-primary" (~icon :name :plus) "Create space")))))

(defun @get (params)
  (declare (ignore params))
  (with-owner
    (set-title "Spaces · koya")
    (hsx (~spaces-page :spaces (list-spaces)))))

;; health check
(defun @head (params)
  (declare (ignore params)))

(defun @post (params)
  (with-owner-post
    (let ((action (param params "action"))
          (name (param params "name")))
      (cond ((equal action "create")
             ;; a bad or taken name signals; the message is what the owner needs
             (handler-case
                 (set-flash (format nil "Space ~a created." (create-space (or name ""))))
               (error (e) (set-flash (princ-to-string e) :error)))
             (redirect-to "/"))
            ((not (equal action "delete"))
             (set-response-status 400)
             (hsx (~layout (p "Unknown action"))))
            ((null (and name (find-space name)))
             (set-response-status 404)
             (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            (t
             ;; the rows go first: the cascade takes the media rows with the space,
             ;; and only then is there nothing left pointing at the files
             (delete-space name)
             (remove-space-media name)
             (set-flash (format nil "Space ~a deleted." name))
             (redirect-to "/"))))))
