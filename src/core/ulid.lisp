(defpackage #:koya/core/ulid
  (:use #:cl)
  (:import-from #:ironclad
                #:random-data)
  (:import-from #:local-time
                #:now
                #:timestamp-to-unix
                #:timestamp-millisecond)
  (:export #:make-ulid
           #:ulid-p
           #:ulid-timestamp))
(in-package #:koya/core/ulid)

;;; ULID: 48-bit millisecond timestamp + 80-bit randomness, encoded as 26
;;; Crockford base32 characters. Lexicographically sortable by creation time.

(defparameter +alphabet+ "0123456789ABCDEFGHJKMNPQRSTVWXYZ")
(defparameter +length+ 26)

(defun unix-milliseconds ()
  (let ((ts (now)))
    (+ (* 1000 (timestamp-to-unix ts))
       (timestamp-millisecond ts))))

(defun random-80-bits ()
  (let ((bytes (random-data 10))
        (n 0))
    (loop :for b :across bytes
          :do (setf n (logior (ash n 8) b)))
    n))

(defun encode (integer)
  (let ((chars (make-string +length+)))
    (loop :for i :from (1- +length+) :downto 0
          :do (setf (char chars i) (char +alphabet+ (logand integer #x1f)))
              (setf integer (ash integer -5)))
    chars))

(defun make-ulid (&optional (time-ms (unix-milliseconds)))
  "Return a fresh ULID string. TIME-MS defaults to the current unix time in milliseconds."
  (check-type time-ms (integer 0 #.(1- (expt 2 48))))
  (encode (logior (ash time-ms 80) (random-80-bits))))

(defun ulid-p (string)
  "True when STRING is a syntactically valid ULID."
  (and (stringp string)
       (= (length string) +length+)
       ;; 128 bits in 130 bit slots: the first character can only use 3 bits.
       (char<= (char-upcase (char string 0)) #\7)
       (every (lambda (c) (position (char-upcase c) +alphabet+)) string)))

(defun ulid-timestamp (ulid)
  "Return the unix millisecond timestamp embedded in ULID."
  (let ((n 0))
    (loop :for c :across (subseq ulid 0 10)
          :do (setf n (logior (ash n 5) (position (char-upcase c) +alphabet+))))
    n))
