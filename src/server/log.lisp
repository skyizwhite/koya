(defpackage #:koya-server/log
  (:use #:cl)
  (:import-from #:org.shirakumo.verbose)
  (:export #:log-info
           #:log-warn
           #:log-error))
(in-package #:koya-server/log)

(defun log-info (category control &rest args)
  (apply #'org.shirakumo.verbose:info category control args))

(defun log-warn (category control &rest args)
  (apply #'org.shirakumo.verbose:warn category control args))

(defun log-error (category control &rest args)
  (apply #'org.shirakumo.verbose:error category control args))
