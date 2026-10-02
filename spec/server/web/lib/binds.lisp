(defpackage #:koya-spec/server/web/lib/binds
  (:use #:cl #:rove)
  (:import-from #:koya-server/web/lib/binds
                #:js-string #:on-submit #:on-click #:on-follow #:on-search #:on-reveal #:on-pick))
(in-package #:koya-spec/server/web/lib/binds)

(deftest js-string
  (ok (string= (js-string "/s/web site") "\"/s/web site\"") "a string is written as a JavaScript string")
  (ok (string= (js-string "say \"no\"") "\"say \\\"no\\\"\"") "what would end it is escaped"))

(deftest on-submit
  (ok (string= (on-submit "/act")
               "{ 'onsubmit.prevent': () => $post(\"/act\", koya.form(this)) }")
      "a form posts its fields as it is submitted, and the browser does not")
  (ok (string= (on-submit "/act" :data "{ id: _chosen }")
               "{ 'onsubmit.prevent': () => $post(\"/act\", { id: _chosen }) }")
      "or what it is given")
  (ok (string= (on-submit "/act" :confirm "Delete \"it\"?")
               "{ 'onsubmit.prevent': () => confirm(\"Delete \\\"it\\\"?\") && $post(\"/act\", koya.form(this)) }")
      "a question asked first stops it unless it is answered yes")
  (ok (string= (on-submit "/act" :binds "oninput: () => _track()")
               "{ 'onsubmit.prevent': () => $post(\"/act\", koya.form(this)), oninput: () => _track() }")
      "what else the element binds is kept beside it")
  (ok (string= (on-submit "/act" :binds nil)
               "{ 'onsubmit.prevent': () => $post(\"/act\", koya.form(this)) }")
      "and nothing when there is nothing else"))

(deftest on-click
  (ok (string= (on-click "/act")
               "{ onclick: () => $post(\"/act\") }")
      "a button posts as it is clicked, sending nothing of its own")
  (ok (string= (on-click "/act" :data "{ id: _chosen }")
               "{ onclick: () => $post(\"/act\", { id: _chosen }) }")
      "or what it is given")
  (ok (string= (on-click "/act" :confirm "Sure?")
               "{ onclick: () => confirm(\"Sure?\") && $post(\"/act\") }")
      "a question asked first stops it unless it is answered yes")
  (ok (string= (on-click "/act" :binds "disabled: () => _unchanged()")
               "{ onclick: () => $post(\"/act\"), disabled: () => _unchanged() }")
      "what else the element binds is kept beside it"))

(deftest on-follow
  (ok (string= (on-follow "/list?page=2")
               "{ onclick: (e) => koya.follow(e) && $get(\"/list?page=2\") }")
      "a link is got in place as it is followed, unless koya.follow leaves it to the browser"))

(deftest on-search
  (ok (string= (on-search "/list")
               (concatenate 'string
                            "{ 'onsubmit.prevent': () => _ask(\"/list\", this, true), "
                            "'oninput.debounce300': () => _ask(\"/list\", this), "
                            "onchange: () => _ask(\"/list\", this) }"))
      "a search asks as it is submitted, as the typing stops and as a choice changes")
  (ok (string= (on-search "/list" :typing nil)
               (concatenate 'string
                            "{ 'onsubmit.prevent': () => _ask(\"/list\", this, true), "
                            "onchange: () => _ask(\"/list\", this) }"))
      "or not as it is typed"))

(deftest on-reveal
  (ok (string= (on-reveal "/more")
               "{ oninit: koya.reveal, onrevealed: () => $get(\"/more\") }")
      "a placeholder is got as it comes into view"))

(deftest on-pick
  (ok (string= (on-pick "/upload")
               "{ onchange: (e) => koya.upload(e.target, \"/upload\", (url) => $fetch(url, 'GET')) }")
      "files are uploaded as they are picked, and the answer is drawn through the scope's fetch"))
