(defpackage #:koya-server/web/pages/s/<space>/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya/core/schema
                #:schema-models #:schema-webhooks #:model-name #:model-kind
                #:webhook-label #:webhook-url #:webhook-only)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:load-schema)
  (:import-from #:koya-server/usecases/contents/listing #:count-contents)
  (:import-from #:koya-server/web/http #:path-param)
  (:import-from #:koya-server/web/urls #:model-url #:space-url)
  (:import-from #:koya-server/web/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout #:~missing)
  (:import-from #:koya-server/web/ui/elements #:~empty-state)
  (:import-from #:koya-server/web/ui/icon #:~icon #:~model-icon)
  (:import-from #:koya-server/web/pages/s/<space>/webhooks #:webhook-log-url)
  (:import-from #:koya-server/web/pages/s/<space>/deploys #:deploys-url)
  (:export #:@get))
(in-package #:koya-server/web/pages/s/<space>/index)

(defun @get (params)
  (let* ((name (path-param params :space))
         (schema (load-schema name)))
    (cond ((null schema) (hsx (~missing :what "Space")))
          (t
           (set-title (format nil "~a · koya" name))
           (hsx
            (~layout :space name
              (div :class "mb-6 flex flex-wrap items-center justify-between gap-3"
                (h1 :class "text-2xl font-bold" name)
                (div :class "flex flex-wrap gap-2"
                  (a :href (deploys-url name) :class "btn" (~icon :name :history) "Schema Deploys")
                  (a :href (format nil "~a/media" (space-url name)) :class "btn" (~icon :name :media) "Media")
                  (a :href (format nil "~a/keys" (space-url name)) :class "btn" (~icon :name :key) "Keys")
                  (a :href (format nil "~a/export" (space-url name)) :class "btn"
                    (~icon :name :export) "Export")))
              (if (null (schema-models schema))
                  (hsx (~empty-state "This space has no models."))
                  (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                         (loop :for model :in (schema-models schema) :collect
                           (hsx (li (a :href (model-url name (model-name model))
                                       :class "flex items-center justify-between gap-3 px-4 py-3 hover:bg-base"
                                      (span :class "flex items-center gap-3 font-medium"
                                        (~model-icon :kind (model-kind model) :class "h-4 w-4 text-muted")
                                        (model-name model))
                                      (when (eq (model-kind model) :list)
                                        (hsx (span :class "text-sm text-muted"
                                               (format nil "~a content~:p" (count-contents name (model-name model)))))))))))))
              (let ((hooks (schema-webhooks schema)))
                (when hooks
                  ;; each row opens the log filtered to that webhook; "View log" opens it unfiltered
                  (hsx (section :class "mt-8"
                         (div :class "mb-2 flex items-baseline justify-between gap-3"
                           (h2 :class "text-sm font-semibold text-muted" "Webhooks")
                           (a :href (webhook-log-url name) :class "text-sm text-muted hover:text-fg hover:underline"
                              "View log →"))
                         (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                           (loop :for hook :in hooks :collect
                             (hsx (li (a :href (webhook-log-url name :label (webhook-label hook))
                                         :class "flex items-center justify-between gap-3 px-4 py-3 hover:bg-base"
                                        (span :class "min-w-0"
                                          (span :class "block font-medium" (webhook-label hook))
                                          (code :class "block truncate text-xs text-muted" (webhook-url hook)))
                                        (span :class "shrink-0 text-sm text-muted"
                                          (if (webhook-only hook)
                                              (format nil "~{~a~^, ~} only" (webhook-only hook))
                                              "all models")))))))))))))))))
