(defpackage #:koya-server/usecases/actor
  (:use #:cl)
  (:export #:*actor*))
(in-package #:koya-server/usecases/actor)

(defvar *actor* ""
  "Who is making the change being made, as it is stored: \"owner\", or
\"key:<label>\" for a management key. The entry point that knows binds it; a
change made from the REPL names nobody, as \"\".")
