(defpackage #:koya-server/domain/key
  (:use #:cl)
  (:import-from #:ironclad
                #:random-data #:byte-array-to-hex-string #:digest-sequence)
  (:import-from #:babel
                #:string-to-octets)
  (:export #:key #:make-key
           #:key-id #:key-hash #:key-label #:key-created-at
           #:new-delivery-key
           #:new-management-key
           #:hash-key
           #:new-webhook-secret))
(in-package #:koya-server/domain/key)

(defstruct key
  id hash label created-at)

(defun new-delivery-key () (format nil "koya_~a" (byte-array-to-hex-string (random-data 24))))
(defun new-management-key () (format nil "koya_mgmt_~a" (byte-array-to-hex-string (random-data 24))))

(defun hash-key (key)
  (byte-array-to-hex-string (digest-sequence :sha256 (string-to-octets key :encoding :utf-8))))

(defun new-webhook-secret ()
  (byte-array-to-hex-string (random-data 24)))
