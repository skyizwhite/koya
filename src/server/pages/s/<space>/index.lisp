(defpackage #:koya-server/pages/s/<space>/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya/core/schema
                #:space-models #:model-name #:model-kind #:model-webhooks #:space-webhooks
                #:webhook-label #:webhook-url #:webhook-events)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/contents #:count-contents)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page #:with-owner #:set-title #:~layout #:~empty-state #:~model-icon #:model-url #:space-url)
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
                  (div :class "flex gap-2"
                    (a :href (format nil "~a/media" (space-url name)) :class "btn" "Media")
                    (a :href (format nil "~a/keys" (space-url name)) :class "btn" "API keys")))
                (if (null (space-models space))
                    (hsx (~empty-state "This space has no models."))
                    (hsx (ul :class "divide-y divide-line rounded-md border border-line bg-panel"
                           (loop :for model :in (space-models space) :collect
                             (hsx (li (a :href (model-url name (model-name model))
                                         :class "flex items-center justify-between gap-3 px-4 py-3 hover:bg-base"
                                        (span :class "flex items-center gap-3 font-medium"
                                          (~model-icon :kind (model-kind model) :class "h-4 w-4 text-muted")
                                          (model-name model))
                                        (if (eq (model-kind model) :list)
                                            (hsx (span :class "text-sm text-muted"
                                                   (format nil "~a content~:p" (count-contents name (model-name model)))))
                                            (hsx (<>))))))))))
                (let ((hooks (append (mapcar (lambda (h) (cons nil h)) (space-webhooks space))
                                     (loop :for model :in (space-models space)
                                           :append (mapcar (lambda (h) (cons (model-name model) h)) (model-webhooks model))))))
                  (when hooks
                    (hsx (section :class "mt-8"
                           (h2 :class "mb-2 text-sm font-semibold text-muted" "Webhooks")
                           (ul :class "space-y-1 text-sm"
                             (loop :for (model . hook) :in hooks :collect
                               (hsx (li :class "flex flex-wrap items-center gap-2"
                                      (span :class "font-medium" (webhook-label hook))
                                      (span :class "text-muted" (if model (format nil "~a only" model) "all models"))
                                      (code :class "text-xs" (webhook-url hook))
                                      (span :class "text-xs text-muted"
                                        (format nil "~{~(~a~)~^, ~}" (webhook-events hook))))))))))))))))))
