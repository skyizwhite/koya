(defpackage #:koya-server/domain/number
  (:use #:cl)
  (:import-from #:cl-ppcre
                #:scan-to-strings)
  (:export #:parse-decimal))
(in-package #:koya-server/domain/number)

(defun decimal-value (sign whole fraction exponent)
  (let* ((exponent (if exponent (parse-integer exponent) 0))
         (mantissa (parse-integer (concatenate 'string whole (or fraction ""))))
         (magnitude (* mantissa (expt 10 (- exponent (length fraction))))))
    (when (<= magnitude most-positive-double-float)
      (let ((value (coerce magnitude 'double-float)))
        (if (string= sign "-") (- value) value)))))

(defun parse-decimal (string)
  (multiple-value-bind (match groups)
      (and (stringp string)
           (<= (length string) 64)
           (scan-to-strings "^(-?)([0-9]*)(?:\\.([0-9]+))?(?:[eE]([+-]?[0-9]{1,3}))?$" string))
    (when match
      (destructuring-bind (sign whole fraction exponent) (coerce groups 'list)
        (cond ((and (string= whole "") (null fraction)) nil)
              ((or fraction exponent) (decimal-value sign whole fraction exponent))
              (t (let ((n (parse-integer whole)))
                   (let ((n (if (string= sign "-") (- n) n)))
                     (and (typep n '(signed-byte 64)) n)))))))))
