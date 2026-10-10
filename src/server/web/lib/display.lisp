(defpackage #:koya-server/web/lib/display
  (:use #:cl)
  (:import-from #:koya-core/json #:blank-p)
  (:import-from #:koya-server/domain/timezone #:format-local)
  (:import-from #:koya-server/usecases/settings #:display-timezone)
  (:import-from #:koya-server/usecases/actor #:actor-key-label)
  (:export #:short-time
           #:caller-name))
(in-package #:koya-server/web/lib/display)

(defun short-time (iso)
  (format-local iso :timezone (display-timezone)))

(defun caller-name (by)
  (let ((by (or by "")))
    (multiple-value-bind (label keyp) (actor-key-label by)
      (cond ((not keyp) by)
            ((blank-p label) "(management key)")
            (t (format nil "(management key: ~a)" label))))))
