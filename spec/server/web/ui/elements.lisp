(defpackage #:koya-spec/server/web/ui/elements
  (:use #:cl #:rove)
  (:import-from #:hsx #:hsx #:render-to-string)
  (:import-from #:koya-server/web/ui/elements #:~errors #:~pager #:~go-to))
(in-package #:koya-spec/server/web/ui/elements)

(deftest a-component-with-nothing-to-draw-draws-nothing
  (ok (string= (render-to-string (hsx (~errors :errors nil))) ""))
  (ok (string= (render-to-string (hsx (~pager :page 1 :pages 1 :href #'princ-to-string
                                              :browse #'princ-to-string)))
               "")
      "not the word NIL"))

(deftest a-page-the-server-sends-the-browser-to
  (ok (search "window.location.assign(this.dataset.go)" (render-to-string (hsx (~go-to :url "/login"))))
      "is left as any page is, so an editor with unsaved changes asks first")
  (ok (search "koya.go(this.dataset.go)" (render-to-string (hsx (~go-to :url "/s/website" :on-purpose t))))
      "unless it is the editor moving on after its own write, which asks nothing"))
