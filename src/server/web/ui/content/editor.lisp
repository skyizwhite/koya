(defpackage #:koya-server/web/ui/content/editor
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/lib/binds #:on-submit #:on-click)
  (:import-from #:koya-core/schema
                #:model-kind #:model-fields #:field-name #:field-type #:webhook-covers-p
                #:model-name #:model-preview-url #:model-public-url #:field-fields)
  (:import-from #:koya-core/validate #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/usecases/contents
                #:create #:update-draft #:publish #:unpublish #:discard #:destroy
                #:update-object #:publish-object #:content-references)
  (:import-from #:koya-server/web/lib/target #:target-model #:target-content)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-space #:content-status #:content-published #:content-draft
                #:content-created-at #:content-updated-at #:content-draft-key #:content-data
                #:default-data #:content-label)
  (:import-from #:koya-server/web/lib/http #:param)
  (:import-from #:koya-server/domain/errors
                #:koya-error #:koya-error-code)
  (:import-from #:koya-server/web/lib/forms #:form->data)
  (:import-from #:koya-server/usecases/listing #:reference-options #:find-object-content)
  (:import-from #:koya-server/web/lib/display #:short-time)
  (:import-from #:koya-server/web/lib/urls
                #:expand-url-template #:content-url #:model-url #:history-url #:webhook-log-url #:editor-url)
  (:import-from #:koya-server/web/lib/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/elements #:~status-badge #:~errors #:~confirm-dialog #:~go-to #:~replace-url #:~referrers)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast
                #:set-toast #:~toast #:action-refusal #:action-refused)
  (:import-from #:koya-server/usecases/media #:find-media)
  (:import-from #:koya-server/web/ui/content/field-input #:~field-input #:~field-error #:~custom-input)
  (:import-from #:koya-server/usecases/revisions #:restore-data #:find-revision)
  (:import-from #:koya-server/web/ui/media/picker #:~media-picker-dialog)
  (:import-from #:koya-server/domain/revision #:revision-data #:revision-created-at)
  (:import-from #:koya-server/usecases/webhooks #:space-webhooks)
  (:export #:new-p #:show-editor #:editor-action))
(in-package #:koya-server/web/ui/content/editor)

(defun new-p (id) (string= id "new"))

(defun media-for (space field value)
  (and (eq (field-type field) :media) (stringp value) (plusp (length value))
       (find-media space value)))

(defun field-error (errors name)
  (let ((e (find name errors :key (lambda (e) (getf e :field)) :test #'string=)))
    (and e (getf e :message))))

(defun inner-path (field inner)
  (format nil "~a.~a" (field-name field) (field-name inner)))

(defcomp ~editor-field (&key space field data errors)
  (let ((value (and data (gethash (field-name field) data))))
    (if (eq (field-type field) :custom)
        (hsx (~custom-input :field field :error (field-error errors (field-name field))
               (loop :for inner :in (field-fields field) :collect
                 (let ((inner-value (and (hash-table-p value) (gethash (field-name inner) value))))
                   (hsx (~field-input :field inner :parent field :value inner-value
                                      :references (reference-options space inner)
                                      :media (media-for space inner inner-value)
                                      :error (field-error errors (inner-path field inner))))))))
        (hsx (~field-input :field field :value value
                           :references (reference-options space field)
                           :media (media-for space field value)
                           :error (field-error errors (field-name field)))))))

(defcomp ~editor-field-errors (&key field errors)
  (hsx
   (<> (~field-error :field field :error (field-error errors (field-name field)))
       (when (eq (field-type field) :custom)
         (loop :for inner :in (field-fields field) :collect
           (hsx (~field-error :field inner :parent field :error (field-error errors (inner-path field inner)))))))))

(defcomp ~external-link (&key href children)
  (hsx (a :href href :target "_blank" :rel "noopener" :class "btn" children (~icon :name :external))))

(defcomp ~action-button (&key space model id op (class "btn") title confirm icon children)
  (let ((dialog (and confirm (format nil "confirm-~a" op))))
    (flet ((post ()
             (hsx (button :type "button" :class class
                          :commandfor dialog :command (and dialog "close")
                          :nm-bind (on-click (editor-action :space space :model model :id id :op op)
                                             :data "koya.form($refs.form)"
                                             :binds (and (equal op "save") "disabled: () => _unchanged()"))
                    (when icon (hsx (~icon :name icon)))
                    children))))
      (if dialog
          (hsx (<> (button :type "button" :class class :commandfor dialog :command "show-modal"
                     (when icon (hsx (~icon :name icon)))
                     children)
                   (~confirm-dialog :id dialog :title title :message confirm (post))))
          (post)))))

(defcomp ~meta (&key content)
  (hsx
   (div :class "mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted"
     (~status-badge :status (content-status content))
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

(defcomp ~editor (&key space model content data errors restoring)
  (let* ((space-name space)
         (model-name (model-name model))
         (id (if content (content-id content) "new"))
         (object-p (eq (model-kind model) :object))
         (published (and content (content-published content)))
         (draft (and content (content-draft content)))
         (preview-url (and draft (content-draft-key content)
                           (expand-url-template (model-preview-url model)
                                                :id id :draft-key (content-draft-key content))))
         (public-url (and published (expand-url-template (model-public-url model) :id id))))
    (hsx
     (div :id "editor" :nm-data (format nil "...koya.editor(this, ~:[false~;true~])" (or restoring errors))
       (div :class "sticky top-0 z-10 -mx-4 -mt-3 mb-8 border-b border-line bg-base/95 px-4 py-3 backdrop-blur"
         (h1 :class "text-2xl font-bold" model-name
           (unless object-p
             (hsx (span :class "ml-3 font-mono text-sm font-normal text-muted" id))))
         (when content (hsx (~meta :content content)))
         (div :class "mt-3 flex flex-wrap items-center justify-between gap-2"
           (div :class "flex flex-wrap items-center gap-2"
             (when preview-url (hsx (~external-link :href preview-url "Preview draft")))
             (when public-url (hsx (~external-link :href public-url "Published page")))
             (when content
               (hsx (a :href (history-url space-name model-name id) :class "btn"
                       (~icon :name :history) "History")))
             (when (and object-p (some (lambda (h) (webhook-covers-p h model-name)) (space-webhooks space)))
               (hsx (a :href (webhook-log-url space-name :model model-name) :class "btn"
                       (~icon :name :webhook) "Webhooks"))))
           (div :class "flex flex-wrap items-center gap-2"
             (when (and published draft)
               (hsx (~action-button :space space-name :model model-name :id id :op "discard"
                                    :icon :discard :class "btn btn-danger" :title "Discard draft"
                                    :confirm "Discard the draft and go back to the published version?"
                                    "Discard draft")))
             (~action-button :space space-name :model model-name :id id :op "save" :icon :save "Save draft")
             (~action-button :space space-name :model model-name :id id :op "publish" :icon :publish
                             :class "btn btn-primary" :title "Publish content"
                             :confirm "Publish this content? The site shows it as the form has it now."
                             "Publish"))))
       (~errors :id "editor-errors" :errors errors)
       (when restoring (hsx (~restoring :space space-name :model model :content content
                                        :revision (getf restoring :revision) :notes (getf restoring :notes))))
       (form :id "editor-form" :class "space-y-6" :nm-ref "form"
             :nm-bind (on-submit (editor-action :space space-name :model model-name :id id :op "save")
                                 :binds "oninput: () => _track(), onchange: () => _track()")
         (when content
           (hsx (input :type "hidden" :name "updated-at" :value (content-updated-at content))))
         (loop :for field :in (model-fields model) :collect
           (hsx (~editor-field :space space :field field :data data :errors errors))))
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

(defcomp ~editor-page (&key space model content data errors restoring)
  (let ((model-name (model-name model)))
    (hsx
     (~layout :space space
              :crumbs (if (eq (model-kind model) :object)
                          (list (cons model-name nil))
                          (list (cons model-name (model-url space model-name))
                                (cons (if content (content-label content model) "new") nil)))
       (~editor :space space :model model :content content :data data :errors errors :restoring restoring)
       (~media-picker-dialog :space space)))))

(defun requested-revision (params content)
  (let ((raw (param params "revision")))
    (when (and raw content)
      (let* ((n (ignore-errors (parse-integer raw)))
             (revision (and n (find-revision (content-space content) (content-id content) n))))
        (values revision (null revision))))))

(defun show-editor (params space model content)
  (set-title (format nil "~a · ~a · koya" (model-name model) space))
  (multiple-value-bind (revision unknown) (requested-revision params content)
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
        (t
         (hsx (~editor-page :space space :model model :content content :data current)))))))

(defun done (space model content message)
  (hsx (<> (~editor :space space :model model :content content :data (content-data content :draft t))
           (~replace-url :url (editor-url space model (content-id content)))
           (~toast :message message))))

(defun changed-elsewhere (url)
  (set-response-status 409)
  (hsx (~toast :kind :error :clickable t
               :message (hsx (<> "This content was changed elsewhere after you opened it. "
                                 (a :href url :class "font-semibold underline" "Open it again")
                                 " to see the change; what you typed stays here until you do.")))))

(defun move-on (url message)
  (set-toast message)
  (hsx (~go-to :url url :on-purpose t)))

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
                (done space model (publish-object space model data :since (param params "updated-at")) "Published."))
               ((and object-p (null content))
                (done space model (update-object space model data) "Draft saved."))
               ((null content)
                (let ((made (create space model data :publish (string= op "publish"))))
                  (move-on (content-url space model-name (content-id made))
                      (if (string= op "publish") "Published." "Draft saved."))))
               ((string= op "publish")
                (done space model (publish space model (content-id content) data :since (param params "updated-at"))
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
                          (hsx (~editor-field-errors :field field :errors errors)))))))
           (koya-error (e)
             (if (equal (koya-error-code e) "changed_elsewhere")
                 (changed-elsewhere (editor-url space model (content-id content)))
                 (action-refused e)))))))))
