(defpackage #:koya-server/web/lib/target
  (:use #:cl)
  (:import-from #:koya-core/schema #:model-name)
  (:import-from #:koya-server/usecases/spaces #:find-space)
  (:import-from #:koya-server/usecases/contents #:find-content)
  (:import-from #:koya-server/web/lib/http #:param)
  (:import-from #:koya-server/usecases/schema #:find-model)
  (:export #:target-model
           #:target-content))
(in-package #:koya-server/web/lib/target)

(defun target-model (params)
  (let ((space (param params "space")))
    (and space (find-space space) (find-model space (or (param params "model") "")))))

(defun target-content (params model)
  (find-content (param params "space") (model-name model) (or (param params "id") "")))
