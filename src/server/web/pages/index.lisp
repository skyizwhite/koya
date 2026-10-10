(defpackage #:koya-server/web/pages/index
  (:use #:cl #:hsx)
  (:import-from #:jingle
                #:set-response-status #:*request* #:request-content)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/lib/http #:param)
  (:import-from #:koya-server/web/lib/urls #:space-url)
  (:import-from #:koya-server/web/lib/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/elements #:~empty-state #:~go-to)
  (:import-from #:koya-server/web/lib/binds #:on-submit)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast
                #:set-toast #:~toast #:action-refusal #:action-refused)
  (:import-from #:koya-server/domain/errors #:koya-error #:koya-error-message)
  (:import-from #:koya-server/usecases/archive #:begin-import #:continue-import #:finish-import)
  (:import-from #:koya-server/usecases/spaces
                #:create-space #:remove-space #:list-spaces #:find-space)
  (:export #:@get #:create-space-action #:delete-space-action
           #:begin-import-action #:continue-import-action #:finish-import-action))
(in-package #:koya-server/web/pages/index)

(defun delete-phrase (name)
  (format nil "delete ~a" name))

(defun delete-dialog-id (name) (format nil "delete-space-~a" name))
(defun delete-phrase-id (name) (format nil "delete-phrase-~a" name))
(defun delete-error-id (name) (format nil "delete-error-~a" name))

(defcomp ~dialog-close (&key dialog children)
  (hsx (button :type "button" :commandfor dialog :command "close" :class "btn" children)))

(defcomp ~delete-error (&key name message)
  (hsx (p :id (delete-error-id name) :nm-ref "error" :class "mt-2 text-sm text-danger" message)))

(defcomp ~delete-space-dialog (&key name)
  (let ((id (delete-dialog-id name))
        (phrase (delete-phrase name))
        (input (delete-phrase-id name)))
    (hsx
     (dialog :id id :closedby "any" :class "koya-dialog max-w-sm" :nm-data "...koya.phrase(this)"
             :nm-bind "{ onclose: () => _reset() }"
       (form :nm-bind (on-submit (delete-space-action))
         (input :type "hidden" :name "name" :value name)
         (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
           (h2 :class "font-semibold" "Delete space")
           (button :type "button" :commandfor id :command "close" :class "btn btn-icon" :aria-label "Close"
             (~icon :name :close)))
         (div :class "px-4 py-4"
           (p :class "text-sm"
              "This deletes " (strong name) " with every model, content, media file and key in it. "
              "It cannot be undone.")
           (label :for input :class "label mt-4" "Type " (code (format nil "\"~a\"" phrase)) " to confirm")
           (input :type "text" :id input :name "confirm" :required t :autocomplete "off"
                  :spellcheck "false" :data-confirm-phrase phrase :class "input mt-1.5"
                  :nm-bind "{ value: () => _typed, oninput: () => _typed = this.value }")
           (~delete-error :name name))
         (div :class "flex justify-end gap-2 border-t border-line px-4 py-3"
           (~dialog-close :dialog id "Cancel")
           (button :type "submit" :class "btn btn-danger" :disabled t
                   :nm-bind "{ disabled: () => _typed !== _phrase }"
             (~icon :name :delete) "Delete space")))))))

(defcomp ~space-row (&key space)
  (let ((name (getf space :name)))
    (hsx
     (li :class "flex items-center justify-between gap-3 px-4 py-3"
       (a :href (space-url name) :class "min-w-0 flex-1 hover:underline"
         (span :class "block font-semibold" name)
         (span :class "block text-sm text-muted" (format nil "~a model~:p" (getf space :models))))
       (button :type "button" :class "btn btn-danger btn-icon shrink-0" :aria-label "Delete space"
               :commandfor (delete-dialog-id name) :command "show-modal"
         (~icon :name :delete))
       (~delete-space-dialog :name name)))))

(defcomp ~space-list (&key spaces)
  (hsx
   (div :id "spaces"
     (if (null spaces)
         (hsx (~empty-state
                (p "No spaces yet.")
                (p :class "mt-2" "Make one with " (strong "New space") ", then deploy its models with "
                   (code "(koya-sdk:deploy)") " from your project's REPL.")))
         (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                (loop :for space :in spaces :collect (hsx (~space-row :space space)))))))))

(defcomp ~new-space-error (&key message)
  (hsx (p :id "new-space-error" :class "mt-2 text-sm text-danger" message)))

(defcomp ~new-space-dialog ()
  (hsx
   (dialog :id "new-space" :closedby "any" :class "koya-dialog max-w-sm"
     (form :nm-bind (on-submit (create-space-action))
       (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
         (h2 :class "font-semibold" "New space")
         (button :type "button" :commandfor "new-space" :command "close" :class "btn btn-icon" :aria-label "Close"
           (~icon :name :close)))
       (div :class "px-4 py-4"
         (label :for "name" :class "label" "Name")
         (input :type "text" :id "name" :name "name" :required t :autofocus t :autocomplete "off"
                :pattern "[a-z][a-z0-9\\-]*" :placeholder "website" :class "input mt-1.5")
         (p :class "mt-2 text-xs text-muted"
            "Lowercase letters, digits and hyphens. It is in every URL and in the delivery API, "
            "so it cannot be changed later.")
         (~new-space-error))
       (div :class "flex justify-end gap-2 border-t border-line px-4 py-3"
         (~dialog-close :dialog "new-space" "Cancel")
         (button :type "submit" :class "btn btn-primary" (~icon :name :plus) "Create space"))))))

(defparameter +import-piece-bytes+ (* 16 1024 1024))

(defcomp ~import-space-dialog ()
  (hsx
   (dialog :id "import-space" :closedby "any" :class "koya-dialog max-w-sm"
     (form :nm-data "...koya.importer(this)" :nm-bind "{ 'onsubmit.prevent': () => _start() }"
           :data-import-begin (begin-import-action)
           :data-import-continue (continue-import-action)
           :data-import-finish (finish-import-action)
           :data-import-piece-bytes (princ-to-string +import-piece-bytes+)
       (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
         (h2 :class "font-semibold" "Import space")
         (button :type "button" :commandfor "import-space" :command "close" :class "btn btn-icon" :aria-label "Close"
           (~icon :name :close)))
       (div :class "px-4 py-4"
         (label :for "archive" :class "label" "Archive")
         (input :type "file" :id "archive" :name "file" :required t :accept ".zip,application/zip"
                :nm-ref "file" :class "input mt-1.5")
         (p :class "mt-2 text-xs text-muted"
            "A zip from a space's " (strong "Export") ". The space is made again under its own name, "
            "with its models, webhooks, contents, history, media and keys. A space of that name must not "
            "exist yet, or must be empty: no models, media or keys. Nothing is sent to the webhooks.")
         (div :class "mt-4" :hidden t :nm-bind "{ hidden: () => !_busy }"
           (progress :class "w-full" :max "100" :nm-ref "bar"
                     :nm-bind "{ max: () => _total || 1, value: () => _sent }")
           (p :class "mt-1 text-xs text-muted" :nm-bind "{ textContent: () => _status }")))
       (p :class "px-4 pb-3 text-sm text-danger" :hidden t
          :nm-bind "{ hidden: () => !_error, textContent: () => _error }")
       (p :class "px-4 pb-3 text-sm" :hidden t :nm-bind "{ hidden: () => !_login }"
         (a :target "_blank" :rel "noopener" :class "font-semibold text-danger underline"
            :nm-bind "{ href: () => _login }"
            "Log in in a new tab")
         ", then import again.")
       (div :class "flex justify-end gap-2 border-t border-line px-4 py-3"
         (~dialog-close :dialog "import-space" "Cancel")
         (button :type "submit" :class "btn btn-primary" :nm-bind "{ disabled: () => _busy }"
           (~icon :name :import)
           (span :nm-bind "{ textContent: () => _busy ? 'Importing…' : 'Import' }" "Import")))))))

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

(defun make-space (params)
  (handler-case (values (format nil "Space ~a created." (create-space (or (param params "name") ""))) nil)
    (koya-error (e) (values nil (koya-error-message e)))))

(defun import-archive (id)
  (handler-case
      (let ((space (finish-import id)))
        (set-toast (format nil "Space ~a imported." space))
        (space-url space))
    (error (e)
      (set-toast (format nil "Import failed: ~a" e) :error)
      "/")))

(defaction create-space-action :post (params)
  (multiple-value-bind (message error) (make-space params)
    (cond (error
           (set-response-status 422)
           (hsx (~new-space-error :message error)))
          (t
           (hsx (<> (~new-space-dialog)
                    (~space-list :spaces (list-spaces))
                    (~toast :message message)))))))

(defun delete-refusal (name message status)
  (cond ((null name) (action-refusal message status))
        (t (set-response-status status)
           (hsx (~delete-error :name name :message message)))))

(defaction delete-space-action :post (params)
  (let ((name (param params "name")))
    (cond ((null (and name (find-space name))) (delete-refusal name "Space not found." 404))
          ((string/= (or (param params "confirm") "") (delete-phrase name))
           (delete-refusal name (format nil "Type \"~a\" to delete this space." (delete-phrase name)) 422))
          (t (remove-space name)
             (hsx (<> (~space-list :spaces (list-spaces))
                      (~toast :message (format nil "Space ~a deleted." name))))))))

(defaction begin-import-action :post (params)
  (declare (ignore params))
  (hsx (<> (begin-import))))

(defaction continue-import-action :post (params)
  (let* ((raw (param params "offset"))
         (offset (and (stringp raw) (handler-case (parse-integer raw) (parse-error () nil)))))
    (handler-case
        (hsx (<> (princ-to-string (continue-import (param params "id") offset
                                                   (request-content *request*)))))
      (koya-error (e) (action-refused e)))))

(defaction finish-import-action :post (params)
  (hsx (~go-to :url (import-archive (param params "id")))))

(defun @get (params)
  (declare (ignore params))
  (set-title "Spaces · koya")
  (hsx (~spaces-page :spaces (list-spaces))))
