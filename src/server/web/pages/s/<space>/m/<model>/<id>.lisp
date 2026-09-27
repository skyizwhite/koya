(defpackage #:koya-server/web/pages/s/<space>/m/<model>/<id>
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-core/schema
                #:model-kind #:model-fields #:field-name #:field-type #:webhook-covers-p
                #:model-name #:model-preview-url #:model-public-url)
  (:import-from #:koya-core/validate #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/usecases/contents
                #:find-content #:create #:update-draft #:publish #:unpublish #:discard #:destroy)
  (:import-from #:koya-server/web/lib/target #:target-model #:target-content)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-status #:content-published #:content-draft
                #:content-created-at #:content-updated-at #:content-draft-key #:content-data
                #:default-data #:content-label)
  (:import-from #:koya-server/usecases/spaces #:find-space)
  (:import-from #:koya-server/web/lib/http
                #:path-param #:param)
  (:import-from #:koya-server/domain/errors
                #:koya-error #:not-found)
  (:import-from #:koya-server/web/lib/forms #:form->data)
  (:import-from #:koya-server/usecases/listing #:reference-options)
  (:import-from #:koya-server/web/lib/display #:short-time)
  (:import-from #:koya-server/web/lib/urls
                #:expand-url-template #:content-url #:model-url #:history-url #:webhook-log-url)
  (:import-from #:koya-server/web/lib/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/elements #:~status-badge #:~errors)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast
                #:set-toast #:~toast-oob #:action-refusal #:action-refused)
  (:import-from #:koya-server/usecases/media #:find-media)
  (:import-from #:koya-server/web/ui/content/field-input #:~field-input)
  (:import-from #:koya-server/usecases/revisions #:restore-data #:find-revision)
  (:import-from #:koya-server/web/ui/media/picker #:~media-picker-dialog)
  (:import-from #:koya-server/domain/revision #:revision-data #:revision-created-at)
  (:import-from #:koya-server/usecases/schema #:resolve-model #:find-model)
  (:import-from #:koya-server/usecases/webhooks #:space-webhooks)
  (:export #:@get #:editor-action))
(in-package #:koya-server/web/pages/s/<space>/m/<model>/<id>)

(defun new-p (id) (string= id "new"))

(defun media-for (space field value)
  (and (eq (field-type field) :media) (stringp value) (plusp (length value))
       (find-media space value)))

(defun field-error (errors name)
  (let ((e (find name errors :key (lambda (e) (getf e :field)) :test #'string=)))
    (and e (getf e :message))))

(defcomp ~external-link (&key href children)
  (hsx (a :href href :target "_blank" :rel "noopener" :class "btn" children (~icon :name :external))))

(defcomp ~action-button (&key space model id op (class "btn") confirm icon children)
  (hsx (button :type "button" :class class
               :data-save-draft (equal op "save")
               :hx-post (editor-action :space space :model model :id id :op op)
               :hx-include "#editor-form" :hx-target "#editor" :hx-swap "outerHTML"
               :hx-confirm confirm
         (when icon (hsx (~icon :name icon)))
         children)))

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
       (a :href (content-url space (model-name model) (content-id content)) :class "btn"
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
     (div :id "editor"
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
                                    :icon :discard :class "btn btn-danger"
                                    :confirm "Discard the draft and go back to the published version?"
                                    "Discard draft")))
             (~action-button :space space-name :model model-name :id id :op "save" :icon :save "Save draft")
             (~action-button :space space-name :model model-name :id id :op "publish" :icon :publish
                             :class "btn btn-primary" "Publish"))))
       (~errors :errors errors)
       (when restoring (hsx (~restoring :space space-name :model model :content content
                                        :revision (getf restoring :revision) :notes (getf restoring :notes))))
       (form :id "editor-form" :class "space-y-6" :data-editor-form t :data-unsaved (and (or restoring errors) t)
             :hx-post (editor-action :space space-name :model model-name :id id :op "save")
             :hx-target "#editor" :hx-swap "outerHTML"
         (loop :for field :in (model-fields model) :collect
           (hsx (~field-input :field field
                              :value (and data (gethash (field-name field) data))
                              :references (reference-options space field)
                              :media (media-for space field (and data (gethash (field-name field) data)))
                              :error (field-error errors (field-name field))))))
       (when content
         (hsx (div :class "mt-12 flex flex-wrap items-center justify-between gap-4 border-t border-line pt-6 text-sm"
                (div
                  (p :class "font-medium text-danger" "Danger zone")
                  (p :class "text-muted"
                    (if object-p
                        "Unpublishing takes the content off the site; deleting empties it and starts over."
                        "Unpublishing takes the content off the site; deleting removes it for good.")))
                (div :class "flex flex-wrap items-center gap-2"
                  (when published
                    (hsx (~action-button :space space-name :model model-name :id id :op "unpublish"
                                         :icon :unpublish "Unpublish")))
                  (~action-button :space space-name :model model-name :id id :op "delete"
                                  :icon :delete :class "btn btn-danger" :confirm "Delete this content?"
                                  "Delete")))))))))

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

(defun load-editor (params)
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (let ((id (path-param params :id)))
      (values space model (and (not (new-p id))
                               (find-content space (model-name model) id))))))

(defmacro with-editor ((space model content) params &body body)
  `(handler-case
       (multiple-value-bind (,space ,model ,content) (load-editor ,params)
         (if (and (null ,content) (not (new-p (path-param ,params :id))))
             (progn (set-response-status 404)
                    (hsx (~layout :space (path-param ,params :space) (h1 :class "text-xl font-bold" "Content not found"))))
             (progn ,@body)))
     (not-found ()
       (set-response-status 404)
       (hsx (~layout (h1 :class "text-xl font-bold" "Model not found"))))))

(defun requested-revision (params content)
  (let ((raw (param params "revision")))
    (when (and raw content)
      (let* ((n (ignore-errors (parse-integer raw)))
             (revision (and n (find-revision (content-id content) n))))
        (values revision (null revision))))))

(defun @get (params)
  (with-editor (space model content) params
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
           (hsx (~editor-page :space space :model model :content content :data current))))))))

(defun done (space model content message)
  (set-response-header :hx-replace-url (content-url space (model-name model) (content-id content)))
  (hsx (<> (~editor :space space :model model :content content :data (content-data content :draft t))
           (~toast-oob :message message))))

(defun move-on (url message)
  (set-toast message)
  (set-response-header :hx-redirect url)
  (hsx (<>)))

(defaction editor-action :post (params)
  (let* ((space (param params "space"))
         (op (or (param params "op") "save"))
         (model (target-model params))
         (id (param params "id"))
         (content (and model id (not (new-p id)) (target-content params model))))
    (cond
      ((null model) (action-refusal "Model not found." 404))
      ((and (null content) (not (and (equal id "new") (member op '("save" "publish") :test #'string=))))
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
                (done space model (discard space model (content-id content)) "Draft discarded."))
               ((null content)
                (let ((made (create space model data :publish (string= op "publish"))))
                  (move-on (content-url space model-name (content-id made))
                      (if (string= op "publish") "Published." "Draft saved."))))
               ((string= op "publish")
                (done space model (publish space model (content-id content) data) "Published."))
               (t
                (multiple-value-bind (saved outcome) (update-draft space model (content-id content) data :replace t)
                  (done space model saved (case outcome
                                            (:unchanged "Nothing to save.")
                                            (:published "Back to the published version: the draft is gone.")
                                            (t "Draft saved."))))))
           (validation-error (e)
             (set-response-status 422)
             (hsx (~editor :space space :model model :content content :data data
                           :errors (validation-error-errors e))))
           (koya-error (e) (action-refused e))))))))
