(defpackage #:koya-spec/server/infra/webhook-sender
  (:use #:cl #:rove)
  (:import-from #:koya-server/infra/webhook-sender)
  (:import-from #:koya-server/usecases/ports/webhooks #:send-webhook)
  (:import-from #:koya-spec/server/fake-webhooks #:*webhook-sender*)
  (:import-from #:usocket
                #:socket-listen #:socket-accept #:socket-stream #:socket-close #:get-local-port)
  (:import-from #:bordeaux-threads-2 #:make-thread #:join-thread))
(in-package #:koya-spec/server/infra/webhook-sender)

;;; The real sender, against a receiver on this machine that answers one call
;;; and gives back the request's lines.

(defun crlf (stream control &rest args)
  (apply #'format stream control args)
  (write-char #\Return stream) (write-char #\Newline stream))

(defun receive-once (host &key (status "200 OK") location)
  (let* ((listener (socket-listen host 0 :reuse-address t :element-type 'character))
         (port (get-local-port listener)))
    (values port
            (make-thread
             (lambda ()
               (unwind-protect
                    (let* ((connection (socket-accept listener))
                           (stream (socket-stream connection))
                           (lines (loop :for line := (string-right-trim '(#\Return) (read-line stream nil ""))
                                        :until (string= line "")
                                        :collect line)))
                      (crlf stream "HTTP/1.1 ~a" status)
                      (when location (crlf stream "Location: ~a" location))
                      (crlf stream "Content-Type: text/plain")
                      (crlf stream "Content-Length: 2")
                      (crlf stream "Connection: close")
                      (crlf stream "")
                      (write-string "ok" stream)
                      (force-output stream)
                      (socket-close connection)
                      lines)
                 (socket-close listener)))))))

(defun header (lines name)
  (let ((line (find-if (lambda (l) (and (> (length l) (length name))
                                        (string-equal name l :end2 (length name))
                                        (char= (char l (length name)) #\:)))
                       lines)))
    (and line (string-trim " " (subseq line (1+ (length name)))))))

(deftest plain-http-connects-to-the-checked-address
  (let ((*webhook-sender* nil))
    (dolist (case '(("127.0.0.1" #(127 0 0 1))
                    ("::1" #(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1))))
      (destructuring-bind (host address) case
        (multiple-value-bind (port receiver) (receive-once host)
          (let ((url (format nil "http://receiver.invalid:~a/hook?x=1" port)))
            (multiple-value-bind (status body failure) (send-webhook url "{}" '(("X-KOYA-WEBHOOK-KEY" . "k")) address)
              (let ((lines (join-thread receiver)))
                (ok (null failure) host)
                (ok (eql status 200))
                (ok (equal body "ok"))
                (ok (string= (first lines) "POST /hook?x=1 HTTP/1.1") "the path and query are the URL's")
                (ok (string= (header lines "Host") (format nil "receiver.invalid:~a" port))
                    "the name the URL gives, never looked up")
                (ok (string= (header lines "X-KOYA-WEBHOOK-KEY") "k"))))))))))

(deftest a-redirect-is-the-answer
  (let ((*webhook-sender* nil))
    (flet ((answer (status &optional location)
             (multiple-value-bind (port receiver) (receive-once "127.0.0.1" :status status :location location)
               (multiple-value-prog1
                   (send-webhook (format nil "http://receiver.invalid:~a/hooks/v1?x=1" port) "{}" '() #(127 0 0 1))
                 (join-thread receiver)))))
      (multiple-value-bind (status body failure location) (answer "302 Found" "https://www.example.com/hook")
        (declare (ignore body))
        (ok (eql status 302) "not followed")
        (ok (null failure) "it is an answer, not a failure to send")
        (ok (equal location "https://www.example.com/hook") "and where it pointed is handed back"))
      (multiple-value-bind (status body failure location) (answer "308 Permanent Redirect" "/hooks/v2")
        (declare (ignore body failure))
        (ok (eql status 308))
        (ok (search "://receiver.invalid:" location) "a relative Location is read against the URL, not the address")
        (ok (search "/hooks/v2" location)))
      (multiple-value-bind (status body failure location) (answer "304 Not Modified")
        (declare (ignore body failure))
        (ok (eql status 304))
        (ok (null location) "a 3xx that is not a redirect points nowhere")))))
