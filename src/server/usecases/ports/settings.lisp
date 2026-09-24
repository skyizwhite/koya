(defpackage #:koya-server/usecases/ports/settings
  (:use #:cl)
  (:export #:get-setting
           #:set-setting
           #:delete-setting))
(in-package #:koya-server/usecases/ports/settings)

;;; Instance-wide settings the owner changes from the admin UI, as strings under
;;; a key. See ports/store for what a port is.

(declaim (ftype function get-setting set-setting delete-setting))
