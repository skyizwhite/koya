(defpackage #:koya-spec/server/web/ui/elements
  (:use #:cl #:rove)
  (:import-from #:hsx #:hsx #:render-to-string)
  (:import-from #:koya-server/web/ui/elements #:~errors #:~pager #:~search-form))
(in-package #:koya-spec/server/web/ui/elements)

(deftest a-component-with-nothing-to-draw-draws-nothing
  (ok (string= (render-to-string (hsx (~errors :errors nil))) ""))
  (ok (search "<div id=\"editor-errors\" hidden" (render-to-string (hsx (~errors :id "editor-errors" :errors nil))))
      "unless it has an id, where errors are drawn later")
  (ok (string= (render-to-string (hsx (~pager :page 1 :pages 1 :href #'princ-to-string
                                              :browse #'princ-to-string)))
               "")
      "not the word NIL"))


(deftest a-search-form
  (let ((form (render-to-string (hsx (~search-form :url "/list" :id "filters" :class "flex" (input :name "q"))))))
    (ok (search (concatenate 'string
                             "<form id=\"filters\" class=\"flex\" n-scope=\"koya.search()\""
                             " n-on-submit.prevent=\"ask(&quot;/list&quot;, $el, true)\""
                             " n-on-input.debounce300=\"ask(&quot;/list&quot;, $el)\""
                             " n-on-change=\"ask(&quot;/list&quot;, $el)\""
                             "><input name=\"q\"></form>")
                form)
        "asks as it is submitted, as the typing stops and as a choice changes, and keeps what else it is given"))
  (ok (not (search "n-on-input" (render-to-string (hsx (~search-form :url "/list" :changes-only t)))))
      "or not as it is typed"))
