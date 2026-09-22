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

;;; The spaces. A space owns the contents, media, keys and webhook secret, so it
;;; is made and deleted here, never by a deploy, which only changes its models.
;;; Its name is its id -- it is in every URL -- so there is nothing to edit.

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
         ;; the name goes in an attribute, not an inline handler (koya-editor.js)
         (button :type "submit" :class "btn btn-danger btn-icon" :aria-label "Delete space"
                 :data-confirm (format nil "Delete ~a with every model, content, media file and key in it? This cannot be undone." name)
           (~icon :name :delete)))))))

(defcomp ~new-space-dialog ()
  "The whole of making a space is one name, so it lives in a dialog rather than
taking up the page. Opened by the [data-dialog-open] button (koya-editor.js)."
  (hsx
   (dialog :id "new-space" :class "koya-dialog max-w-sm"
     (form :method "post"
       (input :type "hidden" :name "action" :value "create")
       (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
         (h2 :class "font-semibold" "New space")
         (button :type "button" :class "btn btn-icon" :data-dialog-close t :aria-label "Close"
           (~icon :name :close)))
       (div :class "px-4 py-4"
         (label :for "name" :class "label" "Name")
         (input :type "text" :id "name" :name "name" :required t :autofocus t :autocomplete "off"
                :pattern "[a-z][a-z0-9-]*" :placeholder "website" :class "input mt-1.5")
         (p :class "mt-2 text-xs text-muted"
            "Lowercase letters, digits and hyphens. It is in every URL and in the delivery API, "
            "so it cannot be changed later."))
       (div :class "flex justify-end gap-2 border-t border-line px-4 py-3"
         (button :type "button" :class "btn" :data-dialog-close t "Cancel")
         (button :type "submit" :class "btn btn-primary" (~icon :name :plus) "Create space"))))))

(defcomp ~spaces-page (&key spaces)
  (hsx
   (~layout
     (div :class "mb-6 flex items-center justify-between gap-4"
       (h1 :class "text-2xl font-bold" "Spaces")
       (button :type "button" :class "btn btn-primary" :data-dialog-open "new-space"
         (~icon :name :plus) "New space"))
     (if (null spaces)
         (hsx (~empty-state
                (p "No spaces yet.")
                (p :class "mt-2" "Make one with " (strong "New space") ", then deploy its models with "
                   (code "(koya:deploy)") " from your project's REPL.")))
         (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                (loop :for space :in spaces :collect (hsx (~space-row :space space))))))
     (~new-space-dialog))))

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
