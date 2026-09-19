(defpackage #:koya-server/pages/s/<space>/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya/core/schema #:space-models #:model-name #:model-kind #:space-webhooks)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/contents #:count-contents)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page #:with-owner #:set-title #:~layout #:~empty-state #:model-url #:space-url)
  (:export #:@get))
(in-package #:koya-server/pages/s/<space>/index)

(defun @get (params)
  (with-owner
    (let* ((name (path-param params :space))
           (space (find-space name)))
      (cond ((null space)
             (set-response-status 404)
             (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            (t
             (set-title (format nil "~a · koya" name))
             (hsx
              (~layout :space name
                (div :class "mb-6 flex items-center justify-between"
                  (h1 :class "text-2xl font-bold" name)
                  (a :href (format nil "~a/keys" (space-url name)) :class "btn" "API keys"))
                (if (null (space-models space))
                    (hsx (~empty-state "This space has no models."))
                    (hsx (ul :class "divide-y divide-line rounded-md border border-line bg-panel"
                           (loop :for model :in (space-models space) :collect
                             (hsx (li (a :href (model-url name (model-name model))
                                         :class "flex items-center justify-between px-4 py-3 hover:bg-base"
                                        (span :class "font-medium" (model-name model))
                                        (span :class "text-sm text-muted"
                                          (format nil "~(~a~) · ~a content~:p" (model-kind model)
                                                  (count-contents name (model-name model)))))))))))
                (when (space-webhooks space)
                  (hsx (section :class "mt-8"
                         (h2 :class "mb-2 text-sm font-semibold text-muted" "Webhooks")
                         (ul :class "text-sm"
                           (loop :for url :in (space-webhooks space) :collect (hsx (li (code url)))))))))))))))
