;;;; t/package.lisp -- the package every file in the suite is read into.
;;;;
;;;; Named package.lisp, not support.lisp: CODING_STANDARD.md exempts
;;;; package.lisp and suite.lisp from the <source>-test.lisp rule because they
;;;; are manifests, and that is all this file is. The shared fixtures and
;;;; assertions it used to sit beside live in t/support/.

(defpackage #:cl-prolog.tests
  (:use #:cl #:cl-prolog #:cl-prolog/weave)
  (:shadowing-import-from #:cl-prolog #:assert #:catch #:throw)
  (:export #:deftest
           #:deftest-table
           #:deftest-io-variants
           #:deftest-queries
           #:assert-query
           #:with-single-query-solution
           #:is
           #:is-equal
           #:is-same-set
           #:signals-error
           #:make-family-rulebase))

(in-package #:cl-prolog.tests)
