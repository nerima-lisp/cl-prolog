;;;; term_to_atom/2 and read_term_from_atom/3 tests.
;;;;
;;;; term_to_atom in write mode renders a single atom whose name is the
;;;; term's quoted text (lowercased for display, hence the |...| escapes);
;;;; in parse mode it reads the atom's text back into a term.

(in-package #:cl-prolog.tests)

(deftest-queries term-to-atom-write ((make-rulebase))
  ((cl-prolog::term_to_atom (foo a b) ?a) :ordered (((?a . #.(cl-prolog:prolog-atom "foo(a,b)")))))
  ((cl-prolog::term_to_atom (foo (a b) 1) ?a) :ordered (((?a . #.(cl-prolog:prolog-atom "foo(a(b),1)")))))
  ((cl-prolog::term_to_atom 42 ?a)         :ordered (((?a . cl-prolog::|42|))))
  ;; operator notation is rendered with spaces.
  ((cl-prolog::term_to_atom (+ 1 2) ?a)    :ordered (((?a . #.(cl-prolog:prolog-atom "1 + 2"))))))

(deftest-queries term-to-atom-parse ((make-rulebase))
  ((cl-prolog::term_to_atom ?t "foo(a, b)") :ordered (((?t cl-prolog::foo cl-prolog::a cl-prolog::b))))
  ((cl-prolog::term_to_atom ?t "42")        :ordered (((?t . 42))))
  ;; operator-notation source parses to the prefix compound.
  ((cl-prolog::term_to_atom ?t "1+2")       :ordered (((?t + 1 2))))
  ;; round trip through write then parse.
  ((and (cl-prolog::term_to_atom (foo a b) ?a) (cl-prolog::term_to_atom ?t ?a))
   :ordered (((?a . #.(cl-prolog:prolog-atom "foo(a,b)")) (?t cl-prolog::foo cl-prolog::a cl-prolog::b))))
  ((cl-prolog::term_to_atom ?t "foo((")     :signals)
  ((cl-prolog::term_to_atom ?t ?a)          :signals))

(deftest-queries read-term-from-atom-builtin ((make-rulebase))
  ((cl-prolog::read_term_from_atom "bar(1, 2)" ?t ()) :ordered (((?t cl-prolog::bar 1 2))))
  ((cl-prolog::read_term_from_atom "42" ?t ())        :ordered (((?t . 42))))
  ((cl-prolog::read_term_from_atom "bad((" ?t ())     :signals)
  ((cl-prolog::read_term_from_atom ?a ?t ())          :signals)
  ((cl-prolog::read_term_from_atom "ok" ?t not-a-list) :signals))
