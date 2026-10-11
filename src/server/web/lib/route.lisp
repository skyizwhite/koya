(defpackage #:koya-server/web/lib/route
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model #:resolve-object-model)
  (:export #:with-route-model))
(in-package #:koya-server/web/lib/route)

(defmacro with-route-model ((space model kind) params &body body)
  `(multiple-value-bind (,space ,model)
       (,(ecase kind (:list 'resolve-list-model) (:object 'resolve-object-model))
        (path-param ,params :space) (path-param ,params :model))
     (declare (ignorable ,space ,model))
     ,@body))
