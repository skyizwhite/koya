(defpackage #:koya-server/pages/not-found
  (:use #:cl #:hsx)
  (:export #:@not-found))
(in-package #:koya-server/pages/not-found)

(defun @not-found ()
  (hsx (main :class "mx-auto max-w-5xl px-4 py-24 text-center"
         (h1 :class "text-2xl font-bold" "404")
         (p :class "mt-2 text-muted" "Not found")
         (a :href "/" :class "btn mt-6" "Home"))))
