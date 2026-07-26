;;;; Cut, tabling, and left-recursion detection tests.  Predicate-index and
;;;; depth-limit tests live in engine-runtime-index-and-depth-test.lisp; foreign
;;;; predicates and define-builtin registration in
;;;; engine-runtime-foreign-and-registration-test.lisp; the ISO error contract in
;;;; engine-runtime-error-contract-test.lisp.

(in-package #:cl-prolog.tests)

(defvar *observed-table-session* nil)

(cl-prolog::define-builtin (test-nested-table-session)
    (rulebase environment depth emit)
  (let ((outer cl-prolog::*current-table-session*))
    (cl-prolog::%prove-bindings/k
     '(true) rulebase environment depth
     (lambda (bindings)
       (setf *observed-table-session*
             (and outer
                  (eq outer cl-prolog::*current-table-session*)))
       (funcall emit bindings)))))

(deftest-queries cut-prunes-clause-alternatives
    ((prolog
      ((choice left))
      ((choice right))
      ((pick ?x) (choice ?x) !)
      ((pick fallback) (choice left))
      ((commit-here) !)
      ((commit-here) fail)
      ((commit-value first) !)
      ((commit-value second))))
  ((pick ?x) :ordered (((?x . left))))
  ((commit-value ?x) :ordered (((?x . first))))
  (((choice ?x) (commit-here)) :ordered (((?x . left)) ((?x . right))))
  (((choice ?x) !) :ordered (((?x . left))))
  ((and (choice ?x) !) :ordered (((?x . left))))
  (((choice ?x) (call !)) :ordered (((?x . left)) ((?x . right))))
  (((choice ?x) (once (and (choice ?y) !)))
   :ordered (((?x . left) (?y . left)) ((?x . right) (?y . left))))
  (((choice ?x) (if-then-else (and true !) true fail))
   :ordered (((?x . left)) ((?x . right))))
  (((choice ?x) (if-then-else true ! fail)) :ordered (((?x . left))))
  (((choice ?x) (if-then-else fail true !)) :ordered (((?x . left))))
  )

(deftest malformed-clauses-are-ignored ()
  (let ((rb (make-rulebase)))
    (rulebase-insert-clause! rb (make-clause '() '((anything))))
    (rulebase-insert-clause! rb (make-clause '(ready)))
    (is-equal '(nil) (query-prolog rb '(ready)))))

(deftest-queries facts-are-tried-before-rules
    ((prolog
      ((color red))
      ((color ?x) (= ?x derived))))
  ((color ?x) :ordered (((?x . red)) ((?x . derived)))))

;; The recursive argument keeps growing, so variant tabling cannot close a
;; fixed point and the explicit depth budget must fire.  (A plain P :- P
;; loop is answered finitely by tabling and would fail instead of signal.)
(deftest-queries depth-bound-signals-incomplete-search
    ((prolog
      ((loop-forever ?n) (loop-forever (s ?n)))))
  ((loop-forever zero) :signals :max-depth 16))

(deftest variant-tabling-terminates-left-recursion ()
  (let* ((edge-count 128)
         (rulebase
           (make-rulebase
            :clauses
            (append
             (list
              (make-clause
               (quote (path ?x ?y))
               (quote ((path ?x ?z) (edge ?z ?y))))
              (make-clause
               (quote (path ?x ?y))
               (quote ((edge ?x ?y)))))
             (loop for source below edge-count
                   collect (make-clause
                            (list (quote edge) source (1+ source)))))))
         (solutions (query-prolog rulebase (quote (path 0 ?who)))))
    (is-equal
     (loop for target from 1 to edge-count
           collect (list (cons (quote ?who) target)))
     solutions)))

(deftest-queries variant-tabling-deduplicates-answers
    ((prolog
      ((reachable ?x ?y) (reachable ?x ?z) (arc ?z ?y))
      ((reachable ?x ?y) (arc ?x ?y))
      ((arc a b))
      ((arc a b))
      ((arc b c))
      ((arc a c))))
  ((reachable a ?who)
   :ordered (((?who . b)) ((?who . c)))))

(deftest-queries variant-tabling-terminates-mutual-left-recursion
    ((prolog
      ((even-node ?x) (odd-node ?x))
      ((even-node zero))
      ((odd-node ?x) (even-node ?x))
      ((odd-node one))))
  ((even-node ?x) :ordered (((?x . one)) ((?x . zero)))))

(deftest-queries variant-tabling-terminates-three-node-left-recursion
    ((prolog
      ((cycle-a ?x) (cycle-b ?x))
      ((cycle-a a))
      ((cycle-b ?x) (cycle-c ?x))
      ((cycle-c ?x) (cycle-a ?x))
      ((cycle-c c))))
  ((cycle-a ?x) :ordered (((?x . c)) ((?x . a)))))

(deftest tabled-predicate-preserves-and-deduplicates-cyclic-answer (:timeout 2)
  (let* ((cycle-a (cons 'loop nil))
         (cycle-b (cons 'loop nil))
         (rulebase (make-rulebase)))
    (setf (cdr cycle-a) cycle-a
          (cdr cycle-b) cycle-b)
    (rulebase-insert-clause!
     rulebase (make-clause (list 'cyclic-answer cycle-a)))
    (rulebase-insert-clause!
     rulebase (make-clause (list 'cyclic-answer cycle-b)))
    (cl-prolog::%add-rulebase-table-declaration!
     rulebase 'cyclic-answer 1 :test)
    (let* ((solutions (query-prolog rulebase '(cyclic-answer ?answer)))
           (answer (solution-binding '?answer (first solutions))))
      (is-equal 1 (length solutions))
      (is (consp answer))
      (is (eq answer (cdr answer)))
      (is-equal 'loop (car answer)))))

(deftest table-declaration-and-clause-retraction-guard-repeat-updates ()
  (let ((rulebase (make-rulebase)))
    (cl-prolog::%add-rulebase-table-declaration!
     rulebase 'repeat-owner 1 :owner)
    (cl-prolog::%add-rulebase-table-declaration!
     rulebase 'repeat-owner 1 :owner)
    (is (cl-prolog::%rulebase-tabled-p rulebase 'repeat-owner 1))
    (cl-prolog::%remove-rulebase-table-declaration!
     rulebase 'repeat-owner 1 :absent-owner)
    (is (cl-prolog::%rulebase-tabled-p rulebase 'repeat-owner 1))
    (cl-prolog::%remove-rulebase-table-declaration!
     rulebase 'repeat-owner 1 :owner)
    (is (not (cl-prolog::%rulebase-tabled-p rulebase 'repeat-owner 1)))
    (rulebase-insert-clause! rulebase (make-clause '(repeat-fact)))
    (let ((entry (first (cl-prolog::rulebase-entries rulebase))))
      (is (cl-prolog::%rulebase-retract-entry! rulebase entry))
      (is (not (cl-prolog::%rulebase-retract-entry! rulebase entry))))))

(deftest left-recursion-through-leading-builtins-and-control-terminates
    (:timeout 2)
  (let ((rulebase
          (prolog
           ((builtin-direct ?x) true (builtin-direct ?x))
           ((builtin-direct direct-base))
           ((builtin-indirect-p ?x) (= ?x ?y) (builtin-indirect-q ?y))
           ((builtin-indirect-p p-base))
           ((builtin-indirect-q ?x) true (builtin-indirect-p ?x))
           ((builtin-indirect-q q-base))
           ((control-direct ?x)
            (call (and true (control-direct ?x))))
           ((control-direct control-base)))))
    (is-equal '(((?x . direct-base)))
              (query-prolog rulebase '(builtin-direct ?x)))
    (is-same-set '(((?x . p-base)) ((?x . q-base)))
                 (query-prolog rulebase '(builtin-indirect-p ?x)))
    (is-equal '(((?x . control-base)))
              (query-prolog rulebase '(control-direct ?x)))))

(deftest builtin-proof-search-inherits-table-session ()
  (let ((*observed-table-session* nil))
    (is-equal '(nil)
              (query-prolog (make-rulebase) '(test-nested-table-session)))
    (is *observed-table-session*)))

(deftest shared-table-session-isolates-rulebase-caches ()
  (let* ((recursive-rulebase
           (prolog
            ((shared-value ?value) (shared-value ?value))
            ((shared-value first))))
         (fact-rulebase
           (prolog
            ((shared-value second))
            ((padding-fact present)))))
    (cl-prolog::%add-rulebase-table-declaration!
     recursive-rulebase 'shared-value 1 :test)
    (cl-prolog::%add-rulebase-table-declaration!
     fact-rulebase 'shared-value 1 :test)
    (is-equal (cl-prolog::rulebase-revision recursive-rulebase)
              (cl-prolog::rulebase-revision fact-rulebase))
    (let* ((session
             (cl-prolog::%make-rulebase-table-session recursive-rulebase))
           (recursive-state
             (cl-prolog::%make-proof-state
              recursive-rulebase
              '()
              (cl-prolog::%make-environment-index '())
              nil
              cl-prolog::+default-prolog-module+
              session
              (cl-prolog::%make-cut-tag)))
           (fact-state
             (cl-prolog::%make-proof-state
              fact-rulebase
              '()
              (cl-prolog::%make-environment-index '())
              nil
              cl-prolog::+default-prolog-module+
              session
              (cl-prolog::%make-cut-tag)))
           (recursive-answers '())
           (fact-answers '()))
      (is (not (eq (cl-prolog::%proof-module-entries recursive-state)
                   (cl-prolog::%proof-module-entries fact-state))))
      (is (cl-prolog::%left-recursive-p '(shared-value ?value)
                                        recursive-state))
      (is (not (cl-prolog::%left-recursive-p '(shared-value ?value)
                                             fact-state)))
      (let ((cl-prolog::*current-table-session* session))
        (cl-prolog::%prove-bindings/k
         '(shared-value ?value) recursive-rulebase '() nil
         (lambda (bindings)
           (push (logic-substitute '?value bindings) recursive-answers)
           (cl-prolog::%prove-bindings/k
            '(shared-value ?value) fact-rulebase '() nil
            (lambda (nested-bindings)
              (push (logic-substitute '?value nested-bindings)
                    fact-answers))))))
      (is-equal '(first) (nreverse recursive-answers))
      (is-equal '(second) (nreverse fact-answers))
      (is-equal 2
                (hash-table-count
                 (cl-prolog::%table-session-module-entries session)))
      (is-equal 2
                (hash-table-count
                 (cl-prolog::%table-session-left-recursion session)))
      (is-equal 2
                (hash-table-count
                 (cl-prolog::%table-session-entries session))))))

(deftest interrupted-table-build-discards-partial-entry ()
  (let* ((rulebase (prolog
                     ((recursive ?x) (recursive ?x))
                     ((recursive value))))
         (session (cl-prolog::%make-rulebase-table-session rulebase))
         (state (cl-prolog::%make-proof-state
  rulebase
  (quote ())
  (cl-prolog::%make-environment-index (quote ()))
  nil
  cl-prolog::+default-prolog-module+
  session
  (cl-prolog::%make-cut-tag))))
    (handler-case
        (cl-prolog::%prove-clauses/k
         '(recursive ?x) state
         (lambda (answer-state)
           (declare (cl:ignore answer-state))
           (error "interrupt table construction")))
      (error () nil))
    (is-equal 0
              (hash-table-count
               (cl-prolog::%table-session-entries session)))))

(deftest table-sessions-do-not-outlive-a-query-or-rulebase-revision ()
  (let ((rulebase (prolog ((value old)))))
    (is-equal '(((?x . old))) (query-prolog rulebase '(value ?x)))
    (rulebase-insert-clause! rulebase (make-clause '(value new)))
    (is-equal '(((?x . old)) ((?x . new)))
              (query-prolog rulebase '(value ?x)))))

(deftest proof-search-falls-back-when-no-constraint-hook-is-installed ()
  "*constraint-post-unify-hook* decouples fact/rule matching and unification
from the finite-domain subsystem (installed only once fd-store.lisp loads);
verify the direct-unification fallback taken by an absent hook still
produces the normal proof-search result."
  (let ((rulebase (prolog ((likes alice bob))
                          ((admires ?x ?y) (fond-of ?x ?y))
                          ((fond-of alice bob))))
        (cl-prolog::*constraint-post-unify-hook* nil))
    (is-equal '(((?y . bob))) (query-prolog rulebase '(likes alice ?y)))
    (is-equal '(((?y . bob))) (query-prolog rulebase '(admires alice ?y)))
    (is-equal '(((?y . bob))) (query-prolog rulebase '(= (alice . ?y) (alice . bob))))))

(deftest static-user-goal-defers-argument-substitution ()
  (let* ((rulebase (prolog ((deferred ready))))
         (goal (quote (deferred ?argument)))
         (bindings (quote ((?argument . ready))))
         (state (cl-prolog::%make-proof-state
                 rulebase
                 bindings
                 (cl-prolog::%make-environment-index bindings)
                 nil
                 cl-prolog::+default-prolog-module+
                 (cl-prolog::%make-rulebase-table-session rulebase)
                 (cl-prolog::%make-cut-tag)))
         (original (symbol-function (quote cl-prolog::%resolve-user-goal)))
         (observed nil)
         (succeeded nil))
    (unwind-protect
         (progn
           (setf (symbol-function (quote cl-prolog::%resolve-user-goal))
                 (lambda (candidate current-state explicit-module)
                   (setf observed candidate)
                   (funcall original candidate current-state explicit-module)))
           (cl-prolog::%prove-goal-dispatch/k
            goal
            state
            (lambda (answer-state)
              (declare (cl:ignore answer-state))
              (setf succeeded t)))
           (is succeeded)
           (is (eq goal observed)))
      (setf (symbol-function (quote cl-prolog::%resolve-user-goal))
            original))))
(deftest rule-program-fast-path-preserves-rule-semantics ()
  (let* ((variable (fresh-logic-variable))
         (eligible
           (cl-prolog::%compile-clause-template
            (make-clause (list (quote fast-same) variable variable)
                         (list (list (quote choice) variable)))))
         (cut-template
           (cl-prolog::%compile-clause-template
            (make-clause (quote (fast-cut)) (quote ((!))))))
         (nested-template
           (cl-prolog::%compile-clause-template
            (make-clause (quote (fast-nested (term value))) (quote ((true)))))))
    (is (cl-prolog::%clause-template-rule-program eligible))
    (is (null (cl-prolog::%clause-template-rule-program cut-template)))
    (is (null (cl-prolog::%clause-template-rule-program nested-template))))
  (let ((rulebase
          (prolog
            ((choice a))
            ((choice b))
            ((fast-pick ?x) (choice ?x))
            ((fast-same ?x ?x) (choice ?x))
            ((left a))
            ((left b))
            ((right a))
            ((right c))
            ((fast-paired ?x) (left ?x) (right ?x)))))
    (is-equal (quote (((?answer . a)) ((?answer . b))))
              (query-prolog rulebase (quote (fast-pick ?answer))))
    (is-equal (quote (nil)) (query-prolog rulebase (quote (fast-same a a))))
    (is (null (query-prolog rulebase (quote (fast-same a b)))))
    (is-equal (quote (((?answer . a))))
              (query-prolog rulebase (quote (fast-paired ?answer))))))

(defun %make-rule-program-equivalence-rulebases ()
  (let* ((variable (fresh-logic-variable))
         (shared-goal (list (quote descriptor-choice) variable))
         (generic-clause
           (make-clause (list (quote descriptor-candidate) variable)
                        (list shared-goal shared-goal)))
         (generic-rulebase
           (prolog
             ((descriptor-choice a))
             ((descriptor-choice b)))))
    (rulebase-insert-clause! generic-rulebase generic-clause)
    (values
     (prolog
       ((descriptor-choice a))
       ((descriptor-choice b))
       ((descriptor-candidate ?x)
        (descriptor-choice ?x)
        (descriptor-choice ?x)))
     generic-rulebase
     (cl-prolog::%compile-clause-template generic-clause))))

(deftest shared-and-cyclic-rule-graphs-use-observationally-equivalent-fallback ()
  (multiple-value-bind (fast-rulebase generic-rulebase generic-template)
      (%make-rule-program-equivalence-rulebases)
    (is (null (cl-prolog::%clause-template-rule-program generic-template)))
    (is-equal
     (query-prolog fast-rulebase (quote (descriptor-candidate ?answer)))
     (query-prolog generic-rulebase (quote (descriptor-candidate ?answer)))))
  (let* ((variable (fresh-logic-variable))
         (goal (list (quote descriptor-choice) variable))
         (cyclic-body (list goal)))
    (setf (cdr cyclic-body) cyclic-body)
    (is
     (null
      (cl-prolog::%clause-template-rule-program
       (cl-prolog::%compile-clause-template
        (make-clause (list (quote cyclic-candidate) variable)
                     cyclic-body)))))))

(deftest constraint-hook-continuation-reentry-matches-generic-fallback ()
  (multiple-value-bind (fast-rulebase generic-rulebase generic-template)
      (%make-rule-program-equivalence-rulebases)
    (declare (ignore generic-template))
    (let ((cl-prolog::*constraint-post-unify-hook*
            (lambda (environment continuation)
              (funcall continuation environment)
              (funcall continuation environment))))
      (let ((fast-solutions
              (query-prolog fast-rulebase
                            (quote (descriptor-candidate ?answer))))
            (generic-solutions
              (query-prolog generic-rulebase
                            (quote (descriptor-candidate ?answer)))))
        (is-equal generic-solutions fast-solutions)
        (is-equal 16 (length fast-solutions))))))

(deftest rule-program-and-fallback-share-logical-update-snapshot-semantics ()
  (labels ((observe-update (rulebase)
             (let ((seen (quote ()))
                   (inserted-p nil))
               (map-prolog-solutions
                (lambda (solution)
                  (push (solution-binding (quote ?answer) solution) seen)
                  (unless inserted-p
                    (setf inserted-p t)
                    (rulebase-insert-clause!
                     rulebase
                     (make-clause (quote (descriptor-choice c))))))
                rulebase
                (quote (descriptor-candidate ?answer)))
               (values
                (nreverse seen)
                (mapcar
                 (lambda (solution)
                   (solution-binding (quote ?answer) solution))
                 (query-prolog
                  rulebase
                  (quote (descriptor-candidate ?answer))))))))
    (multiple-value-bind (fast-rulebase generic-rulebase generic-template)
        (%make-rule-program-equivalence-rulebases)
      (declare (ignore generic-template))
      (multiple-value-bind (fast-current fast-next)
          (observe-update fast-rulebase)
        (multiple-value-bind (generic-current generic-next)
            (observe-update generic-rulebase)
          (is-equal (quote (a b)) fast-current)
          (is-equal fast-current generic-current)
          (is-equal (quote (a b c)) fast-next)
          (is-equal fast-next generic-next))))))

(deftest rule-program-and-fallback-share-depth-boundaries ()
  (multiple-value-bind (fast-rulebase generic-rulebase generic-template)
      (%make-rule-program-equivalence-rulebases)
    (declare (ignore generic-template))
    (let ((fast-solutions
            (query-prolog fast-rulebase
                          (quote (descriptor-candidate ?answer))
                          :max-depth 1))
          (generic-solutions
            (query-prolog generic-rulebase
                          (quote (descriptor-candidate ?answer))
                          :max-depth 1)))
      (is-equal (quote (((?answer . a)) ((?answer . b)))) fast-solutions)
      (is-equal fast-solutions generic-solutions))
    (signals-condition prolog-depth-limit-exceeded
      (query-prolog fast-rulebase
                    (quote (descriptor-candidate ?answer))
                    :max-depth 0))
    (signals-condition prolog-depth-limit-exceeded
      (query-prolog generic-rulebase
                    (quote (descriptor-candidate ?answer))
                    :max-depth 0))))

(deftest flat-fact-rule-program-eligibility ()
  (let* ((variable (fresh-logic-variable))
         (shared-term (list (quote term) (quote value)))
         (cyclic-head (list (quote flat-cycle) (quote value)))
         (ground-template
           (cl-prolog::%compile-clause-template
            (make-clause (quote (flat-ground value)))))
         (variable-template
           (cl-prolog::%compile-clause-template
            (make-clause (list (quote flat-variable) variable variable))))
         (nested-template
           (cl-prolog::%compile-clause-template
            (make-clause (quote (flat-nested (term value))))))
         (improper-template
           (cl-prolog::%compile-clause-template
            (make-clause (cons (quote flat-improper) (quote tail)))))
         (shared-template
           (cl-prolog::%compile-clause-template
            (make-clause
             (list (quote flat-shared) shared-term shared-term))))
         (variable-predicate-template
           (cl-prolog::%compile-clause-template
            (make-clause (list variable (quote value))))))
    (setf (cddr cyclic-head) cyclic-head)
    (let* ((cyclic-template
             (cl-prolog::%compile-clause-template
              (make-clause cyclic-head)))
           (ground-program
             (cl-prolog::%clause-template-rule-program ground-template))
           (variable-program
             (cl-prolog::%clause-template-rule-program variable-template)))
      (is ground-program)
      (is (typep (cl-prolog::%rule-program-body ground-program)
                 (quote simple-vector)))
      (is-equal 0
                (length (cl-prolog::%rule-program-body ground-program)))
      (is-equal 0
                (cl-prolog::%rule-program-variable-count ground-program))
      (is variable-program)
      (is-equal 1
                (cl-prolog::%rule-program-variable-count variable-program))
      (is-equal 0
                (length (cl-prolog::%rule-program-body variable-program)))
      (is (null (cl-prolog::%clause-template-rule-program nested-template)))
      (is (null (cl-prolog::%clause-template-rule-program improper-template)))
      (is (null (cl-prolog::%clause-template-rule-program shared-template)))
      (is (null
           (cl-prolog::%clause-template-rule-program
            variable-predicate-template)))
      (is (null (cl-prolog::%clause-template-rule-program cyclic-template))))))
(deftest flat-fact-rule-program-preserves-runtime-semantics ()
  (let ((rulebase
          (prolog
            ((flat-choice first))
            ((flat-choice second))
            ((flat-choice first extra))
            ((flat-other first other))
            ((flat-any ?value))
            ((flat-same ?value ?value)))))
    (is-equal (quote (((?answer . first)) ((?answer . second))))
              (query-prolog rulebase (quote (flat-choice ?answer))))
    (is (null (query-prolog rulebase (quote (flat-choice first second)))))
    (is (null (query-prolog rulebase (quote (flat-other first second)))))
    (is-equal (quote (nil))
              (query-prolog rulebase
                            (quote (flat-choice first))
                            :max-depth 0))
    (is-equal (quote (nil))
              (query-prolog rulebase (quote (flat-same same same))))
    (is (null (query-prolog rulebase (quote (flat-same left right)))))
    (is
     (prolog-succeeds-p
      rulebase
      (quote
       (and (flat-any ?left)
            (= ?left left)
            (flat-any ?right)
            (= ?right right)))))))
(deftest flat-fact-rule-program-preserves-hook-and-snapshot-semantics ()
  (let ((hook-count 0)
        (rulebase (prolog ((flat-hook value)))))
    (let ((cl-prolog::*constraint-post-unify-hook*
            (lambda (environment continuation)
              (incf hook-count)
              (funcall continuation environment)
              (funcall continuation environment))))
      (is-equal (quote (((?answer . value)) ((?answer . value))))
                (query-prolog rulebase (quote (flat-hook ?answer))))
      (is-equal 1 hook-count)))
  (let ((rulebase (prolog ((flat-update first)) ((flat-update second))))
        (current (quote ()))
        (inserted-p nil))
    (map-prolog-solutions
     (lambda (solution)
       (push (solution-binding (quote ?answer) solution) current)
       (unless inserted-p
         (setf inserted-p t)
         (rulebase-insert-clause!
          rulebase
          (make-clause (quote (flat-update third))))))
     rulebase
     (quote (flat-update ?answer)))
    (is-equal (quote (first second)) (nreverse current))
    (is-equal (quote (((?answer . first))
                       ((?answer . second))
                       ((?answer . third))))
              (query-prolog rulebase (quote (flat-update ?answer))))))
