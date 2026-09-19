(defpackage #:koya-server/actions
  (:use #:cl #:hsx)
  (:import-from #:ningle-actions
                #:defaction)
  (:import-from #:jingle
                #:set-response-status)
  (:import-from #:koya/core/markdown
                #:render-markdown)
  (:import-from #:koya-server/lib/auth
                #:session-owner-p)
  (:export #:preview-markdown))
(in-package #:koya-server/actions)

;;; HTMX partial endpoints used by the admin UI.

(defaction preview-markdown :post (params)
  "Render the first f-* textarea value in PARAMS as HTML."
  (cond ((not (session-owner-p))
         (set-response-status 401)
         nil)
        (t
         (let ((markdown (loop :for (k . v) :in params
                               :when (and (stringp k) (> (length k) 2) (string= (subseq k 0 2) "f-"))
                                 :return v)))
           (hsx (div (raw! (render-markdown (or markdown "")))))))))
