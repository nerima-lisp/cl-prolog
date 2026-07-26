;;;; library(pairs) tests.

(in-package #:cl-prolog.tests)

(deftest-queries pairs-builtins ((make-rulebase))
  ((cl-prolog::pairs_keys_values ((- a 1) (- b 2)) ?k ?v)
   :ordered (((?k a b) (?v 1 2))))
  ((cl-prolog::pairs_keys_values ?p (a b) (1 2))
   :ordered (((?p (cl-prolog.user-atoms::- a 1) (cl-prolog.user-atoms::- b 2)))))
  ((cl-prolog::pairs_keys_values () ?k ?v)
   :ordered (((?k) (?v))))
  ((cl-prolog::pairs_keys ((- a 1) (- b 2)) ?k) :ordered (((?k a b))))
  ((cl-prolog::pairs_values ((- a 1) (- b 2)) ?v) :ordered (((?v 1 2))))
  ((cl-prolog::pairs_keys_values ?p ?k ?v) :signals)
  ((cl-prolog::pairs_keys_values ?p (a b) (1)) :signals)
  ((cl-prolog::pairs_keys (not-a-pair) ?k) :signals)
  ;; a proper 3-list with the wrong functor is not a pair
  ((cl-prolog::pairs_keys ((+ a 1)) ?k) :signals)
  ;; duplicate keys are preserved (no dedup)
  ((cl-prolog::pairs_keys_values ((- a 1) (- a 2)) ?k ?v)
   :ordered (((?k a a) (?v 1 2)))))
