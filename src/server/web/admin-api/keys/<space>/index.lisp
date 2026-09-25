(defpackage #:koya-server/web/admin-api/keys/<space>/index
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/web/http #:path-param #:read-json-body #:body-field #:ok-status)
  (:import-from #:koya-server/usecases/keys
                #:space-webhook-secret #:create-delivery-key #:list-delivery-keys)
  (:import-from #:koya-server/usecases/contents/lookup #:resolve-space)
  (:import-from #:koya-server/domain/key #:key-id #:key-label #:key-created-at)
  (:export #:@get #:@post))
(in-package #:koya-server/web/admin-api/keys/<space>/index)

(defun key->jobject (key)
  (jobject "id" (key-id key) "label" (key-label key) "createdAt" (key-created-at key)))

(defun @get (params)
  (let ((space (resolve-space (path-param params :space))))
    (jobject "keys" (map 'vector #'key->jobject (list-delivery-keys space))
             "webhookSecret" (space-webhook-secret space))))

(defun @post (params)
  "Create a delivery key. The plaintext key is only returned here."
  (let* ((space (resolve-space (path-param params :space)))
         (label (or (body-field (read-json-body) "label") "")))
    (multiple-value-bind (key id) (create-delivery-key space :label label)
      (ok-status 201)
      (jobject "id" id "label" label "key" key))))
