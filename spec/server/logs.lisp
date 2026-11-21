(defpackage #:koya-spec/server/logs
  (:use #:cl)
  (:import-from #:org.shirakumo.verbose
                #:*process-locally* #:*global-controller* #:ansi-colors #:repl-faucet #:output-here)
  (:import-from #:piping #:find-place)
  (:export #:logged))
(in-package #:koya-spec/server/logs)

(setf *process-locally* t)

(setf (ansi-colors (find-place *global-controller* 'repl-faucet)) nil)

(output-here (make-broadcast-stream))

(defun logged (thunk)
  (let ((out (make-string-output-stream)))
    (output-here out)
    (unwind-protect (funcall thunk)
      (output-here (make-broadcast-stream)))
    (get-output-stream-string out)))
