(defpackage #:koya-server/web/pages/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/http #:param)
  (:import-from #:koya-server/web/urls #:space-url)
  (:import-from #:koya-server/web/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/elements #:~empty-state)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast #:set-toast #:~toast-oob #:action-refusal)
  (:import-from #:lack/request #:request-env)
  (:import-from #:koya-server/usecases/spaces/archive #:import-space-stream)
  (:import-from #:koya-server/usecases/spaces/lifecycle
                #:create-space #:remove-space #:list-spaces #:find-space)
  (:import-from #:koya-server/web/middlewares #:archive-path)
  (:export #:@get #:create-space-action #:delete-space-action #:import-space-action))
(in-package #:koya-server/web/pages/index)

;;; The spaces. A space owns the contents, media, keys and webhook secret, so it
;;; is made and deleted here, never by a deploy, which only changes its models.
;;; Its name is its id -- it is in every URL -- so there is nothing to edit.
;;;
;;; Making and deleting one are actions answered in place. The dialogs open and
;;; close by HTML alone (commandfor, closedby), so one swapped in works like the
;;; one it replaced.

(defcomp ~space-row (&key space)
  (let ((name (getf space :name)))
    (hsx
     (li :class "flex items-center justify-between gap-3 px-4 py-3"
       (a :href (space-url name) :class "min-w-0 flex-1 hover:underline"
         (span :class "block font-semibold" name)
         (span :class "block text-sm text-muted" (format nil "~a model~:p" (getf space :models))))
       (form :class "shrink-0"
             :hx-post (delete-space-action) :hx-target "#spaces" :hx-swap "outerHTML"
             :hx-confirm (format nil "Delete ~a with every model, content, media file and key in it? This cannot be undone." name)
         (input :type "hidden" :name "name" :value name)
         (button :type "submit" :class "btn btn-danger btn-icon" :aria-label "Delete space"
           (~icon :name :delete)))))))

(defcomp ~space-list (&key spaces oob)
  (hsx
   (div :id "spaces" :hx-swap-oob (and oob "true")
     (if (null spaces)
         (hsx (~empty-state
                (p "No spaces yet.")
                (p :class "mt-2" "Make one with " (strong "New space") ", then deploy its models with "
                   (code "(koya:deploy)") " from your project's REPL.")))
         (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                (loop :for space :in spaces :collect (hsx (~space-row :space space)))))))))

(defcomp ~dialog-close (&key dialog children)
  (hsx (button :type "button" :commandfor dialog :command "close" :class "btn" children)))

(defcomp ~new-space-dialog ()
  "The whole of making a space is one name, so it lives in a dialog rather than
taking up the page."
  (hsx
   (dialog :id "new-space" :closedby "any" :class "koya-dialog max-w-sm"
     (form :hx-post (create-space-action) :hx-target "#new-space" :hx-swap "outerHTML"
       (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
         (h2 :class "font-semibold" "New space")
         (button :type "button" :commandfor "new-space" :command "close" :class "btn btn-icon" :aria-label "Close"
           (~icon :name :close)))
       (div :class "px-4 py-4"
         (label :for "name" :class "label" "Name")
         ;; the hyphen is escaped: browsers read a pattern with the v flag, where a bare one is an error
         (input :type "text" :id "name" :name "name" :required t :autofocus t :autocomplete "off"
                :pattern "[a-z][a-z0-9\\-]*" :placeholder "website" :class "input mt-1.5")
         (p :class "mt-2 text-xs text-muted"
            "Lowercase letters, digits and hyphens. It is in every URL and in the delivery API, "
            "so it cannot be changed later.")
         (p :id "new-space-error" :class "mt-2 text-sm text-danger"))
       (div :class "flex justify-end gap-2 border-t border-line px-4 py-3"
         (~dialog-close :dialog "new-space" "Cancel")
         (button :type "submit" :class "btn btn-primary" (~icon :name :plus) "Create space"))))))

(defcomp ~import-space-dialog ()
  "A space archive from a space's Export. koya-editor.js sends the chosen file to
the import action as the request body (see IMPORT-SPACE-ACTION)."
  (hsx
   (dialog :id "import-space" :closedby "any" :class "koya-dialog max-w-sm"
     (form :data-import (import-space-action)
       (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
         (h2 :class "font-semibold" "Import space")
         (button :type "button" :commandfor "import-space" :command "close" :class "btn btn-icon" :aria-label "Close"
           (~icon :name :close)))
       (div :class "px-4 py-4"
         (label :for "archive" :class "label" "Archive")
         (input :type "file" :id "archive" :name "file" :required t :accept ".zip,application/zip"
                :class "input mt-1.5")
         (p :class "mt-2 text-xs text-muted"
            "A zip from a space's " (strong "Export") ". The space is made again under its own name, "
            "with its models, webhooks, contents, history, media and keys. A space of that name must not "
            "exist yet, or must be empty: no models, media or keys. Nothing is sent to the webhooks."))
       (p :class "hidden px-4 pb-3 text-sm text-danger" :data-import-error t)
       (div :class "flex justify-end gap-2 border-t border-line px-4 py-3"
         (~dialog-close :dialog "import-space" "Cancel")
         (button :type "submit" :class "btn btn-primary" (~icon :name :import) "Import"))))))

(defcomp ~spaces-page (&key spaces)
  (hsx
   (~layout
     (div :class "mb-6 flex flex-wrap items-center justify-between gap-3"
       (h1 :class "text-2xl font-bold" "Spaces")
       (div :class "flex flex-wrap gap-2"
         (button :type "button" :class "btn" :commandfor "import-space" :command "show-modal"
           (~icon :name :import) "Import")
         (button :type "button" :class "btn btn-primary" :commandfor "new-space" :command "show-modal"
           (~icon :name :plus) "New space")))
     (~space-list :spaces spaces)
     (~new-space-dialog)
     (~import-space-dialog))))

;;; --- The work ------------------------------------------------------------------

(defun make-space (params)
  "(values MESSAGE ERROR). A bad or taken name signals; its message is what the owner needs."
  (handler-case (values (format nil "Space ~a created." (create-space (or (param params "name") ""))) nil)
    (error (e) (values nil (princ-to-string e)))))

(defun import-archive (body)
  "The location to go to after importing the archive in the stream BODY."
  ;; every condition: a bad archive can fail in the zip reader, the schema
  ;; check or the database, and each one's message is what the owner needs
  (handler-case
      (let ((space (import-space-stream body)))
        (set-toast (format nil "Space ~a imported." space))
        (space-url space))
    (error (e)
      (set-toast (format nil "Import failed: ~a" e) :error)
      "/")))

;;; --- Actions ------------------------------------------------------------------

(defaction create-space-action :post (params)
  (multiple-value-bind (message error) (make-space params)
    (cond (error
           ;; the dialog stays open with the reason under the name
           (set-response-status 422)
           (set-response-header :hx-retarget "#new-space-error")
           (set-response-header :hx-reswap "innerHTML")
           (hsx (<> error)))
          (t
           ;; a fresh dialog in place of the open one closes it and clears the name
           (hsx (<> (~new-space-dialog)
                    (~space-list :spaces (list-spaces) :oob t)
                    (~toast-oob :message message)))))))

(defaction delete-space-action :post (params)
  (let ((name (param params "name")))
    (cond ((null (and name (find-space name))) (action-refusal "Space not found." 404))
          (t (remove-space name)
             (hsx (<> (~space-list :spaces (list-spaces))
                      (~toast-oob :message (format nil "Space ~a deleted." name))))))))

;;; A space archive from Export, made into a space again (usecases/spaces/archive).
;;;
;;; The dialog sends the file itself as an application/zip body (koya-editor.js),
;;; not as a multipart form, which lack would hold in memory several times over.
;;; ARCHIVE-PATH has *BODY-LIMIT-MIDDLEWARE* set that body aside unread; it is
;;; copied to a file here, once the owner is known, and read from there.
;;;
;;; The answer is where to go next, in HX-Redirect; the toast waits there.

(defaction import-space-action :post (params)
  (declare (ignore params))
  (let ((body (getf (request-env ningle:*request*) :koya.import-body)))
    (set-response-header :hx-redirect
                         (if body
                             (import-archive body)
                             (progn (set-toast "Choose an archive to import." :error) "/")))
    (hsx (<>))))

(archive-path (import-space-action))

;;; --- Page ---------------------------------------------------------------------

(defun @get (params)
  (declare (ignore params))
  (set-title "Spaces · koya")
  (hsx (~spaces-page :spaces (list-spaces))))
