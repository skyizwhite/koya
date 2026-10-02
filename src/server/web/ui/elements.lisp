(defpackage #:koya-server/web/ui/elements
  (:use #:cl #:hsx)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/lib/binds #:on-follow)
  (:export #:~errors
           #:~empty-state
           #:~status-badge
           #:~pager
           #:~confirm-dialog
           #:~go-to
           #:~replace-url))
(in-package #:koya-server/web/ui/elements)

(defcomp ~errors (&key errors)
  (hsx
   (<> (when errors
         (hsx (div :class "mb-6 rounded-md border border-danger/40 bg-danger/5 px-4 py-3 text-sm text-danger"
                (ul :class "list-disc pl-5"
                  (loop :for e :in errors :collect
                    (hsx (li (strong (getf e :field)) " " (getf e :message)))))))))))

(defcomp ~empty-state (&key children)
  (hsx (div :class "rounded-md border border-dashed border-line px-6 py-10 text-center text-sm text-muted" children)))

(defcomp ~status-badge (&key status)
  (let ((class (cond ((string= status "published") "bg-ok/10 text-ok")
                     ((string= status "published+draft") "bg-warn/10 text-warn")
                     (t "bg-line text-muted"))))
    (hsx (span :class (clsx "badge" class) status))))

(defcomp ~pager (&key page pages href browse)
  (flet ((link (n)
           (hsx (a :href (funcall href n) :nm-bind (on-follow (funcall browse n)) :class "btn"
                   (if (< n page)
                       (hsx (<> (~icon :name :prev) "Previous"))
                       (hsx (<> "Next" (~icon :name :next))))))))
    (hsx
     (<> (when (> pages 1)
           (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                  (when (> page 1) (link (1- page)))
                  (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                  (when (< page pages) (link (1+ page))))))))))

(defcomp ~confirm-dialog (&key id title message children)
  (hsx
   (dialog :id id :closedby "any" :class "koya-dialog max-w-sm"
     (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
       (h2 :class "font-semibold" title)
       (button :type "button" :commandfor id :command "close" :class "btn btn-icon" :aria-label "Close"
         (~icon :name :close)))
     (p :class "px-4 py-4 text-sm" message)
     (div :class "flex justify-end gap-2 border-t border-line px-4 py-3"
       (button :type "button" :commandfor id :command "close" :class "btn" "Cancel")
       children))))

(defcomp ~go-to (&key url)
  (hsx (div :id "location" :hidden t :data-go url
            :nm-bind "{ oninit: () => window.location.assign(this.dataset.go) }")))

(defcomp ~replace-url (&key url)
  (hsx (div :id "location" :hidden t :data-replace url
            :nm-bind "{ oninit: () => history.replaceState(history.state, '', this.dataset.replace) }")))
