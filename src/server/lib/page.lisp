(defpackage #:koya-server/lib/page
  (:use #:cl #:hsx)
  (:import-from #:jingle
                #:redirect #:set-response-status #:set-response-header)
  (:import-from #:ningle
                #:context)
  (:import-from #:lack/request
                #:request-method #:request-uri)
  (:import-from #:quri
                #:uri #:uri-path #:uri-query #:make-uri #:render-uri)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:import-from #:koya-server/lib/auth
                #:session-owner-p #:session-logout)
  (:import-from #:ningle-actions
                #:defaction)
  (:import-from #:koya-server/lib/assets
                #:asset-url)
  (:import-from #:koya-server/lib/timezone
                #:format-local)
  (:import-from #:koya/core/schema
                #:model-label)
  (:import-from #:koya/core/json
                #:json-null #:json-array)
  (:import-from #:koya-server/db/contents
                #:content-id #:content-data)
  (:export #:with-owner
           #:owner-p
           #:set-title
           #:page-title
           #:redirect-to
           #:local-path-p
           #:param
           #:set-toast
           #:take-toast
           #:expand-url-template
           #:short-time
           #:caller-name
           #:content-label
           #:~layout
           #:~footer
           #:~status-badge
           #:~toast
           #:~toast-oob
           #:logout
           #:action-refusal
           #:~errors
           #:~empty-state
           #:~icon
           #:~model-icon
           #:space-url
           #:model-url
           #:content-url))
(in-package #:koya-server/lib/page)

;;; Helpers shared by the admin UI pages.

(defun owner-p () (session-owner-p))

(defun set-title (title) (setf (context :title) title))
(defun page-title () (context :title))

(defun redirect-to (path &optional (status 303))
  (redirect path status))

;;; One-shot messages carried in the session across a redirect. A session is
;;; stored as JSON (see db/sessions), so the message travels as a pair of
;;; strings rather than as a list holding a keyword.

(defun set-toast (message &optional (kind :ok))
  (let ((session (context :session)))
    (when session (setf (gethash "toast" session) (json-array message (string-downcase kind))))))

(defun take-toast ()
  "Return (values message kind) once, then forget it."
  (let* ((session (context :session))
         (toast (and session (gethash "toast" session))))
    (when (and toast (= (length toast) 2))
      (remhash "toast" session)
      (values (aref toast 0) (if (equal (aref toast 1) "error") :error :ok)))))

(defun short-time (iso)
  "2026-09-20T05:04:03.123Z -> 2026-09-20 14:04 JST, in the zone chosen on the settings page."
  (format-local iso))

(defun caller-name (by)
  "\"owner\" or \"key:<label>\" as stored, in words. Kept out of the rows so that
rewording it reaches the rows already written."
  (let ((by (or by "")))
    (cond ((string= by "key:") "(management key)")
          ((eql 0 (search "key:" by)) (format nil "(management key: ~a)" (subseq by 4)))
          (t by))))

(defun content-label (content model)
  "What CONTENT is shown as: the value of the field MODEL declares as its :label,
else its id. No field is taken for a title unless the schema says so -- the
first text field of one model is another's subtitle."
  (let* ((label (model-label model))
         (data (and label (content-data content :draft t)))
         (value (and data (gethash label data))))
    (if (and (stringp value) (plusp (length value)))
        value
        (content-id content))))

(defun expand-url-template (template &key id draft-key)
  "Fill {CONTENT_ID} and {DRAFT_KEY} in a model's preview/public URL template."
  (and template
       (regex-replace-all "\\{DRAFT_KEY\\}"
                          (regex-replace-all "\\{CONTENT_ID\\}" template (or id ""))
                          (or draft-key ""))))

(defun local-path-p (path)
  "True for a path on this server. What the login page redirects to comes from the
URL, so anything that a browser could read as another host (//evil, /\\evil) is out."
  (and (stringp path)
       (plusp (length path))
       (char= (char path 0) #\/)
       (not (and (> (length path) 1) (char= (char path 1) #\/)))
       (notany (lambda (c) (or (char< c #\Space) (char= c #\\))) path)))

(defun path-and-query (url)
  (let ((uri (uri url)))
    (render-uri (make-uri :path (or (uri-path uri) "/") :query (uri-query uri)))))

(defun return-path ()
  "The page to come back to after logging in: the one requested. Pages answer GET
only; an action that finds no session sends its own way back (lib/auth)."
  (ignore-errors
   ;; the raw request line: path-info is decoded, and an encoded ? or / would change meaning
   (path-and-query (request-uri ningle:*request*))))

(defun redirect-to-login ()
  (let ((next (return-path)))
    (redirect-to (if (and (local-path-p next) (string/= next "/"))
                     (render-uri (make-uri :path "/login" :query `(("next" . ,next))))
                     "/login")
                 302)))

(defmacro with-owner (&body body)
  "Run BODY for the logged-in owner, otherwise redirect to the login page."
  `(if (owner-p)
       (progn ,@body)
       (redirect-to-login)))

(defun param (params name)
  (let ((v (cdr (assoc name params :test #'equal))))
    (if (and (stringp v) (string= v "")) nil v)))


(defun space-url (space) (format nil "/s/~a" space))
(defun model-url (space model) (format nil "/s/~a/m/~a" space model))
(defun content-url (space model id) (format nil "/s/~a/m/~a/~a" space model id))

;;; Icons. Every button in the admin UI carries one, drawn in the same 16x16
;;; box and stroke as ~MODEL-ICON. An entry naming another icon shares its
;;; drawing: publishing and uploading are the same gesture.

(defparameter +icons+
  '((:external "M11.5 8.75V12.5A1.5 1.5 0 0 1 10 14H3.5A1.5 1.5 0 0 1 2 12.5V6a1.5 1.5 0 0 1 1.5-1.5h3.75"
               "M9.75 2H14v4.25" "M7.5 8.5 14 2")
    (:save "M8 2H3.5A1.5 1.5 0 0 0 2 3.5v9A1.5 1.5 0 0 0 3.5 14h9a1.5 1.5 0 0 0 1.5-1.5V8"
           "M12.25 1.75a1.06 1.06 0 0 1 1.5 1.5l-5.3 5.3a1.3 1.3 0 0 1-.55.33l-1.9.55a.33.33 0 0 1-.41-.41l.55-1.9a1.3 1.3 0 0 1 .33-.55z")
    ;; the page of :save, with a rip where its pen is
    (:discard "M8 2H3.5A1.5 1.5 0 0 0 2 3.5v9A1.5 1.5 0 0 0 3.5 14h9a1.5 1.5 0 0 0 1.5-1.5V8"
              "M13.8 1.8 11.6 3.6l1.6 1.1-2.4 1.8 1.5 1.1-2.6 2")
    (:publish "M2.5 10.5v2A1.5 1.5 0 0 0 4 14h8a1.5 1.5 0 0 0 1.5-1.5v-2"
              "M8 10.5V2.5" "M4.8 5.7 8 2.5l3.2 3.2")
    (:unpublish "M2.5 10.5v2A1.5 1.5 0 0 0 4 14h8a1.5 1.5 0 0 0 1.5-1.5v-2"
                "M8 2.5v8" "M4.8 7.3 8 10.5l3.2-3.2")
    (:upload :publish)
    (:export :publish)
    (:import :unpublish)
    (:delete "M2.5 4.2h11"
             "M12.3 4.2v8.3A1.5 1.5 0 0 1 10.8 14H5.2a1.5 1.5 0 0 1-1.5-1.5V4.2"
             "M5.8 4.2V2.9a1.2 1.2 0 0 1 1.2-1.2h2a1.2 1.2 0 0 1 1.2 1.2v1.3")
    (:plus "M8 3v10" "M3 8h10")
    (:check "M3.2 8.4 6.5 11.7 12.8 4.6")
    (:close "M4.2 4.2l7.6 7.6" "M11.8 4.2l-7.6 7.6")
    (:search "M11.5 7a4.5 4.5 0 1 1-9 0 4.5 4.5 0 1 1 9 0" "M10.4 10.4 14 14")
    (:settings "M2.5 5.5h2.5" "M8.5 5.5h5" "M8.5 5.5a1.75 1.75 0 1 1-3.5 0 1.75 1.75 0 1 1 3.5 0"
               "M2.5 10.5h5" "M11 10.5h2.5" "M11 10.5a1.75 1.75 0 1 1-3.5 0 1.75 1.75 0 1 1 3.5 0")
    (:logout "M6 14H3.3A1.3 1.3 0 0 1 2 12.7V3.3A1.3 1.3 0 0 1 3.3 2H6" "M10.7 11.3 14 8l-3.3-3.3" "M14 8H6")
    (:login "M10 2h2.7A1.3 1.3 0 0 1 14 3.3v9.4a1.3 1.3 0 0 1-1.3 1.3H10" "M6.7 11.3 10 8 6.7 4.7" "M10 8H2")
    (:media "M3.5 2h9A1.5 1.5 0 0 1 14 3.5v9a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 12.5v-9A1.5 1.5 0 0 1 3.5 2z"
            "M7 6.2a1 1 0 1 1-2 0 1 1 0 1 1 2 0" "M14 10.5 11.9 8.4a1.3 1.3 0 0 0-1.9 0L4.5 14")
    (:key "M8.67 10.3a3.67 3.67 0 1 1-7.34 0 3.67 3.67 0 1 1 7.34 0" "M7.6 7.7 14 1.3"
          "M10.3 5l2 2 2.4-2.3-2-2")
    (:rotate "M2 8a6 6 0 0 1 6-6 6.5 6.5 0 0 1 4.5 1.83L14 5.33" "M14 2v3.33h-3.33"
             "M14 8a6 6 0 0 1-6 6 6.5 6.5 0 0 1-4.5-1.83L2 10.67" "M5.33 10.67H2V14")
    ;; a clock turned back: what was deployed, and when
    (:history "M2.4 8a5.6 5.6 0 1 0 1.7-4" "M2 2.6V6h3.4" "M8 5v3.2l2.3 1.4")
    (:eye "M1.5 8S4 3.5 8 3.5 14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z"
          "M9.8 8a1.8 1.8 0 1 1-3.6 0 1.8 1.8 0 1 1 3.6 0")
    (:shield "M8 14.4S13 12.3 13 8.4V4.1L8 2.2 3 4.1v4.3c0 3.9 5 6 5 6z")
    ;; one source, two receivers: the shape of a hook fanning out
    (:webhook "M9.8 4a1.8 1.8 0 1 1-3.6 0 1.8 1.8 0 1 1 3.6 0"
              "M5.8 11.9a1.8 1.8 0 1 1-3.6 0 1.8 1.8 0 1 1 3.6 0"
              "M13.8 11.9a1.8 1.8 0 1 1-3.6 0 1.8 1.8 0 1 1 3.6 0"
              "M7.1 5.6 4.9 10.3" "M8.9 5.6 11.1 10.3" "M5.8 11.9h4.4")
    (:home "M2.5 7.4 8 2.5l5.5 4.9V13a1.2 1.2 0 0 1-1.2 1.2H3.7A1.2 1.2 0 0 1 2.5 13z" "M6.4 14.2V9.6h3.2v4.6")
    (:prev "M10 3 5 8l5 5")
    (:next "M6 3l5 5-5 5"))
  "What a button draws beside its label, as paths in a 16x16 box.")

(defun icon-paths (name)
  (let ((entry (cdr (assoc name +icons+))))
    (if (keywordp (first entry)) (icon-paths (first entry)) entry)))

(defcomp ~icon (&key name)
  (hsx
   (svg :|viewBox| "0 0 16 16" :fill "none" :stroke "currentColor" :stroke-width "1.5"
        :stroke-linecap "round" :stroke-linejoin "round" :aria-hidden "true"
        :class "h-4 w-4 shrink-0"
     (loop :for d :in (icon-paths name) :collect (hsx (path :d d))))))

;;; A component whose whole body is a condition wraps it in a fragment: NIL is
;;; nothing as a child, but a component's own value is rendered, and a NIL there
;;; comes out as the word NIL.

(defcomp ~toast (&key message (kind :ok) oob)
  "What came of what was done, at the top of the screen, going by itself (.toast in
global.css): a success after a few seconds, an error after long enough to read it.
#toast is always there, empty or not, so an action's answer can put one in out of
band."
  (let ((error (eq kind :error)))
    (hsx
     (div :id "toast" :hx-swap-oob (and oob "true")
          :class "pointer-events-none fixed inset-x-4 top-4 z-50 flex justify-center"
       (when message
         (hsx (div :role (if error "alert" "status")
                   ;; on a phone it spans the top, over the header and the editor's
                   ;; bar, so taps go through it; the pointer pauses it elsewhere
                   :class (clsx "toast pointer-events-none w-full rounded-md border bg-panel px-4 py-3 text-sm shadow-lg sm:pointer-events-auto sm:w-auto sm:max-w-md"
                                (if error "toast-long border-danger/40 text-danger" "border-ok/40 text-ok"))
                message)))))))

(defcomp ~toast-oob (&key message (kind :ok))
  "The toast for an action's answer: the session's toast waits for the next page,
which a swap never renders, so the message goes out of band into the layout's #toast."
  (hsx (~toast :message message :kind kind :oob t)))

(defun action-refusal (message &optional (status 400))
  "An action's answer when it cannot do what was asked: the page stays as it is and
MESSAGE shows as the toast. htmx 4 swaps an error response in, so the reswap says not to."
  (set-response-status status)
  (set-response-header :hx-reswap "none")
  (hsx (~toast-oob :message message :kind :error)))

(defcomp ~errors (&key errors)
  (hsx
   (<> (when errors
         (hsx (div :class "mb-6 rounded-md border border-danger/40 bg-danger/5 px-4 py-3 text-sm text-danger"
                (ul :class "list-disc pl-5"
                  (loop :for e :in errors :collect
                    (hsx (li (strong (getf e :field)) " " (getf e :message)))))))))))

;;; The AGPL asks a server that others use over the network to offer them its
;;; source, so every page links to it. The link is the system's :homepage: a fork
;;; that points it at its own repository offers its own source.

(defparameter *version* (asdf:component-version (asdf:find-system "koya-server")))
(defparameter *repository* (asdf:system-homepage (asdf:find-system "koya-server")))

(defcomp ~footer ()
  (hsx
   (footer :class "mx-auto w-full max-w-5xl border-t border-line px-4 py-6 text-xs text-muted"
     (p :class "flex flex-wrap items-center gap-x-3 gap-y-1"
       (span (format nil "koya ~a" *version*))
       (a :href *repository* :class "hover:text-fg hover:underline" "Source code")
       (span "Licensed under the "
             (a :href "https://www.gnu.org/licenses/agpl-3.0.html" :class "hover:text-fg hover:underline"
                "GNU AGPL v3.0")
             " or later")))))

(defcomp ~crumb (&key href label)
  (hsx (span :class "flex min-w-0 max-w-full items-center gap-2 whitespace-nowrap"
         (span :class "text-muted" "/")
         (if href
             (hsx (a :href href :class "max-w-48 truncate text-fg hover:underline sm:max-w-xs" :title label label))
             (hsx (span :class "max-w-48 truncate text-muted sm:max-w-xs" :title label label))))))

;; the header's Log out, on every page
(defaction logout :post (params)
  (declare (ignore params))
  (session-logout)
  (set-response-header :hx-redirect "/login")
  (hsx (<>)))

(defcomp ~layout (&key space crumbs children)
  (hsx
   (<>
     (header :class "border-b border-line bg-panel"
       (div :class "mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3"
         ;; on a narrow screen the crumbs wrap, each with its slash, and a long one
         ;; (a content's label) is cut short; the buttons keep their size
         (nav :class "flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-sm"
           (a :href "/" :class "inline-flex shrink-0 items-center gap-2 font-bold tracking-tight text-fg"
              (img :src (asset-url "icon.svg") :alt "" :width "20" :height "20" :class "h-5 w-5 rounded")
              "koya")
           (when space
             (hsx (~crumb :href (space-url space) :label space)))
           (loop :for (label . href) :in crumbs :collect
             (hsx (~crumb :href href :label label))))
         (div :class "flex shrink-0 items-center gap-2"
           (a :href "/settings" :class "btn" :aria-label "Settings"
              (~icon :name :settings) (span :class "hidden sm:inline" "Settings"))
           (form :hx-post (logout)
             (button :type "submit" :class "btn" :aria-label "Log out"
                     (~icon :name :logout) (span :class "hidden sm:inline" "Log out"))))))
     (main :class "mx-auto w-full max-w-5xl flex-1 px-4 py-8"
       (multiple-value-bind (message kind) (take-toast)
         (hsx (~toast :message message :kind kind)))
       children)
     (~footer))))

(defcomp ~status-badge (&key status)
  (let ((class (cond ((string= status "published") "bg-ok/10 text-ok")
                     ((string= status "published+draft") "bg-warn/10 text-warn")
                     (t "bg-line text-muted"))))
    (hsx (span :class (clsx "badge" class) status))))

(defcomp ~model-icon (&key kind (class "h-4 w-4"))
  "Inline icon for a model KIND: stacked rows for :list, a JSON object's braces
for :object -- one model, one document, the shape the delivery API returns."
  (hsx
   (svg :|viewBox| "0 0 16 16" :fill "none" :stroke "currentColor" :stroke-width "1.5"
        :stroke-linecap "round" :stroke-linejoin "round" :aria-hidden "true"
        :class (clsx "shrink-0" class)
     (if (eq kind :object)
         ;; { : } -- braces around the colon that separates a key from its value
         (hsx (<> (path :d "M6 2.5C4.8 2.5 4.25 3.05 4.25 4.25L4.25 6.5C4.25 7.4 3.7 8 2.75 8C3.7 8 4.25 8.6 4.25 9.5L4.25 11.75C4.25 12.95 4.8 13.5 6 13.5")
                  (path :d "M10 2.5C11.2 2.5 11.75 3.05 11.75 4.25L11.75 6.5C11.75 7.4 12.3 8 13.25 8C12.3 8 11.75 8.6 11.75 9.5L11.75 11.75C11.75 12.95 11.2 13.5 10 13.5")
                  (path :d "M8 6.4h.01M8 9.6h.01")))
         ;; three bulleted rows
         (hsx (path :d "M2 3.5h.5M5.5 3.5H14M2 8h.5M5.5 8H14M2 12.5h.5M5.5 12.5H14"))))))

(defcomp ~empty-state (&key children)
  (hsx (div :class "rounded-md border border-dashed border-line px-6 py-10 text-center text-sm text-muted" children)))
