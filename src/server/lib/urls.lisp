(defpackage #:koya-server/lib/urls
  (:use #:cl)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:export #:space-url
           #:model-url
           #:content-url
           #:expand-url-template))
(in-package #:koya-server/lib/urls)

;;; Where the admin UI's pages are, and where a model says its contents are shown.

(defun space-url (space) (format nil "/s/~a" space))
(defun model-url (space model) (format nil "/s/~a/m/~a" space model))
(defun content-url (space model id) (format nil "/s/~a/m/~a/~a" space model id))

(defun expand-url-template (template &key id draft-key)
  "Fill {CONTENT_ID} and {DRAFT_KEY} in a model's preview/public URL template."
  (and template
       (regex-replace-all "\\{DRAFT_KEY\\}"
                          (regex-replace-all "\\{CONTENT_ID\\}" template (or id ""))
                          (or draft-key ""))))
