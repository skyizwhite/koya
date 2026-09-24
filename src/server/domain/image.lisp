(defpackage #:koya-server/domain/image
  (:use #:cl)
  (:export #:sniff-image
           #:image-extension
           #:+image-types+))
(in-package #:koya-server/domain/image)

;;; Recognise the image formats the media library accepts by their leading
;;; bytes and read the pixel size from the header. Nothing else is decoded.
;;; The client-supplied Content-Type is never consulted.

(defparameter +image-types+
  '(("image/png" . "png") ("image/jpeg" . "jpg") ("image/gif" . "gif") ("image/webp" . "webp")))

(defun image-extension (mime)
  (cdr (assoc mime +image-types+ :test #'string=)))

(defun u16be (v i) (logior (ash (aref v i) 8) (aref v (1+ i))))
(defun u16le (v i) (logior (aref v i) (ash (aref v (1+ i)) 8)))
(defun u32be (v i) (logior (ash (u16be v i) 16) (u16be v (+ i 2))))
(defun u24le (v i) (logior (u16le v i) (ash (aref v (+ i 2)) 16)))

(defun prefix-p (bytes i &rest expected)
  (and (<= (+ i (length expected)) (length bytes))
       (loop :for e :in expected :for k :from i
             :always (or (null e) (= (aref bytes k) e)))))

(defun png-size (bytes)
  ;; signature, then the IHDR chunk: length(4) "IHDR" width(4) height(4)
  (when (and (>= (length bytes) 24) (prefix-p bytes 12 #x49 #x48 #x44 #x52))
    (values (u32be bytes 16) (u32be bytes 20))))

(defun gif-size (bytes)
  (when (>= (length bytes) 10)
    (values (u16le bytes 6) (u16le bytes 8))))

(defun jpeg-size (bytes)
  ;; walk the marker segments to the first SOF (start of frame)
  (let ((i 2) (n (length bytes)))
    (loop
      (when (> (+ i 9) n) (return nil))
      (unless (= (aref bytes i) #xFF) (return nil))
      (let ((marker (aref bytes (1+ i))))
        (cond ((= marker #xFF) (incf i))
              ((or (<= #xC0 marker #xC3) (<= #xC5 marker #xC7) (<= #xC9 marker #xCB) (<= #xCD marker #xCF))
               (return (values (u16be bytes (+ i 7)) (u16be bytes (+ i 5)))))
              ((or (= marker #xD8) (<= #xD0 marker #xD7) (= marker #x01)) (incf i 2))
              (t (incf i (+ 2 (u16be bytes (+ i 2))))))))))

(defun webp-size (bytes)
  ;; RIFF....WEBP then a VP8 / VP8L / VP8X chunk
  (when (and (>= (length bytes) 30) (prefix-p bytes 8 #x57 #x45 #x42 #x50))
    (cond ((prefix-p bytes 12 #x56 #x50 #x38 #x20)          ; "VP8 " lossy
           (values (logand (u16le bytes 26) #x3FFF) (logand (u16le bytes 28) #x3FFF)))
          ((prefix-p bytes 12 #x56 #x50 #x38 #x4C)          ; "VP8L" lossless
           (let ((b (u32be (reverse (subseq bytes 21 25)) 0)))
             (values (1+ (logand b #x3FFF)) (1+ (logand (ash b -14) #x3FFF)))))
          ((prefix-p bytes 12 #x56 #x50 #x38 #x58)          ; "VP8X" extended
           (values (1+ (u24le bytes 24)) (1+ (u24le bytes 27)))))))

(defun sniff-image (bytes)
  "For an accepted image: (values mime width height). Otherwise NIL. WIDTH and
HEIGHT are NIL when the header is truncated."
  (let ((bytes (coerce bytes '(simple-array (unsigned-byte 8) (*)))))
    (cond ((prefix-p bytes 0 #x89 #x50 #x4E #x47 #x0D #x0A #x1A #x0A)
           (multiple-value-bind (w h) (png-size bytes) (values "image/png" w h)))
          ((prefix-p bytes 0 #xFF #xD8 #xFF)
           (multiple-value-bind (w h) (jpeg-size bytes) (values "image/jpeg" w h)))
          ((or (prefix-p bytes 0 #x47 #x49 #x46 #x38 #x39 #x61) (prefix-p bytes 0 #x47 #x49 #x46 #x38 #x37 #x61))
           (multiple-value-bind (w h) (gif-size bytes) (values "image/gif" w h)))
          ((and (prefix-p bytes 0 #x52 #x49 #x46 #x46) (prefix-p bytes 8 #x57 #x45 #x42 #x50))
           (multiple-value-bind (w h) (webp-size bytes) (values "image/webp" w h)))
          (t nil))))
