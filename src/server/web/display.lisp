(defpackage #:koya-server/web/display
  (:use #:cl)
  (:import-from #:koya-server/domain/timezone #:format-local)
  (:import-from #:koya-server/usecases/settings/timezone #:display-timezone)
  (:import-from #:koya-server/usecases/actor #:actor-key-label)
  (:export #:short-time
           #:caller-name))
(in-package #:koya-server/web/display)

;;; What a stored value reads as on a page.

(defun short-time (iso)
  "2026-09-20T05:04:03.123Z -> 2026-09-20 14:04 JST, in the zone chosen on the settings page."
  (format-local iso :timezone (display-timezone)))

(defun caller-name (by)
  "An actor as stored, in words. Kept out of the rows so that rewording it
reaches the rows already written."
  (let ((by (or by "")))
    (multiple-value-bind (label keyp) (actor-key-label by)
      (cond ((not keyp) by)
            ((string= label "") "(management key)")
            (t (format nil "(management key: ~a)" label))))))
