(defpackage #:koya-spec/server/schema
  (:use #:cl)
  (:import-from #:koya-server/usecases/schema #:replace-schema #:load-schema)
  (:export #:with-schema))
(in-package #:koya-spec/server/schema)

(defmacro with-schema ((space schema) &body body)
  (let ((before (gensym)) (name (gensym)))
    `(let* ((,name ,space)
            (,before (load-schema ,name)))
       (replace-schema ,name ,schema)
       (unwind-protect (progn ,@body)
         (replace-schema ,name ,before)))))
