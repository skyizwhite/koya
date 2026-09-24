(defpackage #:koya-server/web/admin-api/contents/<space>/<model>/<id>/draft-key
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/web/http #:path-param)
  (:import-from #:koya-server/usecases/contents/write #:draft-key)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/contents/<space>/<model>/<id>/draft-key)

(defun @post (params)
  "Return the content's draft key for previews, generating it on first call."
  (jobject "draftKey" (draft-key (path-param params :space) (path-param params :model) (path-param params :id))))
