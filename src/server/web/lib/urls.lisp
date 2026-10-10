(defpackage #:koya-server/web/lib/urls
  (:use #:cl)
  (:import-from #:koya-core/json #:blank-p)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:import-from #:koya-core/schema #:model-kind #:model-name)
  (:export #:space-url
           #:model-url
           #:content-url
           #:editor-url
           #:history-url
           #:deploys-url
           #:webhook-log-url
           #:expand-url-template))
(in-package #:koya-server/web/lib/urls)

(defun space-url (space) (format nil "/s/~a" space))
(defun model-url (space model) (format nil "/s/~a/m/~a" space model))
(defun content-url (space model id) (format nil "/s/~a/m/~a/~a" space model id))

(defun editor-url (space model id)
  (if (eq (model-kind model) :object)
      (model-url space (model-name model))
      (content-url space (model-name model) id)))

(defun history-url (space model id &key published-only page)
  (render-uri (make-uri :path (format nil "~a/history" (content-url space model id))
                        :query (append (when published-only '(("view" . "published")))
                                       (when (and page (> page 1)) `(("page" . ,page)))))))

(defun deploys-url (space &key page)
  (render-uri (make-uri :path (format nil "~a/deploys" (space-url space))
                        :query (when (and page (> page 1)) `(("page" . ,page))))))

(defun webhook-log-url (space &key label model page)
  (render-uri (make-uri :path (format nil "~a/webhooks" (space-url space))
                        :query (append (unless (blank-p label) `(("label" . ,label)))
                                       (unless (blank-p model) `(("model" . ,model)))
                                       (when (and page (> page 1)) `(("page" . ,page)))))))

(defun expand-url-template (template &key id draft-key slug)
  (and template
       (or (not (search "{CONTENT_SLUG}" template)) (not (blank-p slug)))
       (regex-replace-all "\\{CONTENT_SLUG\\}"
                          (regex-replace-all "\\{DRAFT_KEY\\}"
                                             (regex-replace-all "\\{CONTENT_ID\\}" template (or id ""))
                                             (or draft-key ""))
                          (or slug ""))))
