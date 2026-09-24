(defpackage #:koya-server/infra/env
  (:use #:cl)
  (:import-from #:cl-dotenv
                #:load-env)
  (:import-from #:koya-server/usecases/ports/config
                #:public-url #:owner-secret #:dev-mode-p)
  (:export #:env
           #:koya-env
           #:db-path
           #:media-dir
           #:server-port))
(in-package #:koya-server/infra/env)

(let ((env-path "./.env"))
  (when (probe-file env-path)
    (load-env env-path)))

(defun env (name &optional default)
  (let ((value (uiop:getenv name)))
    (if (or (null value) (string= value "")) default value)))

(defun required-env (name)
  (or (env name) (error "Environment variable ~a is not set" name)))

(defun koya-env () (env "KOYA_ENV" "production"))
(defmethod dev-mode-p () (string= (koya-env) "dev"))
(defmethod owner-secret () (required-env "KOYA_SECRET"))
(defun db-path () (env "KOYA_DB_PATH" "./data/koya.db"))
(defun media-dir () (env "KOYA_MEDIA_DIR" "./data/media"))
(defun server-port () (parse-integer (env "KOYA_PORT" "3100")))
(defmethod public-url ()
  (env "KOYA_BASE_URL" (format nil "http://localhost:~a" (server-port))))
