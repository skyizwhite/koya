(defpackage #:koya-server/pages/s/<space>/deploys
  (:use #:cl #:hsx)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/schema-deploys #:list-deploys #:count-deploys #:+keep-per-space+)
  (:import-from #:koya-server/domain/deploy
                #:deploy-changes #:deploy-change-count #:deploy-destructive #:deploy-by
                #:deploy-created-at #:change-op #:change-destructive #:change-description)
  (:import-from #:koya-server/lib/http #:path-param #:param #:blank-p)
  (:import-from #:koya-server/lib/paging #:+page-size+ #:page-number #:last-page #:page-offset)
  (:import-from #:koya-server/lib/auth #:with-owner)
  (:import-from #:koya-server/lib/display #:short-time #:caller-name)
  (:import-from #:koya-server/lib/urls #:space-url)
  (:import-from #:koya-server/document #:set-title)
  (:import-from #:koya-server/ui/layout #:~layout)
  (:import-from #:koya-server/ui/elements #:~empty-state)
  (:import-from #:koya-server/ui/icon #:~icon)
  (:import-from #:koya-server/ui/toast #:action-refusal)
  (:export #:@get #:deploys-url #:browse-deploys))
(in-package #:koya-server/pages/s/<space>/deploys)

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
    (flet ((page-link (n)
             (hsx (a :href (deploys-url space :page n)
                     :hx-get (browse-deploys :space space :page n) :hx-target "#deploys" :hx-swap "outerHTML"
                     :class "btn"
                     (if (< n page)
                         (hsx (<> (~icon :name :prev) "Previous"))
                         (hsx (<> "Next" (~icon :name :next))))))))
      (hsx
       (div :id "deploys"
         (if (null items)
             (hsx (~empty-state "Nothing has been deployed yet."))
             (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                    (loop :for deploy :in items :collect
                      (hsx (~deploy :deploy deploy))))))
         (when (> pages 1)
           (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                  (when (> page 1) (page-link (1- page)))
                  (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                  (when (< page pages) (page-link (1+ page)))))))))))

(defcomp ~deploys-page (&key space page)
  (hsx
   (~layout :space space :crumbs (list (cons "Schema Deploys" nil))
     (h1 :class "mb-2 text-2xl font-bold" "Schema Deploys")
     (p :class "mb-4 text-sm text-muted"
       (format nil "~a deploy~:p, the newest ~a kept." (count-deploys space) +keep-per-space+))
     (~deploys :space space :page page))))

;; paging is answered in place, with the page put back in the URL
(defaction browse-deploys :get (params)
  (let ((space (param params "space")))
    (cond ((not (and space (find-space space))) (action-refusal "Space not found." 404))
          (t (let ((page (min (page-number params) (last-page (count-deploys space)))))
               (set-response-header :hx-replace-url (deploys-url space :page page))
               (hsx (~deploys :space space :page page)))))))

(defun @get (params)
  (with-owner
    (let ((space (path-param params :space)))
      (cond ((null (find-space space))
             (set-response-status 404)
             (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            (t
             (set-title (format nil "Schema Deploys · ~a · koya" space))
             (hsx (~deploys-page :space space :page (page-number params))))))))
