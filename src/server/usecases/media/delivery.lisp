(defpackage #:koya-server/usecases/media/delivery
  (:use #:cl)
  (:import-from #:koya-server/domain/image
                #:+image-types+)
  (:import-from #:koya-server/usecases/ports/media
                #:media-file-path)
  (:export #:stored-file))
(in-package #:koya-server/usecases/media/delivery)

;;; A media is served by this server at /media/{space}/{id}.{ext} (web/presenters
;;; makes the URL, web/media serves it).

(defun stored-file (space id extension)
  "(values PATH MIME) of the file a media URL names, or NIL when there is none."
  (let ((mime (car (rassoc extension +image-types+ :test #'string=))))
    (when mime
      (let ((path (media-file-path space id mime)))
        (when (probe-file path)
          (values path mime))))))
