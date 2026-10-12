(defpackage #:koya-spec/server/web/lib/presenters
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/media #:make-media)
  (:import-from #:koya-server/web/lib/presenters #:media-url)
  (:import-from #:koya-spec/server/main #:with-env))
(in-package #:koya-spec/server/web/lib/presenters)

(deftest a-media-is-reached-at-its-url
  (let ((media (make-media :id "01ARZ3NDEKTSV4RRFFQ69G5FAV" :space "website" :mime "image/png")))
    (with-env (("KOYA_BASE_URL" "https://cms.example/"))
      (ok (string= (media-url media) "https://cms.example/media/website/01ARZ3NDEKTSV4RRFFQ69G5FAV.png")
          "under the server's public URL, its file named by its id and type")
      (ok (string= (media-url media :absolute nil) "/media/website/01ARZ3NDEKTSV4RRFFQ69G5FAV.png")
          "or as a path, as the editor writes it into rich text"))))
