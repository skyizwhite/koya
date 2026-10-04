(defpackage #:koya-spec/server/domain/image
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/image #:strip-metadata #:sniff-image)
  (:import-from #:ironclad #:digest-sequence)
  (:export #:jpeg #:octets))
(in-package #:koya-spec/server/domain/image)

(defun octets (&rest parts)
  (let ((out (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (labels ((put (part)
               (etypecase part
                 (integer (vector-push-extend part out))
                 (string (loop :for c :across part :do (vector-push-extend (char-code c) out)))
                 (sequence (map nil #'put part)))))
      (map nil #'put parts))
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defun be16 (n) (list (ldb (byte 8 8) n) (ldb (byte 8 0) n)))
(defun be32 (n) (list (ldb (byte 8 24) n) (ldb (byte 8 16) n) (ldb (byte 8 8) n) (ldb (byte 8 0) n)))
(defun le16 (n) (reverse (be16 n)))
(defun le32 (n) (reverse (be32 n)))

(defun contains (bytes text) (search (octets text) bytes))

(defun tiff-be (orientation)
  (octets "MM" 0 42 (be32 8) (be16 3)
          (be16 #x010F) (be16 2) (be32 4) "Fuj" 0
          (be16 #x0112) (be16 3) (be32 1) (be16 orientation) 0 0
          (be16 #x8825) (be16 4) (be32 1) (be32 50)
          (be32 0)
          "GPS-35.6N"))

(defun tiff-le (orientation)
  (octets "II" 42 0 (le32 8) (le16 2)
          (le16 #x010F) (le16 2) (le32 4) "Fuj" 0
          (le16 #x0112) (le16 3) (le32 1) (le16 orientation) 0 0
          (le32 0)
          "GPS-35.6N"))

(defun minimal-tiff (orientation)
  (octets "MM" 0 42 (be32 8) (be16 1) (be16 #x0112) (be16 3) (be32 1) (be16 orientation) 0 0 (be32 0)))

(defun segment (marker &rest payload)
  (let ((body (apply #'octets payload)))
    (octets #xFF marker (be16 (+ 2 (length body))) body)))

(defun jpeg (&key (exif (tiff-be 6)) trailing)
  (octets #xFF #xD8
          (segment #xE0 "JFIF" 0 1 1 0 0 1 0 1 0 0)
          (when exif (segment #xE1 "Exif" 0 0 exif))
          (segment #xE1 "http://ns.adobe.com/xap/1.0/" 0 "<x:xmpmeta>GPS-35.6N</x:xmpmeta>")
          (segment #xE2 "ICC_PROFILE" 0 1 1 "icc-data")
          (segment #xE2 "MPF" 0 "MM" 0 42 "mpf-index")
          (segment #xED "Photoshop 3.0" 0 "iptc-city")
          (segment #xFE "a comment")
          (segment #xDB 0 (make-list 64 :initial-element 1))
          (segment #xC0 8 (be16 256) (be16 128) 1 1 #x11 0)
          (segment #xDA 1 1 0 0 63 0)
          1 2 #xFF 0 3 #xFF #xD0 4 5
          #xFF #xD9
          trailing))

(defun chunk (type data)
  (let ((body (octets type data)))
    (octets (be32 (length data)) body (be32 (crc32 body)))))

(defun crc32 (bytes)
  (reduce (lambda (acc b) (+ (ash acc 8) b)) (digest-sequence :crc32 bytes) :initial-value 0))

(defun png (&key (exif (tiff-be 8)))
  (octets #x89 "PNG" #x0D #x0A #x1A #x0A
          (chunk "IHDR" (octets (be32 640) (be32 480) 8 6 0 0 0))
          (chunk "iCCP" (octets "sRGB" 0 0 "icc-data"))
          (chunk "tEXt" (octets "Comment" 0 "GPS-35.6N"))
          (chunk "zTXt" (octets "Raw" 0 0 "zipped"))
          (chunk "iTXt" (octets "XML:com.adobe.xmp" 0 0 0 0 0 "GPS-35.6N"))
          (chunk "tIME" (octets (be16 2026) 10 4 9 0 0))
          (when exif (chunk "eXIf" exif))
          (chunk "IDAT" (octets "pixels"))
          (chunk "IEND" (octets))))

(defun riff-chunk (type data)
  (octets type (le32 (length data)) data (when (oddp (length data)) 0)))

(defun webp (&key (exif (tiff-be 3)) (flags #x2C))
  (let ((body (octets "WEBP"
                      (riff-chunk "VP8X" (octets flags 0 0 0 (le16 319) 0 (le16 239) 0))
                      (riff-chunk "ICCP" (octets "icc-data"))
                      (riff-chunk "VP8 " (octets 0 0 0 #x9D 1 #x2A (le16 320) (le16 240) "frame"))
                      (when exif (riff-chunk "EXIF" exif))
                      (riff-chunk "XMP " (octets "<x:xmpmeta>GPS-35.6N</x:xmpmeta>!")))))
    (octets "RIFF" (le32 (length body)) body)))

(deftest jpeg-metadata
  (let ((out (strip-metadata (jpeg :trailing (octets #xFF #xD8 (segment #xE1 "Exif" 0 0 (tiff-be 1)) #xFF #xD9))
                             "image/jpeg")))
    (ng (contains out "GPS") "the position is gone, from the image and from what follows it")
    (ng (contains out "Fuj") "and every other tag")
    (ng (contains out "iptc-city"))
    (ng (contains out "a comment"))
    (ng (contains out "mpf-index") "the index of pictures no longer there")
    (ok (contains out "JFIF"))
    (ok (contains out "icc-data") "the colour profile stays")
    (ok (search (segment #xE1 "Exif" 0 0 (minimal-tiff 6)) out) "the orientation stays, alone")
    (ok (search (octets 1 2 #xFF 0 3 #xFF #xD0 4 5 #xFF #xD9) out) "the picture is copied as it was")
    (ok (= (aref out (- (length out) 1)) #xD9) "and ends where it does")
    (multiple-value-bind (mime w h) (sniff-image out)
      (ok (string= mime "image/jpeg")) (ok (= w 128)) (ok (= h 256))))
  (testing "a little-endian orientation is read as well"
    (ok (search (segment #xE1 "Exif" 0 0 (minimal-tiff 8)) (strip-metadata (jpeg :exif (tiff-le 8)) "image/jpeg"))))
  (testing "an upright picture keeps no EXIF at all"
    (ng (contains (strip-metadata (jpeg :exif (tiff-be 1)) "image/jpeg") "Exif"))
    (ng (contains (strip-metadata (jpeg :exif nil) "image/jpeg") "Exif"))))

(deftest png-metadata
  (let ((out (strip-metadata (png) "image/png")))
    (ng (contains out "GPS"))
    (ng (contains out "Fuj"))
    (ng (contains out "zipped"))
    (ng (contains out "tIME"))
    (ok (contains out "icc-data"))
    (ok (search (chunk "eXIf" (minimal-tiff 8)) out) "the orientation stays, alone, with its checksum")
    (ok (search (chunk "IDAT" (octets "pixels")) out))
    (ok (search (chunk "IEND" (octets)) out))
    (multiple-value-bind (mime w h) (sniff-image out)
      (ok (string= mime "image/png")) (ok (= w 640)) (ok (= h 480))))
  (testing "an upright picture keeps no eXIf"
    (ng (contains (strip-metadata (png :exif (tiff-be 1)) "image/png") "eXIf"))
    (ng (contains (strip-metadata (png :exif nil) "image/png") "eXIf"))))

(deftest webp-metadata
  (let ((out (strip-metadata (webp) "image/webp")))
    (ng (contains out "GPS"))
    (ng (contains out "Fuj"))
    (ng (contains out "XMP "))
    (ok (contains out "icc-data"))
    (ok (contains out "frame"))
    (ok (search (riff-chunk "EXIF" (minimal-tiff 3)) out) "the orientation stays, alone")
    (ok (= (aref out 20) #x28) "the flags say there is EXIF and no XMP")
    (ok (= (+ 8 (logior (aref out 4) (ash (aref out 5) 8) (ash (aref out 6) 16) (ash (aref out 7) 24)))
           (length out))
        "the RIFF size is the new one")
    (multiple-value-bind (mime w h) (sniff-image out)
      (ok (string= mime "image/webp")) (ok (= w 320)) (ok (= h 240))))
  (testing "an upright picture keeps no EXIF, and its flag goes"
    (let ((out (strip-metadata (webp :exif (tiff-be 1)) "image/webp")))
      (ng (contains out "EXIF"))
      (ok (= (aref out 20) #x20))))
  (testing "a simple WebP has nothing to strip"
    (let ((simple (octets "RIFF" (le32 22) "WEBP" (riff-chunk "VP8 " (octets 0 0 0 #x9D 1 #x2A (le16 320) (le16 240))))))
      (ok (equalp (strip-metadata simple "image/webp") simple)))))

(deftest what-is-not-stripped
  (let ((gif (octets "GIF89a" (le16 16) (le16 8) 0 0 0 "rest")))
    (ok (equalp (strip-metadata gif "image/gif") gif) "a GIF is kept as it is"))
  (testing "a file cut short is kept as far as it goes"
    (let ((cut (subseq (png) 0 40)))
      (ok (equalp (strip-metadata cut "image/png") cut)))
    (let ((cut (octets #xFF #xD8 #xFF #xC0 0 #x11 8 1 0 0 #x80 3 0 0 0 0 0 0 0 0)))
      (ok (equalp (strip-metadata cut "image/jpeg") cut)))))
