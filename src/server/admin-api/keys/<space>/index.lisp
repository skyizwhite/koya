(defpackage #:koya-server/admin-api/keys/<space>/index
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:path-param #:read-json-body #:body-field #:fail-api #:ok-status)
  (:import-from #:koya-server/db/schema-store #:find-space #:space-webhook-secret)
  (:import-from #:koya-server/db/api-keys #:create-api-key #:list-api-keys)
  (:export #:@get #:@post))
(in-package #:koya-server/admin-api/keys/<space>/index)

(defun require-space (params)
  (let ((name (path-param params :space)))
    (unless (find-space name) (fail-api 404 "not_found" (format nil "Space ~a does not exist" name)))
    name))

(defun key->jobject (key)
  (jobject "id" (getf key :id) "label" (getf key :label) "createdAt" (getf key :created-at)))

(defun @get (params)
  (let ((space (require-space params)))
    (jobject "keys" (map 'vector #'key->jobject (list-api-keys space))
             "webhookSecret" (space-webhook-secret space))))

(defun @post (params)
  "Create an API key. The plaintext key is only returned here."
  (let* ((space (require-space params))
         (label (or (body-field (read-json-body) "label") "")))
    (multiple-value-bind (key id) (create-api-key space :label label)
      (ok-status 201)
      (jobject "id" id "label" label "key" key))))
