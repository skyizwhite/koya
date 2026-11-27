(defpackage #:koya-server/web/ui/content/editor
  (:use #:cl #:hsx)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/lib/binds #:submit #:post)
  (:import-from #:koya-core/schema
                #:model-kind #:model-fields #:field-name #:field-type #:webhook-covers-p
                #:model-name #:model-preview-url #:model-public-url #:model-history-p #:field-fields #:field-option
                #:field-row-kind #:row-kind #:custom-field-name #:custom-field-fields #:model-field
                #:field-many-p #:field-value)
  (:import-from #:koya-core/data #:array-p)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:koya-core/ulid #:make-ulid)
  (:import-from #:koya-core/validate #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/usecases/contents
                #:create #:update-draft #:publish #:unpublish #:discard #:destroy
                #:update-object #:publish-object #:content-references #:find-content)
  (:import-from #:koya-server/web/lib/target #:target-model #:target-content)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-space #:content-status #:content-published #:content-draft
                #:content-published-p #:content-draft-p
                #:content-created-at #:content-updated-at #:content-draft-key #:content-data
                #:default-data #:duplicated-data #:content-label #:slug-value #:held-ids)
  (:import-from #:koya-server/web/lib/http #:param #:integer-text #:form-list #:set-response-status #:send-to #:replace-url)
  (:import-from #:koya-server/domain/errors
                #:koya-error #:koya-error-code)
  (:import-from #:koya-server/web/lib/forms #:form->data #:field-param-name #:row-prefix)
  (:import-from #:koya-server/usecases/listing #:find-object-content)
  (:import-from #:koya-server/usecases/held #:read-held)
  (:import-from #:koya-server/usecases/schema #:find-model)
  (:import-from #:koya-server/web/lib/display #:short-time)
  (:import-from #:koya-server/web/lib/urls
                #:expand-url-template #:content-url #:model-url #:history-url #:webhook-log-url #:editor-url)
  (:import-from #:koya-server/web/lib/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/elements #:~status-badge #:~errors #:~confirm-dialog #:~referrers)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast
                #:set-toast #:~toast #:action-refusal #:action-refused)
  (:import-from #:koya-server/web/ui/content/field-input #:~field-input #:~field-error #:~custom-input #:~repeater-input)
  (:import-from #:koya-server/usecases/revisions #:restore-data #:find-revision)
  (:import-from #:koya-server/web/ui/media/picker #:~media-picker-dialog)
  (:import-from #:koya-server/web/ui/content/reference-picker #:~reference-picker-dialog)
  (:import-from #:koya-server/domain/revision #:revision-data #:revision-created-at)
  (:import-from #:koya-server/usecases/webhooks #:space-webhooks)
  (:export #:new-p #:show-editor #:editor-action #:repeater-row))
(in-package #:koya-server/web/ui/content/editor)

(defun new-p (id) (string= id "new"))

(defstruct (choices (:constructor make-choices (space &optional (media (make-hash-table :test 'equal))
                                                                 (contents (make-hash-table :test 'equal)))))
  space media contents)

(defun references-for (choices field value)
  (when (eq (field-type field) :reference)
    (let ((ids (held-ids value (field-many-p field))))
      (when ids
        (let* ((target (field-option field :model))
               (model (find-model (choices-space choices) target))
               (found (gethash target (choices-contents choices))))
          (loop :for id :in ids
                :for content := (and model found (gethash id found))
                :collect (if content
                             (list :id id :label (content-label content model) :status (content-status content)
                                   :href (editor-url (choices-space choices) model id))
                             (list :id id :label (format nil "~a (missing)" id)))))))))

(defun media-for (choices field value)
  (when (eq (field-type field) :media)
    (let ((media (choices-media choices))
          (ids (held-ids value (field-many-p field))))
      (if (field-many-p field)
          (mapcar (lambda (id) (cons id (gethash id media))) ids)
          (and ids (gethash (first ids) media))))))

(defun field-error (errors name)
  (let ((e (find name errors :key (lambda (e) (getf e :field)) :test #'string=)))
    (and e (getf e :message))))

(defun inner-path (field inner)
  (format nil "~a.~a" (field-name field) (field-name inner)))

(defun row-path (field index inner)
  (format nil "~a[~a].~a" (field-name field) index (field-name inner)))

(defun new-row-key ()
  (string-downcase (make-ulid)))

(defcomp ~repeater-row (&key choices field kind key row errors index fresh)
  (let ((prefix (row-prefix field key))
        (name (field-param-name field)))
    (hsx
     (div :class "rounded-md border border-line bg-panel" :data-row key
          :n-on-init (and fresh "koya.rowAdded($el)")
       (div :class "flex items-center justify-between gap-2 border-b border-line px-3 py-1"
         (div :class "flex items-center gap-2 text-sm"
           (span :class "cursor-move select-none text-muted" :aria-hidden "true" :data-drag-handle t "⠿")
           (span :class "font-medium" (custom-field-name kind)))
         (div :class "flex items-center gap-1"
           (button :type "button" :class "btn btn-icon py-1" :aria-label "Move row up"
                   :n-on-click "koya.moveRow($el, -1)" (~icon :name :up))
           (button :type "button" :class "btn btn-icon py-1" :aria-label "Move row down"
                   :n-on-click "koya.moveRow($el, 1)" (~icon :name :down))
           (button :type "button" :class "btn btn-icon py-1" :aria-label "Remove row"
                   :n-on-click "koya.removeRow($el)" (~icon :name :close))))
       (input :type "hidden" :name name :value key)
       (input :type "hidden" :name (format nil "~a.~a.fieldId" name key) :value (custom-field-name kind))
       (div :class "space-y-4 p-4"
         (loop :for inner :in (custom-field-fields kind) :collect
           (let ((inner-value (if (consp row)
                                  (field-value row inner)
                                  (and (eq (field-type inner) :boolean) (field-option inner :default) t))))
             (hsx (~field-input :field inner :parent prefix :value inner-value
                                :references (references-for choices inner inner-value)
                                :media (media-for choices inner inner-value)
                                :error (and index (field-error errors (row-path field index inner))))))))))))

(defcomp ~editor-field (&key space model field data errors choices)
  (multiple-value-bind (value found) (field-value data field)
    (case (field-type field)
      (:repeater
       (hsx (~repeater-input :field field :error (field-error errors (field-name field))
                             :add-url (repeater-row :space space :model model :field (field-name field))
              (when (array-p value)
                (loop :for row :across value
                      :for index :from 0
                      :for kind := (row-kind field row)
                      :when kind
                        :collect (hsx (~repeater-row :choices choices :field field :kind kind :key (princ-to-string index)
                                                     :row row :errors errors :index index)))))))
      (:custom
        (hsx (~custom-input :field field :present (and found (listp value)) :error (field-error errors (field-name field))
               (loop :for inner :in (field-fields field) :collect
                 (let ((inner-value (if (and found (listp value))
                                        (field-value value inner)
                                        (and (eq (field-type inner) :boolean) (field-option inner :default) t))))
                   (hsx (~field-input :field inner :parent field :value inner-value
                                      :references (references-for choices inner inner-value)
                                      :media (media-for choices inner inner-value)
                                      :error (field-error errors (inner-path field inner)))))))))
      (t
        (hsx (~field-input :field field :value value
                           :references (references-for choices field value)
                           :media (media-for choices field value)
                           :error (field-error errors (field-name field))))))))

(defcomp ~editor-field-errors (&key field errors params)
  (hsx
   (<> (~field-error :field field :error (field-error errors (field-name field)))
       (case (field-type field)
         (:custom
          (loop :for inner :in (field-fields field) :collect
            (hsx (~field-error :field inner :parent field :error (field-error errors (inner-path field inner))))))
         (:repeater
          (let ((name (field-param-name field)))
            (loop :for key :in (form-list params name)
                  :for index :from 0
                  :for kind := (field-row-kind field (param params (format nil "~a.~a.fieldId" name key)))
                  :when kind
                    :append (loop :for inner :in (custom-field-fields kind) :collect
                              (hsx (~field-error :field inner :parent (row-prefix field key)
                                                 :error (field-error errors (row-path field index inner))))))))))))

(defaction repeater-row :get (params)
  (let* ((space (param params "space"))
         (model (target-model params))
         (field (and model (model-field model (or (param params "field") ""))))
         (kind (and field (eq (field-type field) :repeater)
                    (field-row-kind field (param params "kind")))))
    (if kind
        (hsx (div :id (format nil "~a-rows" (field-param-name field)) :n-swap "append"
               (~repeater-row :choices (make-choices space) :field field :kind kind :key (new-row-key) :fresh t)))
        (action-refusal "No such row." 404))))

(defcomp ~external-link (&key href children)
  (hsx (a :href href :target "_blank" :rel "noopener" :class "btn" (~icon :name :external) children)))

(defcomp ~action-button (&key space model id op (class "btn") title confirm icon children)
  (let ((dialog (and confirm (format nil "confirm-~a" op))))
    (flet ((act ()
             (hsx (button :type "button" :class class
                          :commandfor dialog :command (and dialog "close")
                          :n-on-click (post (editor-action :space space :model model :id id :op op)
                                            :data "$refs.form")
                          :n-bind-disabled (and (equal op "save") "unchanged()")
                    (when icon (hsx (~icon :name icon)))
                    children))))
      (if dialog
          (hsx (<> (button :type "button" :class class :commandfor dialog :command "show-modal"
                     (when icon (hsx (~icon :name icon)))
                     children)
                   (~confirm-dialog :id dialog :title title :message confirm (act))))
          (act)))))

(defcomp ~meta (&key content)
  (hsx
   (div :id "editor-meta" :class "editor-fold mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted"
        :n-bind-class.open "unfolded"
     (span "created at " (short-time (content-created-at content)))
     (span "updated at " (short-time (content-updated-at content))))))

(defcomp ~restoring (&key space model content revision notes)
  (hsx
   (div :class "mb-6 rounded-md border border-accent/40 bg-accent/5 px-4 py-3 text-sm"
     (div :class "flex flex-wrap items-center justify-between gap-2"
       (p (strong "Restoring the version of " (short-time (revision-created-at revision)) ".")
          " Nothing is stored until you save a draft or publish.")
       (a :href (editor-url space model (content-id content)) :class "btn"
          (~icon :name :close) "Cancel"))
     (when notes
       (hsx (ul :class "mt-2 list-disc pl-5 text-warn"
              (loop :for note :in notes :collect
                (hsx (li (strong (getf note :field)) " " (getf note :note))))))))))

(defun duplicate-url (space model id)
  (render-uri (make-uri :path (content-url space model "new") :query `(("from" . ,id)))))

(defcomp ~duplicating (&key space model original)
  (hsx
   (div :class "mb-6 rounded-md border border-accent/40 bg-accent/5 px-4 py-3 text-sm"
     (div :class "flex flex-wrap items-center justify-between gap-2"
       (p (strong "A copy of " (content-label original model) ".")
          " Nothing is stored until you save a draft or publish.")
       (a :href (editor-url space model (content-id original)) :class "btn"
          (~icon :name :close) "Cancel")))))

(defcomp ~editor (&key space model content data errors restoring original)
  (let* ((space-name space)
         (model-name (model-name model))
         (id (if content (content-id content) "new"))
         (object-p (eq (model-kind model) :object))
         (published (and content (content-published-p content)))
         (draft (and content (content-draft-p content)))
         (preview-url (and draft (content-draft-key content)
                           (expand-url-template (model-preview-url model)
                                                :id id :draft-key (content-draft-key content)
                                                :slug (slug-value model (content-draft content)))))
         (public-url (and published (expand-url-template (model-public-url model)
                                                         :id id :slug (slug-value model (content-published content))))))
    (hsx
     (div :id "editor" :n-scope (format nil "koya.editor($el, ~:[false~;true~])" (or restoring original))
          :n-on-fetchredirect.window "koya.leave()"
       (div :class "sticky top-0 z-10 -mx-4 -mt-3 mb-8 border-b border-line bg-base/95 px-4 py-3 backdrop-blur"
         (div :class "flex items-center justify-between gap-3"
           (div :class "flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1"
             (h1 :class "flex min-w-0 flex-wrap items-baseline gap-x-3 text-2xl font-bold" model-name
               (unless object-p
                 (hsx (span :class "font-mono text-sm font-normal text-muted" id))))
             (when content (hsx (~status-badge :status (content-status content)))))
           (button :type "button" :class "btn btn-icon editor-fold-toggle" :aria-label "Menu"
                   :aria-controls (if content "editor-meta editor-actions" "editor-actions") :aria-expanded "false"
                   :n-on-click "unfolded = !unfolded" :n-bind-ariaexpanded "String(unfolded)"
             (span :n-bind-hidden "unfolded" (~icon :name :menu))
             (span :hidden t :n-bind-hidden "!unfolded" (~icon :name :close))))
         (when content (hsx (~meta :content content)))
         (div :id "editor-actions" :class "editor-fold mt-3 flex items-start justify-between gap-2 sm:flex-wrap sm:items-center"
              :n-bind-class.open "unfolded"
           (div :class "flex flex-1 flex-col gap-2 sm:flex-initial sm:flex-row sm:flex-wrap sm:items-center"
             (when preview-url (hsx (~external-link :href preview-url "Preview draft")))
             (when public-url (hsx (~external-link :href public-url "Published page")))
             (when (and content (model-history-p model))
               (hsx (a :href (history-url space-name model-name id) :class "btn"
                       (~icon :name :history) "History")))
             (when (and object-p (some (lambda (h) (webhook-covers-p h model-name)) (space-webhooks space)))
               (hsx (a :href (webhook-log-url space-name :model model-name) :class "btn"
                       (~icon :name :webhook) "Webhooks"))))
           (div :class "flex flex-1 flex-col gap-2 sm:flex-initial sm:flex-row sm:flex-wrap sm:items-center"
             (when (and published draft)
               (hsx (~action-button :space space-name :model model-name :id id :op "discard"
                                    :icon :discard :class "btn btn-danger" :title "Discard draft"
                                    :confirm "Discard the draft and go back to the published version?"
                                    "Discard draft")))
             (when (and content (not object-p))
               (hsx (a :href (duplicate-url space-name model-name id) :class "btn"
                       (~icon :name :duplicate) "Duplicate")))
             (~action-button :space space-name :model model-name :id id :op "save" :icon :save "Save draft")
             (~action-button :space space-name :model model-name :id id :op "publish" :icon :publish
                             :class "btn btn-primary" :title "Publish content"
                             :confirm "Publish this content? The site shows it as the form has it now."
                             "Publish"))))
       (~errors :id "editor-errors" :errors errors)
       (when restoring (hsx (~restoring :space space-name :model model :content content
                                        :revision (getf restoring :revision) :notes (getf restoring :notes))))
       (when original (hsx (~duplicating :space space-name :model model :original original)))
       (form :id "editor-form" :class "space-y-6" :n-ref "form"
             :n-on-submit.prevent (submit (editor-action :space space-name :model model-name :id id :op "save"))
             :n-on-input "track()" :n-on-change "track()"
         (when content
           (hsx (input :type "hidden" :name "updated-at" :value (content-updated-at content))))
         (let ((choices (multiple-value-call #'make-choices space-name (read-held space-name model (list data)))))
           (loop :for field :in (model-fields model) :collect
             (hsx (~editor-field :space space-name :model model-name :field field :data data :errors errors
                                 :choices choices)))))
       (when (and content (or published (not object-p)))
         (hsx (div :class "mt-12 flex flex-wrap items-center justify-between gap-4 border-t border-line pt-6 text-sm"
                (div
                  (p :class "font-medium text-danger" "Danger zone")
                  (p :class "text-muted"
                    (if object-p
                        "Unpublishing takes the content off the site."
                        "Unpublishing takes the content off the site; deleting removes it for good.")))
                (div :class "flex flex-wrap items-center gap-2"
                  (when published
                    (hsx (~action-button :space space-name :model model-name :id id :op "unpublish"
                                         :icon :unpublish :title "Unpublish content"
                                         :confirm "Unpublish this content? It comes off the site and stays here as a draft."
                                         "Unpublish")))
                  (unless object-p
                    (hsx (~action-button :space space-name :model model-name :id id :op "delete"
                                         :icon :delete :class "btn btn-danger" :title "Delete content"
                                         :confirm "Delete this content? This cannot be undone."
                                         "Delete")))))))
       (let ((references (and content (content-references space-name model-name id))))
         (when references
           (hsx (div :class "mt-6 border-t border-line pt-6"
                  (~referrers :space space-name :heading "Referenced by" :references references)))))))))

(defcomp ~editor-page (&key space model content data errors restoring original)
  (let ((model-name (model-name model)))
    (hsx
     (~layout :space space
              :crumbs (if (eq (model-kind model) :object)
                          (list (cons model-name nil))
                          (list (cons model-name (model-url space model-name))
                                (cons (if content (content-label content model) "new") nil)))
       (~editor :space space :model model :content content :data data :errors errors :restoring restoring
                :original original)
       (~media-picker-dialog :space space)
       (~reference-picker-dialog :space space)))))

(defun requested-revision (params content)
  (let ((raw (param params "revision")))
    (when (and raw content)
      (let* ((n (integer-text raw))
             (revision (and (typep n '(and (signed-byte 64) (integer 1)))
                            (find-revision (content-space content) (content-id content) n))))
        (values revision (null revision))))))

(defun requested-original (params space model content)
  (let ((id (param params "from")))
    (when (and id (null content))
      (let ((original (find-content space (model-name model) id)))
        (values original (null original))))))

(defun show-editor (params space model content)
  (set-title (format nil "~a · ~a · koya" (model-name model) space))
  (multiple-value-bind (revision unknown) (requested-revision params content)
    (multiple-value-bind (original missing) (requested-original params space model content)
      (let ((current (if content (content-data content :draft t) (default-data model))))
        (cond
          (revision
           (multiple-value-bind (data notes)
               (restore-data space model (content-id content) (revision-data revision) current)
             (hsx (~editor-page :space space :model model :content content :data data
                                :restoring (list :revision revision :notes notes)))))
          (unknown
           (hsx (~editor-page :space space :model model :content content :data current
                              :errors (list (list :field "revision"
                                                  :message "does not exist for this content; this is its current data")))))
          (original
           (hsx (~editor-page :space space :model model :data (duplicated-data model (content-data original :draft t))
                              :original original)))
          (missing
           (hsx (~editor-page :space space :model model :data current
                              :errors (list (list :field "from"
                                                  :message "does not exist in this model; this is an empty content")))))
          (t
           (hsx (~editor-page :space space :model model :content content :data current))))))))

(defun done (space model content message)
  (replace-url (editor-url space model (content-id content)))
  (hsx (<> (~editor :space space :model model :content content :data (content-data content :draft t))
           (~toast :message message))))

(defun changed-elsewhere (url)
  (set-response-status 409)
  (hsx (~toast :kind :error :clickable t
               :message (hsx (<> "This content was changed elsewhere after you opened it. "
                                 (a :href url :class "font-semibold underline" "Open it again")
                                 " to see the change; what you typed stays here until you do.")))))

(defun move-on (url message)
  (set-toast message)
  (send-to url))

(defaction editor-action :post (params)
  (let* ((space (param params "space"))
         (op (or (param params "op") "save"))
         (model (target-model params))
         (id (param params "id"))
         (object-p (and model (eq (model-kind model) :object)))
         (content (cond (object-p (find-object-content space (model-name model)))
                        ((and model id (not (new-p id))) (target-content params model)))))
    (cond
      ((null model) (action-refusal "Model not found." 404))
      ((not (member op '("save" "publish" "unpublish" "discard" "delete") :test #'string=))
       (action-refusal "Unknown action." 404))
      ((and (null content)
            (not (and (or object-p (equal id "new")) (member op '("save" "publish") :test #'string=))))
       (action-refusal "Content not found." 404))
      (t
       (let ((model-name (model-name model))
             (data (form->data model params)))
         (handler-case
             (cond
               ((string= op "delete")
                (destroy space model (content-id content))
                (move-on (model-url space model-name) "Content deleted."))
               ((string= op "unpublish")
                (done space model (unpublish space model (content-id content)) "Unpublished."))
               ((string= op "discard")
                (done space model (discard space model (content-id content) :since (param params "updated-at"))
                      "Draft discarded."))
               ((and object-p (string= op "publish"))
                (done space model (publish-object space model :data data :since (param params "updated-at")) "Published."))
               ((and object-p (null content))
                (done space model (update-object space model data) "Draft saved."))
               ((null content)
                (let ((made (create space model data :publish (string= op "publish"))))
                  (move-on (content-url space model-name (content-id made))
                      (if (string= op "publish") "Published." "Draft saved."))))
               ((string= op "publish")
                (done space model (publish space model (content-id content) :data data :since (param params "updated-at"))
                      "Published."))
               (t
                (multiple-value-bind (saved outcome) (update-draft space model (content-id content) data :replace t
                                                                   :since (param params "updated-at"))
                  (done space model saved (case outcome
                                            (:unchanged "Nothing to save.")
                                            (:published "Back to the published version: the draft is gone.")
                                            (t "Draft saved."))))))
           (validation-error (e)
             (set-response-status 422)
             (let ((errors (validation-error-errors e)))
               (hsx (<> (~errors :id "editor-errors" :errors errors)
                        (loop :for field :in (model-fields model) :collect
                          (hsx (~editor-field-errors :field field :errors errors :params params)))))))
           (koya-error (e)
             (if (equal (koya-error-code e) "changed_elsewhere")
                 (changed-elsewhere (editor-url space model (content-id content)))
                 (action-refused e)))))))))
