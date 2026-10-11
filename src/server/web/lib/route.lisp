(defpackage #:koya-server/web/lib/route
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model #:resolve-object-model)
  (:export #:with-route-model))
(in-package #:koya-server/web/lib/route)

(defmacro with-route-model ((space model kind) params &body body)
  (let ((given (gensym "PARAMS")))
    `(let ((,given ,params))
       (multiple-value-bind (,space ,model)
           (,(ecase kind (:list 'resolve-list-model) (:object 'resolve-object-model))
            (path-param ,given :space) (path-param ,given :model))
         ,@body))))
