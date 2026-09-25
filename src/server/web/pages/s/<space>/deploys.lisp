(defpackage #:koya-server/web/pages/s/<space>/deploys
  (:use #:cl #:hsx)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/usecases/schema/deploy #:list-deploys #:count-deploys #:+deploys-kept+)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:find-space)
  (:import-from #:koya-server/domain/deploy
                #:deploy-changes #:deploy-change-count #:deploy-destructive #:deploy-by
                #:deploy-created-at #:change-op #:change-destructive #:change-description)
  (:import-from #:koya-server/web/http #:path-param #:param #:blank-p)
  (:import-from #:koya-server/web/paging #:+page-size+ #:page-number #:last-page #:page-offset)
  (:import-from #:koya-server/web/display #:short-time #:caller-name)
  (:import-from #:koya-server/web/urls #:space-url)
  (:import-from #:koya-server/web/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout #:~missing)
  (:import-from #:koya-server/web/ui/elements #:~empty-state #:~pager)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast #:action-refusal)
  (:export #:@get #:deploys-url #:browse-deploys))
(in-package #:koya-server/web/pages/s/<space>/deploys)

;;; What each deploy of this space's schema changed, newest first. Read-only:
;;; deploys come from the project's repository through the client.
;;;
;;; Each change is drawn as the line PLAN prints for it.

(defun deploys-url (space &key page)
  (render-uri (make-uri :path (format nil "~a/deploys" (space-url space))
                        :query (when (and page (> page 1)) `(("page" . ,page))))))

(defun deployed-by (deploy) (caller-name (deploy-by deploy)))

(defun line-class (change)
  (let ((op (or (change-op change) "")))
    (cond ((change-destructive change) "text-danger")
          ((eql 0 (search "add_" op)) "text-ok")
          ((eql 0 (search "rename_" op)) "text-accent")
          (t "text-muted"))))

(defcomp ~diff (&key changes)
  (hsx
   (pre :class "max-h-96 overflow-auto rounded border border-line bg-base px-3 py-2 font-mono text-xs leading-5"
     (loop :for change :in changes :collect
       (hsx (div :class (line-class change) (change-description change)))))))

(defcomp ~deploy (&key deploy)
  (hsx
   (li :class "px-4 py-3"
     (div :class "mb-2 flex flex-wrap items-center justify-between gap-2 text-sm"
       (span :class "flex items-center gap-2"
         (span :class "font-medium" (format nil "~a change~:p" (deploy-change-count deploy)))
         (when (deploy-destructive deploy)
           (hsx (span :class "badge bg-danger/10 text-danger" "destructive")))
         ;; a deploy from the REPL names nobody
         (unless (blank-p (deployed-by deploy))
           (hsx (span :class "text-muted" (format nil "· ~a" (deployed-by deploy))))))
       (span :class "shrink-0 whitespace-nowrap text-muted" (short-time (deploy-created-at deploy))))
     (~diff :changes (deploy-changes deploy)))))

(defcomp ~deploys (&key space page)
  "What paging draws again: the deploys and their pager."
  (let* ((pages (last-page (count-deploys space)))
         (page (min page pages))
         (items (list-deploys space :limit +page-size+ :offset (page-offset page))))
    (hsx
     (div :id "deploys"
       (if (null items)
           (hsx (~empty-state "Nothing has been deployed yet."))
           (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                  (loop :for deploy :in items :collect
                    (hsx (~deploy :deploy deploy))))))
       (~pager :page page :pages pages :target "#deploys"
               :href (lambda (n) (deploys-url space :page n))
               :browse (lambda (n) (browse-deploys :space space :page n)))))))

(defcomp ~deploys-page (&key space page)
  (hsx
   (~layout :space space :crumbs (list (cons "Schema Deploys" nil))
     (h1 :class "mb-2 text-2xl font-bold" "Schema Deploys")
     (p :class "mb-4 text-sm text-muted"
       (format nil "~a deploy~:p, the newest ~a kept." (count-deploys space) +deploys-kept+))
     (~deploys :space space :page page))))

;; paging is answered in place, with the page put back in the URL
(defaction browse-deploys :get (params)
  (let ((space (param params "space")))
    (cond ((not (and space (find-space space))) (action-refusal "Space not found." 404))
          (t (let ((page (min (page-number params) (last-page (count-deploys space)))))
               (set-response-header :hx-replace-url (deploys-url space :page page))
               (hsx (~deploys :space space :page page)))))))

(defun @get (params)
  (let ((space (path-param params :space)))
    (cond ((null (find-space space)) (hsx (~missing :what "Space")))
          (t
           (set-title (format nil "Schema Deploys · ~a · koya" space))
           (hsx (~deploys-page :space space :page (page-number params)))))))
