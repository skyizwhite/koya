(defpackage #:koya-server/web/ui/picker
  (:use #:cl #:hsx)
  (:import-from #:koya-server/web/lib/binds #:js-string)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:export #:~picker-dialog))
(in-package #:koya-server/web/ui/picker)

(defcomp ~picker-dialog (&key id class title factory url add-label)
  (hsx
   (dialog :id id :class (clsx "koya-dialog koya-dialog-wide" class)
           :nm-data (format nil "...koya.~a(this, ~a)" factory (js-string url))
           :nm-bind "{ onclick: (e) => e.target === this && _close(), onopenpicker: (e) => _open(e.detail) }"
     (div :class "flex items-center justify-between border-b border-line px-4 py-3"
       (h2 :class "font-semibold" title)
       (button :type "button" :class "btn btn-icon" :nm-bind "{ onclick: () => _close() }" :aria-label "Close"
         (~icon :name :close)))
     (div :id (format nil "~a-content" id) :class "max-h-[70vh] overflow-y-auto p-4"
       (div :id (format nil "~a-body" id) :class "text-sm text-muted" "Loading…"))
     (div :class "flex items-center justify-end gap-3 border-t border-line px-4 py-3" :hidden t
          :nm-bind "{ hidden: () => !_many }"
       (span :class "text-sm text-muted" :nm-bind "{ textContent: () => `${_chosen.length} selected` }")
       (button :type "button" :class "btn btn-primary"
               :nm-bind "{ onclick: () => _done(), disabled: () => !_chosen.length }"
         (~icon :name :check) add-label)))))
