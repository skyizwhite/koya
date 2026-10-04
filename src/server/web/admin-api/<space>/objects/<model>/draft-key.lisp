(defpackage #:koya-server/web/admin-api/<space>/objects/<model>/draft-key
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/contents #:draft-key #:object-content)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-core/schema #:model-name)
  (:import-from #:koya-server/usecases/schema #:resolve-object-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/<space>/objects/<model>/draft-key)

(defun @post (params)
  (multiple-value-bind (space model) (resolve-object-model (path-param params :space) (path-param params :model))
    (jobject "draftKey" (draft-key space (model-name model) (content-id (object-content space model))))))
