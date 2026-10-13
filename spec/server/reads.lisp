(defpackage #:koya-spec/server/reads
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/contents #:find-content #:find-contents-by-ids #:list-contents)
  (:import-from #:koya-server/usecases/ports/contents #:space-contents #:contents-mentioning)
  (:import-from #:koya-server/usecases/ports/media #:find-media #:find-media-by-ids)
  (:import-from #:koya-server/usecases/ports/spaces #:load-schema)
  (:export #:reads-of))
(in-package #:koya-spec/server/reads)

(defvar *reads* nil)

(defun note (read)
  (when (and *reads* (member (if (consp read) (first read) read) (car *reads*)))
    (push read (cdr *reads*))))

(defmethod find-content :around (space model id)
  (declare (ignore space model id))
  (note :find-content)
  (call-next-method))

(defmethod find-media :around (space id)
  (declare (ignore space id))
  (note :find-media)
  (call-next-method))

(defmethod find-contents-by-ids :around (space model ids)
  (declare (ignore space ids))
  (note (list :find-contents-by-ids model))
  (call-next-method))

(defmethod find-media-by-ids :around (space ids)
  (declare (ignore space ids))
  (note :find-media-by-ids)
  (call-next-method))

(defmethod list-contents :around (space model schema-model query &key status only-status)
  (declare (ignore space schema-model query status only-status))
  (note (list :list-contents model))
  (call-next-method))

(defmethod load-schema :around (space-name)
  (declare (ignore space-name))
  (note :load-schema)
  (call-next-method))

(defmethod space-contents :around (space)
  (declare (ignore space))
  (note :space-contents)
  (call-next-method))

(defmethod contents-mentioning :around (space needle &key exclude-id)
  (declare (ignore space needle exclude-id))
  (note :contents-mentioning)
  (call-next-method))

(defun reads-of (thunk &key (of '(:find-content :find-media :find-contents-by-ids :find-media-by-ids)))
  (let ((*reads* (cons of '())))
    (funcall thunk)
    (sort (mapcar #'princ-to-string (cdr *reads*)) #'string<)))
