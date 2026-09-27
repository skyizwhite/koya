(defpackage #:koya-server/domain/address
  (:use #:cl)
  (:export #:address-reach
           #:addresses-reach
           #:address-string))
(in-package #:koya-server/domain/address)

(defparameter +v4-ranges+
  '((:forbidden (0 0 0 0) 8)
    (:forbidden (169 254 0 0) 16)
    (:forbidden (224 0 0 0) 4)
    (:forbidden (240 0 0 0) 4)
    (:forbidden (100 100 100 200) 32)
    (:forbidden (168 63 129 16) 32)
    (:internal (127 0 0 0) 8)
    (:internal (10 0 0 0) 8)
    (:internal (172 16 0 0) 12)
    (:internal (192 168 0 0) 16)
    (:internal (100 64 0 0) 10)))

(defparameter +v6-ranges+
  '((:forbidden (0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0) 128)
    (:forbidden (#xfe #x80 0 0 0 0 0 0 0 0 0 0 0 0 0 0) 10)
    (:forbidden (#xff 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0) 8)
    (:forbidden (#xfd 0 #x0e #xc2 0 0 0 0 0 0 0 0 0 0 #x02 #x54) 128)
    (:internal (0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1) 128)
    (:internal (#xfc 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0) 7)))

(defun octets->integer (octets)
  (reduce (lambda (n octet) (+ (ash n 8) octet)) octets :initial-value 0))

(defun in-range-p (address network length)
  (let ((shift (- length (* 8 (length address)))))
    (= (ash (octets->integer address) shift) (ash (octets->integer network) shift))))

(defparameter +v4-carriers+
  '(((0 0 0 0 0 0 0 0 0 0 #xff #xff) 12)
    ((0 #x64 #xff #x9b 0 0 0 0 0 0 0 0) 12)
    ((0 #x64 #xff #x9b 0 1) 12)
    ((#x20 #x02) 2)))

(defun carried-v4 (address)
  (and (= (length address) 16)
       (loop :for (prefix at) :in +v4-carriers+
             :when (every #'= prefix address)
               :return (subseq address at (+ at 4)))))

(defun address-reach (address)
  (let* ((address (or (carried-v4 address) address))
         (ranges (if (= (length address) 4) +v4-ranges+ +v6-ranges+)))
    (or (loop :for (reach network length) :in ranges
              :when (in-range-p address network length) :return reach)
        :public)))

(defun addresses-reach (addresses)
  (let ((reaches (mapcar #'address-reach addresses)))
    (cond ((null reaches) nil)
          ((member :forbidden reaches) :forbidden)
          ((member :internal reaches) :internal)
          (t :public))))

(defun address-string (address)
  (if (= (length address) 4)
      (format nil "~{~a~^.~}" (coerce address 'list))
      (format nil "~{~(~x~)~^:~}"
              (loop :for i :from 0 :below 16 :by 2
                    :collect (+ (ash (aref address i) 8) (aref address (1+ i)))))))
