(defpackage #:koya-server/pages/s/<space>/m/<model>/<id>
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya/core/schema
                #:model-kind #:model-fields #:field-name #:space-name #:model-name
                #:model-preview-url #:model-public-url)
  (:import-from #:koya/core/validate #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/db/contents
                #:find-content #:content-id #:content-status #:content-published #:content-draft
                #:content-updated-at #:content-draft-key #:content-data)
  (:import-from #:koya-server/lib/content-service
                #:resolve-model #:create #:update-draft #:publish #:unpublish #:destroy)
  (:import-from #:koya-server/lib/http #:path-param #:api-error)
  (:import-from #:koya-server/lib/forms #:form->data)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:redirect-to #:param #:set-flash #:expand-url-template
                #:~layout #:~status-badge #:~errors #:content-url #:model-url)
  (:import-from #:koya-server/components/field-input #:~field-input)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/s/<space>/m/<model>/<id>)

(defun new-p (id) (string= id "new"))

(defun field-error (errors name)
  (let ((e (find name errors :key (lambda (e) (getf e :field)) :test #'string=)))
    (and e (getf e :message))))

(defcomp ~external-link (&key href children)
  (hsx (a :href href :target "_blank" :rel "noopener" :class "btn" children " ↗")))

(defcomp ~editor (&key space model content data errors)
  (let* ((space-name (space-name space))
         (model-name (model-name model))
         (id (if content (content-id content) "new"))
         (published (and content (content-published content)))
         (draft (and content (content-draft content)))
         (preview-url (and draft (content-draft-key content)
                           (expand-url-template (model-preview-url model)
                                                :id id :draft-key (content-draft-key content))))
         (public-url (and published (expand-url-template (model-public-url model) :id id))))
    (hsx
     (~layout :space space-name
              :crumbs (list (cons model-name (model-url space-name model-name))
                            (cons (if content id "new") nil))
       (div :class "mb-6 flex flex-wrap items-center justify-between gap-3"
         (div
           (h1 :class "text-2xl font-bold" model-name
             (span :class "ml-3 font-mono text-sm font-normal text-muted" id))
           (if content
               (hsx (div :class "mt-1 flex items-center gap-3 text-sm text-muted"
                      (~status-badge :status (content-status content))
                      (span "updated " (content-updated-at content))))
               (hsx (<>))))
         (div :class "flex items-center gap-2"
           (if preview-url (hsx (~external-link :href preview-url "Preview draft")) (hsx (<>)))
           (if public-url (hsx (~external-link :href public-url "Published page")) (hsx (<>)))))
       (~errors :errors errors)
       (form :method "post" :action (content-url space-name model-name id) :class "space-y-6" :data-editor-form t
         (loop :for field :in (model-fields model) :collect
           (hsx (~field-input :field field
                              :value (and data (gethash (field-name field) data))
                              :error (field-error errors (field-name field)))))
         (div :class "flex flex-wrap items-center gap-3 border-t border-line pt-6"
           (button :type "submit" :name "action" :value "save" :class "btn" "Save draft")
           (button :type "submit" :name "action" :value "publish" :class "btn btn-primary" "Publish")
           (if published
               (hsx (button :type "submit" :name "action" :value "unpublish" :class "btn" "Unpublish"))
               (hsx (<>)))
           (if content
               (hsx (button :type "submit" :name "action" :value "delete" :class "btn btn-danger ml-auto"
                            :onclick "return confirm('Delete this content?')" "Delete"))
               (hsx (<>)))))))))

(defun load-editor (params)
  "Return (values space model content) for the route, or signal 404 for unknown model."
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (let ((id (path-param params :id)))
      (values space model (and (not (new-p id))
                               (find-content (space-name space) (model-name model) id))))))

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
      (set-title (format nil "~a · ~a · koya" (model-name model) (space-name space)))
      (hsx (~editor :space space :model model :content content
                    :data (and content (content-data content :draft t)))))))

(defun @post (params)
  (with-owner-post
    (with-editor (space model content) params
      (set-title (format nil "~a · ~a · koya" (model-name model) (space-name space)))
      (let* ((action (or (param params "action") "save"))
             (space-name (space-name space))
             (model-name (model-name model))
             (data (form->data model params)))
        (handler-case
            (cond
              ((string= action "delete")
               (destroy space model (content-id content))
               (set-flash "Content deleted.")
               (redirect-to (model-url space-name model-name)))
              ((string= action "unpublish")
               (unpublish space model (content-id content))
               (set-flash "Unpublished.")
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
