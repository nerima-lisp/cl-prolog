;;;; The Lisp-level entry point for the cl-prolog coverage report.
;;;;
;;;;     sbcl --script run-coverage.lisp [report-directory]
;;;;
;;;; Mirrors run-tests.lisp's role as the one org-wide answer to "how do I
;;;; run this without Nix?" (see PACKAGE_STANDARD.md); flake.nix's
;;;; checks.coverage invokes exactly this script so the local command and the
;;;; CI gate cannot drift apart.
;;;;
;;;; Only :cl-prolog and the project-owned :cl-prolog/weave are compiled with
;;;; SB-COVER's instrumentation on. cl-weave is loaded before coverage is
;;;; enabled, while :cl-prolog/test loads after it is disabled, so neither
;;;; external test-harness code nor the test system can enter the report.
;;;;
;;;; cl-weave must be reachable through CL_SOURCE_REGISTRY, exactly as
;;;; run-tests.lisp requires.
(require :asdf)

(require :sb-cover)

(let ((root
      (make-pathname :name nil :type nil :version nil :defaults *load-truename*)))
  (asdf:load-asd (merge-pathnames "cl-prolog.asd" root)))

(progn
  (asdf:load-system "cl-weave")
  (declaim (optimize sb-cover:store-coverage-data))
  (asdf:load-system "cl-prolog" :force t)
  (asdf:load-system "cl-prolog/weave"))

(declaim (optimize (sb-cover:store-coverage-data 0)))

;; asdf:test-system's :perform method is what raises on a failing suite, so
;; reusing it here (rather than calling CL-WEAVE:RUN-ALL directly) is what
;; makes this script refuse to report coverage for a red suite for free.
(asdf:test-system "cl-prolog/test")

(let* ((argument (second sb-ext:*posix-argv*))
       (report-directory
      (if argument (uiop:ensure-directory-pathname (uiop:parse-native-namestring argument))
        (merge-pathnames "coverage/" (truename ".")))))
  (sb-cover:report report-directory)
  (format t "~&Coverage report written to ~A~%" report-directory))
