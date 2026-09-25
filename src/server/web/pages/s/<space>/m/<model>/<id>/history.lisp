(defpackage #:koya-server/web/pages/s/<space>/m/<model>/<id>/history
  (:use #:cl #:hsx)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya/core/schema
                #:model-kind #:model-name #:model-field #:field-type #:field-option)
  (:import-from #:koya/core/json #:json-array-p)
  (:import-from #:koya/core/validate #:blank-value-p)
  (:import-from #:koya-server/usecases/contents/revisions #:list-revisions #:count-revisions)
  (:import-from #:koya-server/usecases/contents/lookup #:find-content #:resolve-model)
  (:import-from #:koya-server/web/target #:target-model #:target-content)
  (:import-from #:koya-server/domain/content #:content-id #:content-label)
  (:import-from #:koya-server/domain/revision
                #:revision-id #:revision-event #:revision-data #:revision-by
                #:revision-created-at #:changed-keys)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:find-space #:find-model)
  (:import-from #:koya-server/usecases/media/library #:find-media)
  (:import-from #:koya-server/domain/media #:media-filename)
  (:import-from #:koya-server/web/http #:path-param #:param)
  (:import-from #:koya-server/domain/errors #:not-found)
  (:import-from #:koya-server/web/forms #:number->string)
  (:import-from #:koya-server/web/assets #:asset-url)
  (:import-from #:koya-server/web/paging #:+page-size+ #:page-number #:last-page #:page-offset)
  (:import-from #:koya-server/web/display #:short-time #:caller-name)
  (:import-from #:koya-server/web/urls #:content-url #:model-url)
  (:import-from #:koya-server/web/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/elements #:~empty-state #:~pager)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast #:action-refusal)
  (:export #:@get #:history-url #:restore-url #:browse-history))
(in-package #:koya-server/web/pages/s/<space>/m/<model>/<id>/history)

;;; A content's revisions, newest first, each drawn as what it changed against
;;; the one before it in the same view: every write, or the publishes alone,
;;; where the one before is the version that was live until then.

(defun history-url (space model id &key published-only page)
  (render-uri (make-uri :path (format nil "~a/history" (content-url space model id))
                        :query (append (when published-only '(("view" . "published")))
                                       (when (and page (> page 1)) `(("page" . ,page)))))))

(defun restore-url (space model id revision-id)
  "The editor, with REVISION-ID's data in the form."
  (render-uri (make-uri :path (content-url space model id) :query `(("revision" . ,revision-id)))))

(defparameter +events+
  '(("draft" . "Draft saved")
    ("publish" . "Published")
    ("unpublish" . "Unpublished")
    ("discard" . "Draft discarded")))

(defun event-label (event) (or (cdr (assoc event +events+ :test #'string=)) event))

(defun event-class (event)
  (cond ((string= event "publish") "bg-ok/10 text-ok")
        ((string= event "unpublish") "bg-warn/10 text-warn")
        (t "bg-line text-muted")))

;;; Values, as text. A value is drawn whole: this page is where a change is
;;; read, so nothing is cut. Rich text is the exception, drawn as rich text by
;;; ~RICHTEXT.

(defun id-text (space field id)
  "An id with what it points at, when that still exists."
  (let ((label (if (eq (field-type field) :media)
                   (let ((media (find-media space id))) (and media (media-filename media)))
                   (let* ((target-model (find-model space (field-option field :model)))
                          (target (and target-model (find-content space (model-name target-model) id))))
                     (and target (content-label target target-model))))))
    (if (and label (string/= label id)) (format nil "~a (~a)" label id) id)))

(defun scalar-text (space field value)
  (case (and field (field-type field))
    ((:reference :media) (id-text space field value))
    (:datetime (short-time value))
    (:boolean (if value "Yes" "No"))
    (:number (if (realp value) (number->string value) (princ-to-string value)))
    (t (if (eq value t) "Yes" (princ-to-string value)))))

(defun value-text (space field value found)
  "VALUE as text, or NIL for none. FIELD is NIL for a key the model has lost."
  (cond ((and field (eq (field-type field) :boolean))
         (and found (scalar-text space field value)))
        ((or (not found) (blank-value-p value)) nil)
        ((json-array-p value)
         (format nil "~{~a~^, ~}" (map 'list (lambda (v) (scalar-text space field v)) value)))
        (t (scalar-text space field value))))

(defun richtext-document (html)
  "A page of its own for HTML, styled as the site might style it."
  (format nil "<!doctype html><html><head><meta charset=\"utf-8\"><link rel=\"stylesheet\" href=\"~a\"></head>~
               <body class=\"prose prose-sm max-w-none bg-transparent\">~a</body></html>"
          (asset-url "style/dist.css") html))

(defcomp ~richtext (&key html)
  "Stored rich text is whatever a management key sent, so it is not put in this
page: a sandbox without allow-scripts runs nothing in it, not even an onerror.
allow-same-origin is only there so that koya-editor.js can read its height."
  (hsx (iframe :sandbox "allow-same-origin" :srcdoc (richtext-document html) :title "rich text"
               :data-fit-content t :class "block h-16 w-full")))

(defcomp ~value (&key space field value found class)
  (let ((text (value-text space field value found)))
    (hsx
     (div :class (clsx "max-h-64 overflow-auto break-words rounded border px-3 py-2"
                       (if text class "border-line text-muted"))
       (cond ((null text) "—")
             ((and field (eq (field-type field) :richtext)) (~richtext :html value))
             (t (hsx (div :class "whitespace-pre-wrap font-mono text-xs leading-5" text))))))))

(defcomp ~changes (&key space model before after)
  (let ((keys (changed-keys model before after)))
    (hsx
     (<> (if (null keys)
             (hsx (p :class "text-sm text-muted" "No field changed."))
             (hsx (div :class "space-y-3"
                    (loop :for key :in keys :collect
                      (let ((field (model-field model key)))
                        (multiple-value-bind (old found-old) (if before (gethash key before) (values nil nil))
                          (multiple-value-bind (new found-new) (gethash key after)
                            (hsx (div
                                   (p :class "mb-1 text-sm font-medium" key
                                     (unless field
                                       (hsx (span :class "ml-2 font-normal text-muted" "no longer a field"))))
                                   ;; the oldest has nothing to be compared with: its values alone
                                   (if before
                                       (hsx (div :class "grid gap-2 sm:grid-cols-2"
                                              (~value :space space :field field :value old :found found-old
                                                      :class "border-danger/30 bg-danger/5")
                                              (~value :space space :field field :value new :found found-new
                                                      :class "border-ok/30 bg-ok/5")))
                                       (hsx (~value :space space :field field :value new :found found-new
                                                    :class "border-line"))))))))))))))))

(defcomp ~revision (&key space model id revision previous)
  (hsx
   (li :class "px-4 py-3"
     (div :class "mb-3 flex flex-wrap items-center justify-between gap-2 text-sm"
       (span :class "flex flex-wrap items-center gap-2"
         (span :class (clsx "badge" (event-class (revision-event revision))) (event-label (revision-event revision)))
         (span :class "whitespace-nowrap text-muted" (short-time (revision-created-at revision)))
         ;; a write from the REPL names nobody
         (unless (blank-value-p (caller-name (revision-by revision)))
           (hsx (span :class "text-muted" (format nil "· ~a" (caller-name (revision-by revision)))))))
       (a :href (restore-url space (model-name model) id (revision-id revision)) :class "btn"
          (~icon :name :history) "Restore"))
     (when (null previous)
       (hsx (p :class "mb-2 text-sm text-muted" "The oldest version in this view.")))
     (~changes :space space :model model
               :before (and previous (revision-data previous))
               :after (revision-data revision)))))

(defcomp ~tab (&key href browse active children)
  (hsx (a :href href :hx-get browse :hx-target "#revisions" :hx-swap "outerHTML"
          :class (clsx "border-b-2 px-3 py-2 text-sm"
                       (if active "border-accent font-medium text-fg" "border-transparent text-muted hover:text-fg"))
          children)))

(defun page-count (id published-only)
  (last-page (count-revisions id :published-only published-only)))

(defcomp ~revisions (&key space model content published-only page)
  "What a tab or a page draws again: the tabs, the versions and their pager."
  (let* ((model-name (model-name model))
         (id (content-id content))
         (pages (page-count id published-only))
         (page (min page pages))
         ;; one more than the page, so its last row has the one before it to compare with
         (rows (list-revisions id :published-only published-only
                                  :limit (1+ +page-size+) :offset (page-offset page)))
         (items (subseq rows 0 (min +page-size+ (length rows))))
         (view (if published-only "published" "")))
    (hsx
     (div :id "revisions"
       (nav :class "mb-4 flex items-center gap-1 border-b border-line"
         (~tab :href (history-url space model-name id)
               :browse (browse-history :space space :model model-name :id id :view "" :page 1)
               :active (not published-only)
               (format nil "All changes (~a)" (count-revisions id)))
         (span :class "text-sm text-muted" :aria-hidden "true" "/")
         (~tab :href (history-url space model-name id :published-only t)
               :browse (browse-history :space space :model model-name :id id :view "published" :page 1)
               :active published-only
               (format nil "Published (~a)" (count-revisions id :published-only t))))
       (if (null items)
           (hsx (~empty-state (if published-only "This content has never been published." "No history yet.")))
           (hsx (ul :class "divide-y divide-line overflow-hidden rounded-md border border-line bg-panel"
                  (loop :for (revision previous) :on rows
                        :for n :below (length items)
                        :collect (hsx (~revision :space space :model model :id id
                                                 :revision revision :previous previous))))))
       (~pager :page page :pages pages :target "#revisions"
               :href (lambda (n) (history-url space model-name id :published-only published-only :page n))
               :browse (lambda (n) (browse-history :space space :model model-name :id id :view view :page n)))))))

(defcomp ~history-page (&key space model content published-only page)
  (let* ((model-name (model-name model))
         (id (content-id content)))
    (hsx
     (~layout :space space
              :crumbs (if (eq (model-kind model) :object)
                          (list (cons model-name (content-url space model-name id)) (cons "History" nil))
                          (list (cons model-name (model-url space model-name))
                                (cons (content-label content model) (content-url space model-name id))
                                (cons "History" nil)))
       (h1 :class "mb-2 text-2xl font-bold" "History")
       (p :class "mb-4 text-sm text-muted"
         "Every saved version of this content, newest first.")
       (~revisions :space space :model model :content content :published-only published-only :page page)))))

;; a tab or a page is answered in place, with the view and page put back in the URL
(defaction browse-history :get (params)
  (let* ((space (param params "space"))
         (model (target-model params))
         (content (and model (target-content params model))))
    (cond ((null content) (action-refusal "Content not found." 404))
          (t
           (let* ((published-only (equal (param params "view") "published"))
                  (page (min (page-number params) (page-count (content-id content) published-only))))
             (set-response-header :hx-replace-url
                                  (history-url space (model-name model) (content-id content)
                                               :published-only published-only :page page))
             (hsx (~revisions :space space :model model :content content
                              :published-only published-only :page page)))))))

(defun @get (params)
  (handler-case
      (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
        (let ((content (find-content space (model-name model) (path-param params :id))))
          (cond ((null content)
                 (set-response-status 404)
                 (hsx (~layout :space space (h1 :class "text-xl font-bold" "Content not found"))))
                (t
                 (set-title (format nil "History · ~a · ~a · koya" (model-name model) space))
                 (hsx (~history-page :space space :model model :content content
                                     :published-only (equal (param params "view") "published")
                                     :page (page-number params)))))))
    (not-found ()
      (set-response-status 404)
      (hsx (~layout (h1 :class "text-xl font-bold" "Model not found"))))))
