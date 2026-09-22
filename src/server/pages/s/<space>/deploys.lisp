(defpackage #:koya-server/pages/s/<space>/deploys
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/schema-deploys
                #:list-deploys #:count-deploys #:+keep-per-space+
                #:deploy-changes #:deploy-change-count #:deploy-destructive
                #:deploy-by #:deploy-created-at
                #:change-op #:change-destructive #:change-description)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:set-title #:param #:short-time
                #:~layout #:~empty-state #:~icon #:space-url)
  (:export #:@get #:deploys-url))
(in-package #:koya-server/pages/s/<space>/deploys)

;;; What each deploy of this space's schema changed, newest first. Read-only:
;;; deploys come from the project's repository through the client.
;;;
;;; Each change is drawn as the line PLAN prints for it.

(defparameter +page-size+ 20)

(defun deploys-url (space &key page)
  (format nil "~a/deploys~@[?page=~a~]" (space-url space) (and page (> page 1) page)))

(defun page-number (params)
  (max 1 (or (ignore-errors (parse-integer (or (param params "page") "1"))) 1)))

(defun blank-p (value) (or (null value) (zerop (length value))))

(defun deployed-by (deploy)
  "\"owner\" or \"key:<label>\" as stored, in words. Kept out of the row so that
rewording it reaches the rows already written."
  (let ((by (or (deploy-by deploy) "")))
    (cond ((string= by "key:") "(management key)")
          ((eql 0 (search "key:" by)) (format nil "(management key: ~a)" (subseq by 4)))
          (t by))))

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

(defcomp ~deploys-page (&key space page)
  (let* ((total (count-deploys space))
         (pages (max 1 (ceiling total +page-size+)))
         (page (min page pages))
         (items (list-deploys space :limit +page-size+ :offset (* (1- page) +page-size+))))
    (hsx
     (~layout :space space :crumbs (list (cons "Schema Deploys" nil))
       (h1 :class "mb-2 text-2xl font-bold" "Schema Deploys")
       (p :class "mb-4 text-sm text-muted"
         (format nil "~a deploy~:p, the newest ~a kept." total +keep-per-space+))
       (if (null items)
           (hsx (~empty-state "Nothing has been deployed yet."))
           (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                  (loop :for deploy :in items :collect
                    (hsx (~deploy :deploy deploy))))))
       (when (> pages 1)
         (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                (when (> page 1)
                  (hsx (a :href (deploys-url space :page (1- page)) :class "btn" (~icon :name :prev) "Previous")))
                (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                (when (< page pages)
                  (hsx (a :href (deploys-url space :page (1+ page)) :class "btn" "Next" (~icon :name :next)))))))))))

(defun @get (params)
  (with-owner
    (let ((space (path-param params :space)))
      (cond ((null (find-space space))
             (set-response-status 404)
             (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            (t
             (set-title (format nil "Schema Deploys · ~a · koya" space))
             (hsx (~deploys-page :space space :page (page-number params))))))))
