(defpackage #:koya-server/pages/s/<space>/m/<model>/<id>
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya/core/schema
                #:model-kind #:model-fields #:field-name #:field-type #:field-option
                #:webhook-covers-p
                #:model-name #:model-preview-url #:model-public-url)
  (:import-from #:koya/core/validate #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/lib/query #:make-query)
  (:import-from #:koya-server/db/contents
                #:list-contents #:find-content #:content-id #:content-status #:content-published #:content-draft
                #:content-created-at #:content-updated-at #:content-draft-key #:content-data)
  (:import-from #:koya-server/db/schema-store
                #:find-model #:space-webhooks)
  (:import-from #:koya-server/lib/content-service
                #:resolve-model #:default-data #:create #:update-draft #:publish #:unpublish #:discard #:destroy)
  (:import-from #:koya-server/lib/http #:path-param #:api-error)
  (:import-from #:koya-server/lib/forms #:form->data)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:redirect-to #:param #:set-flash #:expand-url-template
                #:short-time #:content-label #:~layout #:~status-badge #:~errors #:~icon #:content-url #:model-url)
  (:import-from #:koya-server/pages/s/<space>/webhooks #:webhook-log-url)
  (:import-from #:koya-server/components/field-input #:~field-input)
  (:import-from #:koya-server/actions/media-picker #:~media-picker-dialog)
  (:import-from #:koya-server/db/media #:find-media)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/s/<space>/m/<model>/<id>)

(defun new-p (id) (string= id "new"))

(defun media-for (space field value)
  "The media struct behind a :media field's id, or NIL."
  (and (eq (field-type field) :media) (stringp value) (plusp (length value))
       (find-media space value)))

(defun reference-options (space field)
  "Selectable contents of FIELD's target model as (id . label), sorted by label."
  (when (eq (field-type field) :reference)
    (let ((target (find-model space (field-option field :model))))
      (when target
        (sort (mapcar (lambda (content) (cons (content-id content) (content-label content target)))
                      (list-contents space (model-name target) target
                                     (make-query :limit 1000) :status :all))
              #'string-lessp :key #'cdr)))))

(defun field-error (errors name)
  (let ((e (find name errors :key (lambda (e) (getf e :field)) :test #'string=)))
    (and e (getf e :message))))

(defcomp ~external-link (&key href children)
  (hsx (a :href href :target "_blank" :rel "noopener" :class "btn" children (~icon :name :external))))

(defcomp ~action-button (&key value (class "btn") onclick icon children)
  "A submit button for the editor form, usable outside the form element."
  (hsx (button :type "submit" :form "editor-form" :name "action" :value value :class class :onclick onclick
         (when icon (hsx (~icon :name icon)))
         children)))

(defcomp ~meta (&key content)
  (hsx
   (div :class "mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted"
     (~status-badge :status (content-status content))
     (span "created at " (short-time (content-created-at content)))
     (span "updated at " (short-time (content-updated-at content))))))

(defcomp ~editor (&key space model content data errors)
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
     (~layout :space space-name
              :crumbs (if object-p
                          (list (cons model-name nil))
                          (list (cons model-name (model-url space-name model-name))
                                (cons (if content id "new") nil)))
       ;; Sticky action bar: title and metadata on the left, links and actions on the right.
       ;; -mt-3 takes back the bar's own top padding so the title starts where every
       ;; other page's title does, under the layout's padding alone.
       (div :class "sticky top-0 z-10 -mx-4 -mt-3 mb-8 border-b border-line bg-base/95 px-4 py-3 backdrop-blur"
         (h1 :class "text-2xl font-bold" model-name
           (unless object-p
             (hsx (span :class "ml-3 font-mono text-sm font-normal text-muted" id))))
         (when content (hsx (~meta :content content)))
         ;; under the title, the full width: where the content can be seen on the
         ;; left, what can be done to it on the right
         (div :class "mt-3 flex flex-wrap items-center justify-between gap-2"
           (div :class "flex flex-wrap items-center gap-2"
             (when preview-url (hsx (~external-link :href preview-url "Preview draft")))
             (when public-url (hsx (~external-link :href public-url "Published page")))
             ;; an object model has no list page to carry this, and this editor
             ;; is the whole of its screen -- but only where a hook can fire
             (when (and object-p (some (lambda (h) (webhook-covers-p h model-name)) (space-webhooks space)))
               (hsx (a :href (webhook-log-url space-name :model model-name) :class "btn"
                       (~icon :name :webhook) "Webhooks"))))
           (div :class "flex flex-wrap items-center gap-2"
             (when (and published draft)
               (hsx (~action-button :value "discard" :icon :discard :class "btn btn-danger"
                                    :onclick "return confirm('Discard the draft and go back to the published version?')"
                                    "Discard draft")))
             (~action-button :value "save" :icon :save "Save draft")
             (~action-button :value "publish" :icon :publish :class "btn btn-primary" "Publish"))))
       (~errors :errors errors)
       (form :id "editor-form" :method "post" :action (content-url space-name model-name id)
             :class "space-y-6" :data-editor-form t
         (loop :for field :in (model-fields model) :collect
           (hsx (~field-input :field field
                              :value (and data (gethash (field-name field) data))
                              :references (reference-options space field)
                              :media (media-for space field (and data (gethash (field-name field) data)))
                              :error (field-error errors (field-name field))))))
       ;; one picker per page, shared by :media fields and Quill's image button
       (~media-picker-dialog :space space-name)
       ;; the two ways to take content off the site, kept away from the daily ones
       (when content
         (hsx (div :class "mt-12 flex flex-wrap items-center justify-between gap-4 border-t border-line pt-6 text-sm"
                (div
                  (p :class "font-medium text-danger" "Danger zone")
                  (p :class "text-muted"
                    (if object-p
                        "Unpublishing takes the content off the site; deleting empties it and starts over."
                        "Unpublishing takes the content off the site; deleting removes it for good.")))
                (div :class "flex flex-wrap items-center gap-2"
                  (when published (hsx (~action-button :value "unpublish" :icon :unpublish "Unpublish")))
                  (~action-button :value "delete" :icon :delete :class "btn btn-danger"
                                  :onclick "return confirm('Delete this content?')" "Delete")))))))))

(defun load-editor (params)
  "Return (values space model content) for the route, or signal 404 for unknown model."
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
     (api-error ()
       (set-response-status 404)
       (hsx (~layout (h1 :class "text-xl font-bold" "Model not found"))))))

(defun @get (params)
  (with-owner
    (with-editor (space model content) params
      (set-title (format nil "~a · ~a · koya" (model-name model) space))
      (hsx (~editor :space space :model model :content content
                    :data (if content (content-data content :draft t) (default-data model)))))))

(defun @post (params)
  (with-owner-post
    (with-editor (space model content) params
      (set-title (format nil "~a · ~a · koya" (model-name model) space))
      (let* ((action (or (param params "action") "save"))
             (space-name space)
             (model-name (model-name model))
             (data (form->data model params)))
        (handler-case
            (cond
              ((and (null content) (member action '("delete" "unpublish" "discard") :test #'string=))
               ;; posted against /new: there is nothing to act on
               (set-response-status 404)
               (hsx (~layout :space space-name (h1 :class "text-xl font-bold" "Content not found"))))
              ((string= action "delete")
               (destroy space model (content-id content))
               (set-flash "Content deleted.")
               (redirect-to (model-url space-name model-name)))
              ((string= action "unpublish")
               (unpublish space model (content-id content))
               (set-flash "Unpublished.")
               (redirect-to (content-url space-name model-name (content-id content))))
              ((string= action "discard")
               (discard space model (content-id content))
               (set-flash "Draft discarded.")
               (redirect-to (content-url space-name model-name (content-id content))))
              ((string= action "publish")
               (let ((result (if content
                                 (publish space model (content-id content) data)
                                 (create space model data :publish t))))
                 (set-flash "Published.")
                 (redirect-to (content-url space-name model-name (content-id result)))))
              (t
               (let ((result (if content
                                 (update-draft space model (content-id content) data :replace t)
                                 (create space model data))))
                 (set-flash "Draft saved.")
                 (redirect-to (content-url space-name model-name (content-id result))))))
          (validation-error (e)
            (set-response-status 422)
            (hsx (~editor :space space :model model :content content :data data
                          :errors (validation-error-errors e)))))))))
