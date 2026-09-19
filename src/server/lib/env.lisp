(defpackage #:koya-server/lib/env
  (:use #:cl)
  (:import-from #:cl-dotenv
                #:load-env)
  (:export #:env
           #:koya-env
           #:dev-mode-p
           #:koya-secret
           #:db-path
           #:media-dir
           #:base-url
           #:server-port))
(in-package #:koya-server/lib/env)

(let ((env-path "./.env"))
  (when (probe-file env-path)
    (load-env env-path)))

(defun env (name &optional default)
  (let ((value (uiop:getenv name)))
    (if (or (null value) (string= value "")) default value)))

(defun required-env (name)
  (or (env name) (error "Environment variable ~a is not set" name)))

(defun koya-env () (env "KOYA_ENV" "production"))
(defun dev-mode-p () (string= (koya-env) "dev"))
(defun koya-secret () (required-env "KOYA_SECRET"))
(defun db-path () (env "KOYA_DB_PATH" "./data/koya.db"))
(defun media-dir () (env "KOYA_MEDIA_DIR" "./data/media"))
(defun base-url () (env "KOYA_BASE_URL" "http://localhost:3000"))
(defun server-port () (parse-integer (env "KOYA_PORT" "3000")))
