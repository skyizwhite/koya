(defpackage #:koya-server/admin-api/contents/<space>/<model>/<id>/draft-key
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/content-service #:resolve-model #:resolve-content)
  (:import-from #:koya-server/db/contents #:ensure-draft-key)
  (:export #:@post))
(in-package #:koya-server/admin-api/contents/<space>/<model>/<id>/draft-key)

(defun @post (params)
  "Return the content's draft key for previews, generating it on first call."
  (resolve-model (path-param params :space) (path-param params :model))
  (resolve-content (path-param params :space) (path-param params :model) (path-param params :id))
  (jobject "draftKey" (ensure-draft-key (path-param params :id))))
