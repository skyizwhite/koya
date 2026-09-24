(defpackage #:koya-server/usecases/media/delivery
  (:use #:cl)
  (:import-from #:koya/core/json
                #:jobject #:json-null)
  (:import-from #:koya-server/domain/image
                #:+image-types+)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-space #:media-filename #:media-mime #:media-size #:media-width
                #:media-height #:media-alt #:media-created-at #:media-file-name)
  (:import-from #:koya-server/usecases/ports/config
                #:public-url)
  (:import-from #:koya-server/usecases/ports/media
                #:media-file-path)
  (:export #:media-url
           #:media->jobject
           #:stored-file))
(in-package #:koya-server/usecases/media/delivery)

;;; A media as koya hands it out: at /media/{space}/{id}.{ext}, served by this
;;; server, and as the object the APIs and webhooks carry.

(defun media-url (media &key (absolute t))
  (let ((path (format nil "/media/~a/~a" (media-space media) (media-file-name media))))
    (if absolute
        (concatenate 'string (string-right-trim "/" (public-url)) path)
        path)))

(defun media->jobject (media)
  (jobject "id" (media-id media)
           "url" (media-url media)
           "filename" (media-filename media)
           "mime" (media-mime media)
           "size" (media-size media)
           "width" (or (media-width media) json-null)
           "height" (or (media-height media) json-null)
           "alt" (media-alt media)
           "createdAt" (media-created-at media)))

(defun stored-file (space id extension)
  "(values PATH MIME) of the file a media URL names, or NIL when there is none."
  (let ((mime (car (rassoc extension +image-types+ :test #'string=))))
    (when mime
      (let ((path (media-file-path space id mime)))
        (when (probe-file path)
          (values path mime))))))
