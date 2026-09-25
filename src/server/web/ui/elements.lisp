(defpackage #:koya-server/web/ui/elements
  (:use #:cl #:hsx)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:export #:~errors
           #:~empty-state
           #:~status-badge
           #:~pager))
(in-package #:koya-server/web/ui/elements)

;;; Small pieces any page draws.

;;; A component whose whole body is a condition wraps it in a fragment: NIL is
;;; nothing as a child, but a component's own value is rendered, and a NIL there
;;; comes out as the word NIL.

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

(defcomp ~pager (&key page pages href browse target)
  "Previous and Next under a list of PAGES pages, on PAGE, when there is more
than one. HREF gives a page's URL and BROWSE the action that draws it in place,
each a function of the page number; TARGET is what that action replaces."
  (flet ((link (n)
           (hsx (a :href (funcall href n) :hx-get (funcall browse n)
                   :hx-target target :hx-swap "outerHTML" :class "btn"
                   (if (< n page)
                       (hsx (<> (~icon :name :prev) "Previous"))
                       (hsx (<> "Next" (~icon :name :next))))))))
    (hsx
     (<> (when (> pages 1)
           (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                  (when (> page 1) (link (1- page)))
                  (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                  (when (< page pages) (link (1+ page))))))))))
