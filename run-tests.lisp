;;;; The Lisp-level entry point for the cl-prolog regression suite.
;;;;
;;;;     sbcl --script run-tests.lisp
;;;;
;;;; PACKAGE_STANDARD.md puts this file at the repository root in every
;;;; nerima-lisp package, so "how do I run the tests without Nix?" has one
;;;; answer org-wide. flake.nix's checks.default invokes exactly this script,
;;;; which is what keeps the local command and the CI gate from drifting.
;;;;
;;;; cl-weave must be reachable through CL_SOURCE_REGISTRY. `nix develop` and
;;;; `nix flake check` both set it; outside Nix, point it at a cl-weave
;;;; checkout yourself.
;;;;
;;;; --script implies --disable-debugger, so an unhandled error — including the
;;;; one cl-prolog/test's test-op signals on a failing suite — exits non-zero
;;;; with a backtrace rather than dropping into the REPL.

(require :asdf)

;;; Resolved from *LOAD-TRUENAME* rather than *DEFAULT-PATHNAME-DEFAULTS* so
;;; the script works both from the repository root and from the Nix store path
;;; that checks.default passes as an absolute argument.
(let ((root (make-pathname :name nil :type nil :version nil
                           :defaults *load-truename*)))
  (asdf:load-asd (merge-pathnames "cl-prolog.asd" root)))

(asdf:test-system "cl-prolog/test")
