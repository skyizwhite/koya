(defpackage #:koya-server/web/urls
  (:use #:cl)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:import-from #:koya-server/web/http #:blank-p)
  (:export #:space-url
           #:model-url
           #:content-url
           #:history-url
           #:deploys-url
           #:webhook-log-url
           #:expand-url-template))
(in-package #:koya-server/web/urls)

;;; Where the admin UI's pages are, and where a model says its contents are shown.
;;; A page's URL is here once another page links to it: pages do not import one
;;; another.

(defun space-url (space) (format nil "/s/~a" space))
(defun model-url (space model) (format nil "/s/~a/m/~a" space model))
(defun content-url (space model id) (format nil "/s/~a/m/~a/~a" space model id))

(defun history-url (space model id &key published-only page)
  (render-uri (make-uri :path (format nil "~a/history" (content-url space model id))
                        :query (append (when published-only '(("view" . "published")))
                                       (when (and page (> page 1)) `(("page" . ,page)))))))

(defun deploys-url (space &key page)
  (render-uri (make-uri :path (format nil "~a/deploys" (space-url space))
                        :query (when (and page (> page 1)) `(("page" . ,page))))))

(defun webhook-log-url (space &key label model page)
  "SPACE's webhook log, narrowed to LABEL and/or MODEL, at PAGE."
  (render-uri (make-uri :path (format nil "~a/webhooks" (space-url space))
                        :query (append (unless (blank-p label) `(("label" . ,label)))
                                       (unless (blank-p model) `(("model" . ,model)))
                                       (when (and page (> page 1)) `(("page" . ,page)))))))

(defun expand-url-template (template &key id draft-key)
  "Fill {CONTENT_ID} and {DRAFT_KEY} in a model's preview/public URL template."
  (and template
       (regex-replace-all "\\{DRAFT_KEY\\}"
                          (regex-replace-all "\\{CONTENT_ID\\}" template (or id ""))
                          (or draft-key ""))))
