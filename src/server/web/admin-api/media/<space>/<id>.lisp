(defpackage #:koya-server/web/admin-api/media/<space>/<id>
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/web/http #:path-param #:read-json-body #:body-field #:fail-api)
  (:import-from #:koya-server/usecases/contents/lookup #:resolve-space)
  (:import-from #:koya-server/web/presenters #:media->jobject)
  (:import-from #:koya-server/usecases/media/library
                #:remove-media #:find-media #:update-media #:media-references)
  (:import-from #:koya-server/domain/media #:media-space #:media-id)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/web/admin-api/media/<space>/<id>)

(defun require-media (params)
  (let ((space (resolve-space (path-param params :space))))
    (or (find-media space (path-param params :id))
        (fail-api 404 "not_found" "Media does not exist"))))

(defun with-references (media)
  (let ((obj (media->jobject media)))
    (setf (gethash "references" obj) (media-references (media-space media)
                                                       (media-id media)))
    obj))

(defun @get (params)
  "The media object plus \"references\": how many contents mention it."
  (with-references (require-media params)))

(defun @patch (params)
  "Update the alt text: {\"alt\": \"...\"}."
  (let* ((media (require-media params))
         (alt (body-field (read-json-body) "alt")))
    (unless (stringp alt) (fail-api 400 "bad_request" "\"alt\" must be a string"))
    (media->jobject (update-media (media-space media)
                                  (media-id media) :alt alt))))

(defun @delete (params)
  "Delete the file and its row. Contents that referenced it keep a dangling id."
  (let ((media (require-media params)))
    (remove-media media)
    (jobject "deleted" t)))
