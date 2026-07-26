;;;; src/package-weave.lisp
;;;;
;;;; Not folded into src/package.lisp, which CODING_STANDARD.md otherwise makes
;;;; the single home for defpackage forms. CL-PROLOG/WEAVE belongs to the
;;;; cl-prolog/weave system, which exists only so the test suite can depend on
;;;; cl-weave without the engine doing so -- "dependency-free" is a claim the
;;;; core system's .asd makes and this repository's README repeats. Defining
;;;; the package in src/package.lisp would hand every plain (asdf:load-system
;;;; "cl-prolog") a package whose two exported macros have no definitions.
;;;; package-<subsystem>.lisp is the name the standard's own checker
;;;; recognises for exactly this case.

(defpackage #:cl-prolog/weave
  (:use #:cl)
  (:documentation
   "cl-weave assertions for cl-prolog queries: ASSERT-QUERY for a single
expectation and DEFTEST-QUERIES for a table of them. Defined by the
cl-prolog/weave system, not by cl-prolog itself.")
  (:export
   #:assert-query
   #:deftest-queries))
