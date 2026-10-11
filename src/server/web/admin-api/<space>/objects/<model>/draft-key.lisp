(defpackage #:koya-server/web/admin-api/<space>/objects/<model>/draft-key
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/usecases/contents #:draft-key #:object-content)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/<space>/objects/<model>/draft-key)

(defun @post (params)
  (with-route-model (space model :object) params
    (jobject "draftKey" (draft-key space model (content-id (object-content space model))))))
