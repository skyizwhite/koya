(defpackage #:koya-server/web/target
  (:use #:cl)
  (:import-from #:koya-core/schema #:model-name)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:find-space #:find-model)
  (:import-from #:koya-server/usecases/contents/lookup #:find-content)
  (:import-from #:koya-server/web/http #:param)
  (:export #:target-model
           #:target-content))
(in-package #:koya-server/web/target)

;;; What an action is about. A page's URL names its space, model and content
;;; (ningle-fbr); an action's form carries them as the parameters space, model
;;; and id, and an action that is handed nothing it can find refuses with 404.

(defun target-model (params)
  "The model PARAMS name, in a space that exists, or NIL."
  (let ((space (param params "space")))
    (and space (find-space space) (find-model space (or (param params "model") "")))))

(defun target-content (params model)
  "The content of MODEL that PARAMS name, or NIL."
  (find-content (param params "space") (model-name model) (or (param params "id") "")))
