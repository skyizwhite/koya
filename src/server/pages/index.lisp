(defpackage #:koya-server/pages/index
  (:use #:cl #:hsx)
  (:import-from #:koya/core/schema #:schema-spaces #:space-name #:space-models)
  (:import-from #:koya-server/db/schema-store #:load-schema)
  (:import-from #:koya-server/lib/page #:with-owner #:set-title #:~layout #:~empty-state #:space-url)
  (:export #:@get #:@head))
(in-package #:koya-server/pages/index)

(defun @get (params)
  (declare (ignore params))
  (with-owner
    (set-title "Spaces · koya")
    (let ((spaces (schema-spaces (load-schema))))
      (hsx
       (~layout
         (h1 :class "mb-6 text-2xl font-bold" "Spaces")
         (if (null spaces)
             (hsx (~empty-state
                    (p "No schema yet.")
                    (p :class "mt-2" "Define spaces and models with " (code "defspace") " / " (code "defmodel")
                       " and run " (code "(koya:deploy)") " from your project's REPL.")))
             (hsx (ul :class "grid gap-3 sm:grid-cols-2"
                    (loop :for space :in spaces :collect
                      (hsx (li (a :href (space-url (space-name space))
                                  :class "block rounded-md border border-line bg-panel px-4 py-3 hover:border-accent"
                                 (div :class "font-semibold" (space-name space))
                                 (div :class "text-sm text-muted"
                                   (format nil "~a model~:p" (length (space-models space))))))))))))))))

;; health check
(defun @head (params)
  (declare (ignore params)))
