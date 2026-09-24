(defpackage #:koya-server/domain/totp
  (:use #:cl)
  (:import-from #:quri #:make-uri #:render-uri #:url-encode)
  (:import-from #:ironclad
                #:make-hmac #:update-hmac #:hmac-digest #:random-data)
  (:export #:base32-decode
           #:base32-encode
           #:hotp
           #:totp
           #:code-step
           #:unix-now
           #:generate-totp-secret
           #:otpauth-uri))
(in-package #:koya-server/domain/totp)

;;; Time-based one-time passwords (RFC 6238 over RFC 4226): HMAC-SHA1, 30 second
;;; steps, six digits.

(defparameter +alphabet+ "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
(defparameter +step-seconds+ 30)
(defparameter +digits+ 6)

(defun base32-decode (string)
  "Octets of a Base32 STRING (RFC 4648, case-insensitive, padding and spaces ignored)."
  (let ((bits 0) (nbits 0) (out '()))
    (loop :for c :across (string-upcase string)
          :for v := (position c +alphabet+)
          :do (cond (v (setf bits (logior (ash bits 5) v)) (incf nbits 5)
                       (when (>= nbits 8)
                         (push (ldb (byte 8 (- nbits 8)) bits) out)
                         (decf nbits 8)
                         (setf bits (ldb (byte nbits 0) bits))))
                    ((member c '(#\= #\Space #\-)) nil)
                    (t (error "not a Base32 character: ~s" c))))
    (coerce (nreverse out) '(vector (unsigned-byte 8)))))

(defun base32-encode (octets)
  (with-output-to-string (out)
    (let ((bits 0) (nbits 0))
      (loop :for b :across octets
            :do (setf bits (logior (ash bits 8) b)) (incf nbits 8)
                (loop :while (>= nbits 5)
                      :do (write-char (char +alphabet+ (ldb (byte 5 (- nbits 5)) bits)) out)
                          (decf nbits 5)
                          (setf bits (ldb (byte nbits 0) bits))))
      (when (plusp nbits)
        (write-char (char +alphabet+ (ash bits (- 5 nbits))) out)))))

(defun hotp (secret-octets counter &key (digits +digits+))
  "HOTP value of COUNTER as a zero-padded string."
  (let* ((message (make-array 8 :element-type '(unsigned-byte 8)))
         (hmac (make-hmac secret-octets :sha1)))
    (loop :for i :from 7 :downto 0 :do (setf (aref message i) (ldb (byte 8 (* 8 (- 7 i))) counter)))
    (update-hmac hmac message)
    (let* ((digest (hmac-digest hmac))
           (offset (logand (aref digest 19) #x0F))
           (binary (logior (ash (logand (aref digest offset) #x7F) 24)
                           (ash (aref digest (+ offset 1)) 16)
                           (ash (aref digest (+ offset 2)) 8)
                           (aref digest (+ offset 3)))))
      (format nil "~v,'0d" digits (mod binary (expt 10 digits))))))

(defun unix-now ()
  (- (get-universal-time) #.(encode-universal-time 0 0 0 1 1 1970 0)))

(defun totp (secret &key (time (unix-now)))
  "The current code for SECRET (a Base32 string)."
  (hotp (base32-decode secret) (floor time +step-seconds+)))

(defun code-step (code secret &key (time (unix-now)) (window 1) (after -1))
  "The time step CODE is the code of for SECRET: the current one or one within
WINDOW steps either way, and later than AFTER. NIL when there is none."
  (let ((code (remove #\Space (or code "")))
        (now (floor time +step-seconds+))
        (key (base32-decode secret)))
    (loop :for step :from (max (- now window) (1+ after)) :to (+ now window)
          :when (ironclad:constant-time-equal (babel:string-to-octets (hotp key step))
                                              (babel:string-to-octets code))
            :do (return step))))

(defun generate-totp-secret ()
  "A fresh 160-bit secret as Base32, the size RFC 4226 recommends."
  (base32-encode (random-data 20)))

(defun otpauth-uri (secret &key (issuer "koya") (account "owner"))
  "The otpauth:// URI authenticator apps import (paste it, or make a QR code from it)."
  (render-uri (make-uri :scheme "otpauth" :host "totp" :path (format nil "/~a:~a" (url-encode issuer) (url-encode account))
                        :query `(("secret" . ,secret) ("issuer" . ,issuer) ("algorithm" . "SHA1")
                                 ("digits" . ,+digits+) ("period" . ,+step-seconds+)))))
