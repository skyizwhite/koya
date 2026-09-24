(defpackage #:koya-server/ui/icon
  (:use #:cl #:hsx)
  (:export #:~icon
           #:~model-icon))
(in-package #:koya-server/ui/icon)

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
