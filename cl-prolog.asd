;;;; System names are written as STRINGS, not #:symbols or :keywords: a string
;;;; does not depend on the reader's package state at load time, and a single
;;;; spelling keeps `grep` reliable across the org.

(asdf:defsystem "cl-prolog"
  :description "A small, dependency-free Common Lisp Prolog engine."
  :long-description "A macro-first Common Lisp Prolog engine with CPS proof search, an extensible builtin registry, and a compact rule DSL."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-prolog"
  :bug-tracker "https://github.com/nerima-lisp/cl-prolog/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-prolog.git")
  :long-name "cl-prolog"
  ;; Single source of truth for the version. flake.nix parses this exact form
  ;; (first match wins) and release.yml refuses to publish a tag that
  ;; disagrees with it, so a release edits this one line.
  :version "1.0.1"
  :pathname "src"
  :serial t
  :components ((:file "package")
                 (:file "atom-name")
                 (:file "operator-table")
                 (:file "module-system")
                 (:file "source-registry")
                 (:file "logic-variable")
                 (:file "clause")
                 (:file "predicate-index")
                 (:file "data")
                 (:file "table-variant")
                 (:file "environment-index")
                 (:file "unification")
                 (:file "lexer")
                 (:file "lexer-operator-lexemes")
                 (:file "lexer-tokenizer")
                 (:file "grammar")
                 (:file "term-writer")
               (:file "engine")
               (:file "io-context")
               (:file "proof-state")
               (:file "prover")
               (:file "tabling")
               (:module "builtins"
                :serial t
                :components ((:file "core")
                             (:file "control")
                             (:file "collection")
                             (:file "dynamic")
                             (:file "arithmetic")
                             (:file "list")
                             (:file "text-conversion")
                             (:file "atom-ops")
                             (:file "atom-number-conversion")
                             (:file "operator")
                             (:file "io")
                             (:file "io-streams")
                             (:file "io-code")))
               (:file "fd-store")
               (:file "builtins/fd")
               (:file "term-inspect")
               (:file "term-compare")
               (:file "term-construct")
               (:file "builtins/list-extra")
               (:file "builtins/apply")
               (:file "builtins/format")
               (:file "builtins/char-type")
               (:file "builtins/term-io")
               (:file "builtins/string")
               (:file "builtins/assoc")
               (:file "builtins/pairs")
               (:file "dcg-runtime")
               (:file "query")
               (:file "source-io")
               (:file "source-directives")
               (:file "source-rollback")
               (:file "source-loader")
               (:file "dsl-compiler")
               (:file "dsl")
               (:file "dcg"))
  :in-order-to ((asdf:test-op (asdf:test-op "cl-prolog/test"))))

(asdf:defsystem "cl-prolog/weave"
  :description "cl-weave helpers for testing cl-prolog queries."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.1"
  :homepage "https://github.com/nerima-lisp/cl-prolog"
  :bug-tracker "https://github.com/nerima-lisp/cl-prolog/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-prolog.git")
  :depends-on (#:cl-prolog #:cl-weave)
  :pathname "src"
  ;; :serial t so package-weave.lisp is loaded before the file that reads
  ;; symbols into the package it declares.
  :serial t
  :components ((:file "package-weave")
               (:file "weave")))

;;; The test system is `cl-prolog/test` — singular, slash-separated — with
;;; :pathname "t". It is NOT `cl-prolog-test` and NOT `cl-prolog/tests`.
(asdf:defsystem "cl-prolog/test"
  :description "Test system for cl-prolog."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.1"
  :homepage "https://github.com/nerima-lisp/cl-prolog"
  :bug-tracker "https://github.com/nerima-lisp/cl-prolog/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-prolog.git")
  :depends-on (#:cl-prolog/weave)
  :pathname "t"
  :serial t
  :components ((:file "support")
               (:module "support-files"
                :pathname "support"
                :serial t
                :components ((:file "core")
                             (:file "query")
                             (:file "fixtures")))
               (:file "unification")
               (:file "iso-conformance")
               (:file "iso-inria")
               (:file "atom-canonicalization")
               (:file "operator-table")
               (:file "parser")
               (:file "term-writer")
               (:file "io-context")
               (:file "source-loader")
               (:file "source-loader-transactions")
               (:file "source-loader-limits")
               (:file "engine-surface")
               (:file "engine-queries")
               (:file "builtin-collections")
               (:file "builtin-list")
               (:file "builtin-list-extra")
               (:file "builtin-dynamic-database")
               (:file "builtin-arithmetic-and-flags")
               (:file "engine-runtime")
               (:file "engine-runtime-index-and-depth")
               (:file "engine-runtime-foreign-and-registration")
               (:file "engine-runtime-error-contract")
               (:file "builtin-term")
               (:file "builtin-atom")
               (:file "builtin-operator")
               (:file "builtin-io-terms")
               (:file "builtin-io-streams-lifecycle")
               (:file "builtin-io-open-errors")
               (:file "builtin-io-code")
               (:file "builtin-format")
               (:file "builtin-char-type")
               (:file "builtin-term-io")
               (:file "builtin-string")
               (:file "builtin-occurs-check")
               (:file "builtin-assoc")
               (:file "builtin-pairs")
               (:file "builtin-fd")
               (:file "module-system")
               (:file "dcg")
               (:file "weave-public")
               (:file "weave-quality"))
  :perform (asdf:test-op (op c)
             (declare (ignore op c))
             (unless (uiop:symbol-call "CL-WEAVE" "RUN-ALL" :reporter :spec)
               (error "cl-prolog cl-weave test suite failed."))))

(asdf:defsystem "cl-prolog/examples"
  :description "Runnable examples for cl-prolog."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.1"
  :homepage "https://github.com/nerima-lisp/cl-prolog"
  :bug-tracker "https://github.com/nerima-lisp/cl-prolog/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-prolog.git")
  :depends-on (#:cl-prolog)
  :serial t
  :pathname "examples"
  :components ((:file "quick-start")
               (:file "family-tree")
               (:file "relational-lists")))
