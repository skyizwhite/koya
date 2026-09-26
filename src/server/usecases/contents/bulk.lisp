(defpackage #:koya-server/usecases/contents/bulk
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-name)
  (:import-from #:koya-core/validate
                #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/usecases/ports/contents #:find-content)
  (:import-from #:koya-server/domain/content #:content-published #:content-draft)
  (:import-from #:koya-server/domain/errors
                #:koya-error #:koya-error-message)
  (:import-from #:koya-server/usecases/contents/write #:publish #:unpublish #:destroy)
  (:export #:bulk-action-p
           #:apply-to-each))
(in-package #:koya-server/usecases/contents/bulk)

;;; What is done to a selection of contents: one at a time through contents/write,
;;; so validation, timestamps and webhooks behave as they do for a single one. One
;;; that fails leaves the rest to go through.

(defun bulk-action-function (action)
  (cond ((equal action "publish") #'publish)
        ((equal action "unpublish") #'unpublish)
        ((equal action "delete") #'destroy)))

(defun bulk-action-p (action)
  "True for \"publish\", \"unpublish\" and \"delete\"."
  (and (bulk-action-function action) t))

(defun nothing-to-do-p (action content)
  "True when ACTION would change nothing. A selection is a tick of the header box,
so it holds published and draft alike: publishing what is published again would
move revisedAt and fire a webhook, and unpublishing a draft would reissue its
draft key and break a preview link."
  (and content
       (cond ((equal action "publish") (and (content-published content) (null (content-draft content))))
             ((equal action "unpublish") (null (content-published content)))
             (t nil))))

(defun failure-message (condition)
  "A validation failure as the field that stopped it, not the condition's report."
  (typecase condition
    (validation-error
     (format nil "~{~a~^, ~}"
             (mapcar (lambda (e) (format nil "~a ~a" (getf e :field) (getf e :message)))
                     (validation-error-errors condition))))
    (koya-error (koya-error-message condition))
    (t (princ-to-string condition))))

(defun apply-to-each (space model ids action)
  "Do ACTION to each of IDS. Returns (values DONE SKIPPED FAILED FIRST-MESSAGE)."
  (let ((function (bulk-action-function action))
        (model-name (model-name model))
        (done 0)
        (skipped 0)
        (failed 0)
        (message nil))
    (dolist (id ids (values done skipped failed message))
      (handler-case
          (if (nothing-to-do-p action (find-content space model-name id))
              (incf skipped)
              (progn (funcall function space model id)
                     (incf done)))
        (error (e) (incf failed) (unless message (setf message (failure-message e))))))))
