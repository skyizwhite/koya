(defpackage #:koya-spec/server/web/lib/binds
  (:use #:cl #:rove)
  (:import-from #:koya-server/web/lib/binds
                #:js-string #:post #:submit #:follow #:ask #:upload-picked))
(in-package #:koya-spec/server/web/lib/binds)

(deftest js-string
  (ok (string= (js-string "/s/web site") "\"/s/web site\"") "a string is written as a JavaScript string")
  (ok (string= (js-string "say \"no\"") "\"say \\\"no\\\"\"") "what would end it is escaped"))

(deftest submit
  (ok (string= (submit "/act")
               "$post(\"/act\", e)")
      "a form posts its fields, sent as the event that submits it")
  (ok (string= (submit "/act" :data "{ id: chosen }")
               "$post(\"/act\", { id: chosen })")
      "or what it is given")
  (ok (string= (submit "/act" :confirm "Delete \"it\"?")
               "confirm(\"Delete \\\"it\\\"?\") && $post(\"/act\", e)")
      "a question asked first stops it unless it is answered yes")
  (ok (string= (submit "/act" :guard "koya.mayLeave()")
               "koya.mayLeave() && $post(\"/act\", e)")
      "and so does a guard, asked before the question"))

(deftest post
  (ok (string= (post "/act")
               "$post(\"/act\")")
      "a button posts, sending nothing of its own")
  (ok (string= (post "/act" :data "{ id: chosen }")
               "$post(\"/act\", { id: chosen })")
      "or what it is given")
  (ok (string= (post "/act" :confirm "Sure?")
               "confirm(\"Sure?\") && $post(\"/act\")")
      "a question asked first stops it unless it is answered yes"))

(deftest follow
  (ok (string= (follow "/list?page=2")
               "koya.follow(e) && $get(\"/list?page=2\")")
      "a link is got in place as it is followed, unless koya.follow leaves it to the browser"))

(deftest ask
  (ok (string= (ask "/more")
               "$get(\"/more\")")
      "a placeholder gets what it stands for"))

(deftest upload-picked
  (ok (string= (upload-picked "/upload")
               "koya.fits(e.target) && $post(\"/upload\", e)")
      "files are posted with their form as they are picked, unless they are over the limit"))
