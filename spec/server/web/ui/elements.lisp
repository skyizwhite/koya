(defpackage #:koya-spec/server/web/ui/elements
  (:use #:cl #:rove)
  (:import-from #:hsx #:hsx #:render-to-string)
  (:import-from #:koya-server/web/ui/elements #:~errors #:~pager))
(in-package #:koya-spec/server/web/ui/elements)

(deftest a-component-with-nothing-to-draw-draws-nothing
  (ok (string= (render-to-string (hsx (~errors :errors nil))) ""))
  (ok (string= (render-to-string (hsx (~pager :page 1 :pages 1 :href #'princ-to-string
                                              :browse #'princ-to-string)))
               "")
      "not the word NIL"))
