;;;; callgraph/test/package.lisp - cl-weave test package for cl-prolog/callgraph
;;;;
;;;; CL-WEAVE:DESCRIBE shadows CL:DESCRIBE, so it must be imported with
;;;; :SHADOWING-IMPORT-FROM rather than :USE — the same convention cl-weave
;;;; uses for its own test package (tests/package.lisp in cl-weave itself),
;;;; and the convention nerima-lisp/cl-cc's packages/prolog-tools/tests used
;;;; for this same code before the split.

(defpackage #:cl-prolog/callgraph/test
  (:use #:cl #:cl-prolog/callgraph)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
   #:it
   #:it-property
   #:expect
   #:gen-list
   #:gen-tuple
   #:gen-member
   #:gen-integer
   #:run-all
   #:run-mutations
   #:assert-mutation-score))
