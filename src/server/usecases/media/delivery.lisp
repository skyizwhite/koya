(defpackage #:koya-server/usecases/media/delivery
  (:use #:cl)
  (:import-from #:koya-server/domain/image
                #:+image-types+)
  (:import-from #:koya-server/usecases/ports/media
                #:media-file-path #:media-file-exists-p)
  (:export #:stored-file))
(in-package #:koya-server/usecases/media/delivery)

;;; A media is served by this server at /media/{space}/{id}.{ext} (web/presenters
;;; makes the URL, web/media serves it).

(defun stored-file (space id extension)
  "(values PATH MIME) of the file a media URL names, or NIL when there is none."
  (let ((mime (car (rassoc extension +image-types+ :test #'string=))))
    (when (and mime (media-file-exists-p space id mime))
      (values (media-file-path space id mime) mime))))
