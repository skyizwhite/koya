(defpackage #:koya-server/web/admin-api/media/<space>/index
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/http
                #:path-param #:param #:fail-api #:ok-status #:uploaded-files #:form-field)
  (:import-from #:koya-server/domain/query #:parse-query #:query-limit #:query-offset)
  (:import-from #:koya-server/web/presenters #:media->jobject)
  (:import-from #:koya-server/usecases/media #:store-uploads #:list-media #:count-media)
  (:import-from #:koya-server/usecases/spaces #:resolve-space)
  (:export #:@get #:@post))
(in-package #:koya-server/web/admin-api/media/<space>/index)

(defun @get (params)
  (let* ((space (resolve-space (path-param params :space)))
         (query (parse-query params))
         (search (param params "q")))
    (jobject "media" (map 'vector #'media->jobject
                          (list-media space :search search :limit (query-limit query) :offset (query-offset query)))
             "totalCount" (count-media space :search search)
             "offset" (query-offset query) "limit" (query-limit query))))

(defun @post (params)
  (let* ((space (resolve-space (path-param params :space)))
         (files (uploaded-files params "file"))
         (alt (or (form-field params "alt") "")))
    (when (null files) (fail-api 400 "bad_request" "Send the image as a multipart field named \"file\""))
    (let ((stored (store-uploads space files :alt alt)))
      (ok-status 201)
      (jobject "media" (map 'vector #'media->jobject stored)))))
