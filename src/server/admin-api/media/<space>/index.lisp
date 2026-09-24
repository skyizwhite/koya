(defpackage #:koya-server/admin-api/media/<space>/index
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http
                #:path-param #:param #:fail-api #:ok-status #:uploaded-files #:form-field)
  (:import-from #:koya-server/domain/query #:parse-query #:query-limit #:query-offset)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:find-space)
  (:import-from #:koya-server/usecases/media/delivery #:media->jobject)
  (:import-from #:koya-server/usecases/media/library #:store-upload #:list-media #:count-media)
  (:export #:@get #:@post #:require-space))
(in-package #:koya-server/admin-api/media/<space>/index)

(defun require-space (params)
  (let ((name (path-param params :space)))
    (unless (find-space name) (fail-api 404 "not_found" (format nil "Space ~a does not exist" name)))
    name))

(defun @get (params)
  "List media, newest first: ?q= filters by file name, limit/offset page."
  (let* ((space (require-space params))
         (query (parse-query params))
         (search (param params "q")))
    (jobject "media" (map 'vector #'media->jobject
                          (list-media space :search search :limit (query-limit query) :offset (query-offset query)))
             "totalCount" (count-media space :search search)
             "offset" (query-offset query) "limit" (query-limit query))))

(defun @post (params)
  "Upload one or more images (multipart/form-data, field \"file\"; optional \"alt\"). Returns {\"media\": [...]}."
  (let* ((space (require-space params))
         (files (uploaded-files params "file"))
         (alt (or (form-field params "alt") "")))
    (when (null files) (fail-api 400 "bad_request" "Send the image as a multipart field named \"file\""))
    (let ((stored (loop :for (bytes filename) :in files
                        :collect (store-upload space bytes :filename filename :alt alt))))
      (ok-status 201)
      (jobject "media" (map 'vector #'media->jobject stored)))))
