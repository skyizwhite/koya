(defpackage #:koya-spec/server/threads
  (:use #:cl)
  (:export #:at-once))
(in-package #:koya-spec/server/threads)

(defun at-once (count thunk)
  (let* ((go nil)
         (threads (loop :repeat count
                        :collect (bt2:make-thread (lambda ()
                                                    (loop :until go :do (bt2:thread-yield))
                                                    (handler-case (funcall thunk)
                                                      (error (e) e)))))))
    (setf go t)
    (mapcar #'bt2:join-thread threads)))
