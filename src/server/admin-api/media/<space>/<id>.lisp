(defpackage #:koya-server/admin-api/media/<space>/<id>
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:path-param #:read-json-body #:body-field #:fail-api)
  (:import-from #:koya-server/admin-api/media/<space>/index #:require-space)
  (:import-from #:koya-server/db/media #:find-media #:update-media #:media-references)
  (:import-from #:koya-server/features/media/store #:remove-media #:media->jobject)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/admin-api/media/<space>/<id>)

(defun require-media (params)
  (let ((space (require-space params)))
    (or (find-media space (path-param params :id))
        (fail-api 404 "not_found" "Media does not exist"))))

(defun with-references (media)
  (let ((obj (media->jobject media)))
    (setf (gethash "references" obj) (media-references (koya-server/db/media:media-space media)
                                                       (koya-server/db/media:media-id media)))
    obj))

(defun @get (params)
  "The media object plus \"references\": how many contents mention it."
  (with-references (require-media params)))

(defun @patch (params)
  "Update the alt text: {\"alt\": \"...\"}."
  (let* ((media (require-media params))
         (alt (body-field (read-json-body) "alt")))
    (unless (stringp alt) (fail-api 400 "bad_request" "\"alt\" must be a string"))
    (media->jobject (update-media (koya-server/db/media:media-space media)
                                  (koya-server/db/media:media-id media) :alt alt))))

(defun @delete (params)
  "Delete the file and its row. Contents that referenced it keep a dangling id."
  (let ((media (require-media params)))
    (remove-media media)
    (jobject "deleted" t)))
