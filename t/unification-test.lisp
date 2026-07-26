;;;; Unification protocol tests.
(in-package #:cl-prolog.tests)

(deftest-unification
  unification-protocol
  (:substitute (pair ?x ?y) (pair left right) :expected (pair left right))
  (:fails (tag a) (tag b))
  (:not-ok ?x (wrap ?x))
  (:not-ok (wrap ?x) ?x)
  (:ok "same" "same")
  (:ok 7 7)
  (:not-ok 7 8)
  (:substitute
    (:outer (:inner . ?side) ?side)
    (:outer (:inner . :buy) ?other)
    :expected
    (:outer (:inner . :buy) :buy))
  (:substitute ?x ?y :initial-env ((?y . done)) :expected done))

(deftest
  cyclic-unification-and-substitution-terminate
  ()
  (let ((left (cons 'node nil))
        (right (cons 'node nil))
        (different (cons 'other nil)))
    (setf (cdr left) left
          (cdr right) right
          (cdr different) different)
    (is (nth-value 1 (unify left right)))
    (is (not (nth-value 1 (unify left different))))
    (let ((copy (logic-substitute left nil)))
      (is (not (eq copy left)))
      (is (eq copy (cdr copy)))))
  (let* ((existing (fresh-logic-variable "?EXISTING"))
         (new (fresh-logic-variable "?NEW"))
         (environment (list (cons existing 'bound))))
    (multiple-value-bind (extended ok) (unify new 'value environment)
      (is ok)
      (is (eq 'value (cdr (assoc new extended :test (function eq)))))
      (is (eq 'bound (cdr (assoc existing extended :test (function eq))))))))

(deftest
  cyclic-substitution-preserves-sharing-and-variables
  ()
  (let* ((variable (fresh-logic-variable "?CYCLE"))
         (shared (cons variable nil))
         (root (cons shared shared)))
    (setf (cdr shared) shared)
    (is (cl-prolog::%term-has-variables-p root))
    (let ((copy (logic-substitute root nil)))
      (is (eq (car copy) (cdr copy)))
      (is (eq (car copy) (cdr (car copy))))
      (is (eq variable (car (car copy)))))))

(progn
(progn
  (deftest
    cyclic-variable-scan-and-query-collection-terminate
    ()
    (let ((ground-cycle (cons 'ground nil))
          (query-cycle (cons '?x nil)))
      (setf (cdr ground-cycle) ground-cycle
            (cdr query-cycle) query-cycle)
      (is (not (cl-prolog::%term-has-variables-p ground-cycle)))
      (is-equal '(?x) (cl-prolog::%collect-query-variables query-cycle))))
  (deftest
    question-prefixed-atoms-do-not-unify-as-variables
    ()
    (let ((atom (read-prolog-term "'?x'.")))
      (is (not (logic-var-p atom)))
      (is (not (nth-value 1 (unify atom 'cl-prolog::a))))
      (is (nth-value 1 (unify atom atom)))))
  (deftest
    indexed-alias-chain-terminates-with-linear-lookup
    (:timeout 3)
    (let* ((variables
          (loop repeat 50001
                collect (fresh-logic-variable "?CHAIN")))
           (environment
          (loop for tail on variables
                for variable = (car tail)
                for value = (if (cdr tail) (cadr tail)
              :resolved)
                collect (cons variable value)))
           (start (car variables)))
      (is (eq :resolved (cl-prolog::%walk-term start environment)))
      (is (eq :resolved (logic-substitute start environment)))
      (multiple-value-bind (extended ok) (unify start :resolved environment)
        (is ok)
        (is (eq extended environment)))))
  (deftest
    duplicate-bindings-preserve-first-binding
    ()
    (let* ((variable (fresh-logic-variable "?DUPLICATE"))
           (environment (list (cons variable nil) (cons variable :ignored))))
      (is (null (cl-prolog::%walk-term variable environment)))
      (is (null (logic-substitute variable environment)))
      (multiple-value-bind (extended ok) (unify variable nil environment)
        (is ok)
        (is (eq extended environment)))))
  (deftest
    alias-cycle-operations-terminate
    (:timeout 2)
    (let* ((x (fresh-logic-variable "?CYCLE-X"))
           (y (fresh-logic-variable "?CYCLE-Y"))
           (z (fresh-logic-variable "?CYCLE-Z"))
           (entry (fresh-logic-variable "?CYCLE-ENTRY"))
           (unbound (fresh-logic-variable "?UNBOUND"))
           (self-environment (list (cons x x)))
           (cycle-environment (list (cons x y) (cons y x)))
           (three-cycle-environment (list (cons x y) (cons y z) (cons z x)))
           (chain-into-cycle-environment
          (list (cons entry y) (cons x y) (cons y z) (cons z x)))
           (nil-terminal-environment (list (cons entry nil))))
      (is (eq unbound (cl-prolog::%walk-term unbound nil)))
      (is (null (cl-prolog::%walk-term entry nil-terminal-environment)))
      (is (eq x (cl-prolog::%walk-term x self-environment)))
      (is (eq x (cl-prolog::%walk-term x cycle-environment)))
      (is (eq x (cl-prolog::%walk-term y cycle-environment)))
      (is (eq x (cl-prolog::%walk-term y three-cycle-environment)))
      (is (eq x (cl-prolog::%walk-term entry chain-into-cycle-environment)))
      (is (eq x (logic-substitute y cycle-environment)))
      (is (cl-prolog::%occurs-p x y cycle-environment))
      (multiple-value-bind (extended ok) (unify x y cycle-environment)
        (is ok)
        (is (eq extended cycle-environment)))
      (multiple-value-bind (extended ok) (unify x :resolved cycle-environment)
        (is ok)
        (is (eq (cdr extended) cycle-environment))
        (is (eq :resolved (logic-substitute x extended)))
        (is (eq :resolved (logic-substitute y extended))))
      (is (eq x (cl-prolog::%walk-term x cycle-environment)))))
  (deftest
    indexed-unification-updates-environment-order
    ()
    (let ((left-variable (fresh-logic-variable "?LEFT"))
          (right-variable (fresh-logic-variable "?RIGHT")))
      (multiple-value-bind (environment ok) (unify (list left-variable left-variable) (list right-variable :done))
        (is ok)
        (is (eq right-variable (caar environment)))
        (is (eq :done (cdar environment)))
        (is (eq left-variable (caadr environment)))
        (is (eq right-variable (cdadr environment)))
        (is (eq :done (logic-substitute left-variable environment)))
        (is (eq :done (logic-substitute right-variable environment))))))
  (deftest
    occurs-check-and-input-environment-remain-persistent
    ()
    (let* ((x (fresh-logic-variable "?OCCURS-X"))
           (y (fresh-logic-variable "?OCCURS-Y"))
           (z (fresh-logic-variable "?PERSISTENT"))
           (binding (cons y x))
           (environment (list binding))
           (term (list 'node y)))
      (multiple-value-bind (extended ok) (unify x term environment)
        (is (not ok))
        (is (null extended)))
      (is (eq binding (car environment)))
      (is (eq x (cdar environment)))
      (multiple-value-bind (extended ok) (unify z :resolved environment)
        (is ok)
        (is (eq environment (cdr extended)))
        (is (eq binding (car environment))))
      (is (eq binding (car environment)))
      (is (eq x (cdar environment)))))
  (progn
  (deftest
      indexed-substitution-preserves-cyclic-cons-sharing
      ()
      (let* ((variable (fresh-logic-variable "?SHARED"))
             (shared (cons variable nil))
             (root (cons shared shared))
             (environment (list (cons variable :resolved))))
        (setf (cdr shared) shared)
        (let ((copy (logic-substitute root environment)))
          (is (not (eq copy root)))
          (is (eq (car copy) (cdr copy)))
          (is (eq :resolved (car (car copy))))
          (is (eq (car copy) (cdr (car copy)))))))
  (deftest
      indexed-substitution-root-fast-path-preserves-semantics
      ()
      (let* ((unbound (fresh-logic-variable "?ROOT-UNBOUND"))
             (alias (fresh-logic-variable "?ROOT-ALIAS"))
             (atom-alias (fresh-logic-variable "?ROOT-ATOM"))
             (cycle-x (fresh-logic-variable "?ROOT-CYCLE-X"))
             (cycle-y (fresh-logic-variable "?ROOT-CYCLE-Y"))
             (empty-index (cl-prolog::%make-environment-index nil))
             (alias-index
               (cl-prolog::%make-environment-index
                 (list (cons alias unbound))))
             (atom-index
               (cl-prolog::%make-environment-index
                 (list (cons atom-alias :resolved))))
             (cycle-index
               (cl-prolog::%make-environment-index
                 (list (cons cycle-x cycle-y)
                       (cons cycle-y cycle-x)))))
        (is (eq unbound
                (cl-prolog::%logic-substitute-indexed
                  unbound empty-index)))
        (is (eq unbound
                (cl-prolog::%logic-substitute-indexed
                  alias alias-index)))
        (is (eq :resolved
                (cl-prolog::%logic-substitute-indexed
                  atom-alias atom-index)))
        (is (eq cycle-x
                (cl-prolog::%logic-substitute-indexed
                  cycle-y cycle-index)))
        (let* ((shared (cons :shared :tail))
               (root (cons shared shared))
               (copy
                 (cl-prolog::%logic-substitute-indexed root empty-index)))
          (is (not (eq copy root)))
          (is (eq (car copy) (cdr copy)))
          (is (not (eq (car copy) shared))))
        (let* ((dotted (cons :left :right))
               (copy
                 (cl-prolog::%logic-substitute-indexed dotted empty-index)))
          (is (not (eq copy dotted)))
          (is (eq :left (car copy)))
          (is (eq :right (cdr copy))))
        (let ((cyclic (cons :root nil)))
          (setf (cdr cyclic) cyclic)
          (let ((copy
                  (cl-prolog::%logic-substitute-indexed
                    cyclic empty-index)))
            (is (not (eq copy cyclic)))
            (is (eq copy (cdr copy)))))
        (let* ((variable (fresh-logic-variable "?ROOT-BOUND-CYCLE"))
               (cyclic (cons :bound nil)))
          (setf (cdr cyclic) cyclic)
          (let* ((index
                   (cl-prolog::%make-environment-index
                     (list (cons variable cyclic))))
                 (copy
                   (cl-prolog::%logic-substitute-indexed variable index)))
            (is (not (eq copy cyclic)))
            (is (eq :bound (car copy)))
            (is (eq copy (cdr copy)))))))))
(progn
  (deftest environment-index-overlay-preserves-parent-and-siblings ()
    (let* ((parent-variable (fresh-logic-variable "?PARENT"))
           (left-variable (fresh-logic-variable "?LEFT-CHILD"))
           (right-variable (fresh-logic-variable "?RIGHT-CHILD"))
           (parent-environment (list (cons parent-variable :parent)))
           (parent-index
             (cl-prolog::%make-environment-index parent-environment)))
      (multiple-value-bind (left-environment left-ok left-index)
          (cl-prolog::%unify-indexed
            left-variable
            :left
            parent-environment
            parent-index)
        (declare (ignore left-environment))
        (is left-ok)
        (multiple-value-bind (right-environment right-ok right-index)
            (cl-prolog::%unify-indexed
              right-variable
              :right
              parent-environment
              parent-index)
          (declare (ignore right-environment))
          (is right-ok)
          (is (not (eq parent-index left-index)))
          (is (not (eq parent-index right-index)))
          (is
            (eq (cl-prolog::%environment-index-table parent-index)
                (cl-prolog::%environment-index-table left-index)))
          (is
            (eq (cl-prolog::%environment-index-table parent-index)
                (cl-prolog::%environment-index-table right-index)))
          (is
            (= 0
               (cl-prolog::%environment-index-overlay-length
                 parent-index)))
          (is
            (= 1
               (cl-prolog::%environment-index-overlay-length left-index)))
          (is
            (= 1
               (cl-prolog::%environment-index-overlay-length right-index)))
          (is
            (eq :left
                (car
                  (cl-prolog::%environment-index-entry
                    left-variable
                    left-index))))
          (is
            (eq :right
                (car
                  (cl-prolog::%environment-index-entry
                    right-variable
                    right-index))))
          (multiple-value-bind (entry present-p)
              (cl-prolog::%environment-index-entry
                right-variable
                left-index)
            (declare (ignore entry))
            (is (not present-p)))
          (multiple-value-bind (entry present-p)
              (cl-prolog::%environment-index-entry
                left-variable
                right-index)
            (declare (ignore entry))
            (is (not present-p)))
          (multiple-value-bind (entry present-p)
              (cl-prolog::%environment-index-entry
                left-variable
                parent-index)
            (declare (ignore entry))
            (is (not present-p)))))))
  (deftest environment-index-overlay-rolls-back-failed-unification ()
    (let* ((variable (fresh-logic-variable "?ROLLBACK"))
           (parent-index (cl-prolog::%make-environment-index nil)))
      (multiple-value-bind (environment ok result-index)
          (cl-prolog::%unify-indexed
            (list variable variable)
            (list :first :second)
            nil
            parent-index)
        (is (null environment))
        (is (not ok))
        (is (eq parent-index result-index))
        (is
          (= 0
             (cl-prolog::%environment-index-overlay-length parent-index)))
        (multiple-value-bind (entry present-p)
            (cl-prolog::%environment-index-entry variable parent-index)
          (declare (ignore entry))
          (is (not present-p))))))
  (deftest environment-index-compaction-preserves-ranks-and-cycle-choice ()
    (let* ((x (fresh-logic-variable "?COMPACT-X"))
           (y (fresh-logic-variable "?COMPACT-Y"))
           (z (fresh-logic-variable "?COMPACT-Z"))
           (fillers
             (loop repeat 5
                   collect (fresh-logic-variable "?COMPACT-FILLER")))
           (bindings
             (append
               (list (cons x y) (cons y z) (cons z x))
               (loop for filler in fillers
                     collect (cons filler :filler))))
           (base-index (cl-prolog::%make-environment-index nil))
           (compacted
             (cl-prolog::%extend-environment-index
               base-index
               bindings)))
      (is (= 8 (length bindings)))
      (is
        (= 0
           (cl-prolog::%environment-index-overlay-length compacted)))
      (is
        (not
          (eq (cl-prolog::%environment-index-table base-index)
              (cl-prolog::%environment-index-table compacted))))
      (is
        (= -1
           (cdr (cl-prolog::%environment-index-entry x compacted))))
      (is
        (= -2
           (cdr (cl-prolog::%environment-index-entry y compacted))))
      (is
        (= -3
           (cdr (cl-prolog::%environment-index-entry z compacted))))
      (is (eq z (cl-prolog::%walk-term-indexed x compacted)))))
  (deftest environment-index-after-bindings-distinguishes-prefix-and-rebuild ()
    (let* ((variable (fresh-logic-variable "?PREFIX"))
           (parent-environment (list (cons variable :base)))
           (parent-index
             (cl-prolog::%make-environment-index parent-environment))
           (older-binding (cons variable :older))
           (newest-binding (cons variable :newest))
           (bindings
             (cons newest-binding
                   (cons older-binding parent-environment)))
           (extended
             (cl-prolog::%environment-index-after-bindings
               bindings
               parent-environment
               parent-index))
           (rebuilt
             (cl-prolog::%environment-index-after-bindings
               (copy-tree bindings)
               parent-environment
               parent-index)))
      (is
        (eq parent-index
            (cl-prolog::%environment-index-after-bindings
              parent-environment
              parent-environment
              parent-index)))
      (is
        (= 2
           (cl-prolog::%environment-index-overlay-length extended)))
      (is
        (eq :newest
            (car
              (cl-prolog::%environment-index-entry variable extended))))
      (is
        (= -2
           (cdr
             (cl-prolog::%environment-index-entry variable extended))))
      (is
        (eq :base
            (car
              (cl-prolog::%environment-index-entry
                variable
                parent-index))))
      (is
        (= 0
           (cl-prolog::%environment-index-overlay-length rebuilt)))
      (is
        (not
          (eq (cl-prolog::%environment-index-table parent-index)
              (cl-prolog::%environment-index-table rebuilt))))
      (is
        (eq :newest
            (car
              (cl-prolog::%environment-index-entry variable rebuilt))))))
  (deftest environment-index-long-alias-chain-keeps-overlay-bounded
    (:timeout 5)
    (let* ((variables
             (loop repeat 50001
                   collect (fresh-logic-variable "?BOUNDED-CHAIN")))
           (environment
             (loop for tail on variables
                   for variable = (car tail)
                   for value = (if (cdr tail) (cadr tail) :resolved)
                   collect (cons variable value)))
           (index (cl-prolog::%make-environment-index environment))
           (maximum-overlay-length 0))
      (is
        (eq :resolved
            (cl-prolog::%walk-term-indexed (car variables) index)))
      (loop repeat 17
            for variable = (fresh-logic-variable "?OVERLAY-BOUND")
            do (setf index
                     (cl-prolog::%extend-environment-index
                       index
                       (list (cons variable :bound))))
               (setf maximum-overlay-length
                     (max
                       maximum-overlay-length
                       (cl-prolog::%environment-index-overlay-length
                         index)))
               (is
                 (< (cl-prolog::%environment-index-overlay-length index)
                    cl-prolog::+environment-index-overlay-threshold+)))
      (is (= 7 maximum-overlay-length))
      (is
        (eq :resolved
            (cl-prolog::%walk-term-indexed (car variables) index)))))))

(progn
  (deftest
    freshen-term-preserves-cyclic-conses
    ()
    (let ((variable (fresh-logic-variable "?CYCLE"))
          (cycle (cons nil nil)))
      (setf (car cycle) variable
            (cdr cycle) cycle)
      (let ((copy
              (cl-prolog::%freshen-term
                cycle
                (make-hash-table :test (function eq)))))
        (is (not (eq copy cycle)))
        (is (eq copy (cdr copy)))
        (is (logic-var-p (car copy)))
        (is (not (eq variable (car copy))))
        (is (eq variable (car cycle)))
        (is (eq cycle (cdr cycle))))))
  (deftest
    freshen-term-preserves-dotted-lists-and-two-argument-calls
    ()
    (let* ((variable (fresh-logic-variable "?DOTTED"))
           (term (cons variable :tail))
           (copy
             (cl-prolog::%freshen-term
               term
               (make-hash-table :test (function eq)))))
      (is (not (eq copy term)))
      (is (logic-var-p (car copy)))
      (is (not (eq variable (car copy))))
      (is (eq :tail (cdr copy)))
      (is (eq variable (car term)))
      (is (eq :tail (cdr term)))))
  (deftest
    freshen-term-preserves-proper-list-variable-identity
    ()
    (let* ((variable (fresh-logic-variable "?PROPER"))
           (term (list :pair variable variable))
           (copy
             (cl-prolog::%freshen-term
               term
               (make-hash-table :test (function eq)))))
      (is (not (eq copy term)))
      (is (logic-var-p (second copy)))
      (is (eq (second copy) (third copy)))
      (is (not (eq variable (second copy))))
      (is (eq variable (second term)))
      (is (eq variable (third term)))))
  (deftest
    freshen-term-honors-prebound-variable-in-cyclic-graph
    ()
    (let ((source-variable (fresh-logic-variable "?SOURCE"))
          (bound-variable (fresh-logic-variable "?BOUND"))
          (cycle (cons nil nil))
          (table (make-hash-table :test (function eq))))
      (setf (car cycle) source-variable
            (cdr cycle) cycle
            (gethash source-variable table) bound-variable)
      (let ((copy (cl-prolog::%freshen-term cycle table)))
        (is (not (eq copy cycle)))
        (is (eq copy (cdr copy)))
        (is (eq bound-variable (car copy)))
        (is (eq source-variable (car cycle)))
        (is (eq cycle (cdr cycle))))))
  (deftest
    freshening-map-upgrades-to-eq-hash-table
    ()
    (let* ((mapping (cl-prolog::%make-freshening-map))
           (keys
             (loop repeat (1+ cl-prolog::+freshening-map-threshold+)
                   collect (cons nil nil))))
      (loop for key in keys
            for value from 0
            do (cl-prolog::%freshening-map-insert key value mapping))
      (let ((table (cl-prolog::%freshening-map-table mapping)))
        (is (hash-table-p table))
        (is (eq (hash-table-test table) (quote eq)))
        (is (null (cl-prolog::%freshening-map-entries mapping)))
        (loop for key in keys
              for expected from 0
              do (multiple-value-bind (actual present-p)
                     (cl-prolog::%freshening-map-lookup key mapping)
                   (is present-p)
                   (is (= expected actual)))))))
  (deftest
    freshen-clause-preserves-shared-cons-and-variable-identity
    ()
    (let* ((variable (fresh-logic-variable "?SHARED"))
           (shared (cons variable :shared-tail))
           (head (list (quote head) shared variable))
           (body-goal (list (quote body) shared variable))
           (body (list body-goal))
           (clause (make-clause head body))
           (fresh-clause (cl-prolog::%freshen-clause clause))
           (fresh-head (clause-head fresh-clause))
           (fresh-goal (first (clause-body fresh-clause)))
           (fresh-shared (second fresh-head))
           (fresh-variable (third fresh-head)))
      (is (not (eq fresh-clause clause)))
      (is (not (eq fresh-shared shared)))
      (is (eq fresh-shared (second fresh-goal)))
      (is (eq fresh-variable (third fresh-goal)))
      (is (eq fresh-variable (car fresh-shared)))
      (is (not (eq fresh-variable variable)))
      (is (eq :shared-tail (cdr fresh-shared)))
      (is (eq head (clause-head clause)))
      (is (eq body (clause-body clause)))
      (is (eq shared (second head)))
      (is (eq shared (second body-goal)))
      (is (eq variable (third head)))
      (is (eq variable (car shared)))
      (is (eq :shared-tail (cdr shared)))))
  (deftest
    freshen-clause-isolates-attempts
    ()
    (let* ((variable (fresh-logic-variable "?ATTEMPT"))
           (shared (cons variable :shared-tail))
           (clause
             (make-clause
               (list (quote head) shared variable)
               (list (list (quote body) shared variable))))
           (first-clause (cl-prolog::%freshen-clause clause))
           (second-clause (cl-prolog::%freshen-clause clause))
           (first-head (clause-head first-clause))
           (second-head (clause-head second-clause))
           (first-goal (first (clause-body first-clause)))
           (second-goal (first (clause-body second-clause))))
      (is (eq (second first-head) (second first-goal)))
      (is (eq (third first-head) (third first-goal)))
      (is (eq (third first-head) (car (second first-head))))
      (is (eq (second second-head) (second second-goal)))
      (is (eq (third second-head) (third second-goal)))
      (is (eq (third second-head) (car (second second-head))))
      (is (not (eq (second first-head) (second second-head))))
      (is (not (eq (third first-head) (third second-head)))))) )

(progn (progn
  (deftest
    unification-scratch-keeps-directed-pairs
    ()
    (let* ((scratch (cl-prolog::%make-unification-scratch))
           (left (cons :left nil))
           (right (cons :right nil)))
      (is (not (cl-prolog::%unification-scratch-remember-pair scratch left right)))
      (is (cl-prolog::%unification-scratch-remember-pair scratch left right))
      (is (not (cl-prolog::%unification-scratch-remember-pair scratch right left)))
      (is (= 2 (cl-prolog::%unification-scratch-pair-count scratch)))
      (cl-prolog::%reset-unification-scratch scratch)))
  (deftest
    unification-scratch-migrates-and-resets
    ()
    (let* ((scratch (cl-prolog::%make-unification-scratch))
           (lefts
          (loop repeat 33
                collect (cons nil nil)))
           (rights
          (loop repeat 33
                collect (cons nil nil))))
      (loop for left in lefts
            for right in rights
            for expected-count from 1
            do (is (not (cl-prolog::%unification-scratch-remember-pair scratch left right))) (is (= expected-count (cl-prolog::%unification-scratch-pair-count scratch))))
      (is (cl-prolog::%unification-scratch-hash-mode-p scratch))
      (is (= 33 (cl-prolog::%unification-scratch-pair-count scratch)))
      (is
        (cl-prolog::%unification-scratch-remember-pair
          scratch
          (first lefts)
          (first rights)))
      (is
        (cl-prolog::%unification-scratch-remember-pair
          scratch
          (car (last lefts))
          (car (last rights))))
      (let ((pairs (cl-prolog::%unification-scratch-pairs scratch))
            (table (cl-prolog::%unification-scratch-pair-table scratch)))
        (cl-prolog::%reset-unification-scratch scratch)
        (is (zerop (cl-prolog::%unification-scratch-pair-count scratch)))
        (is (not (cl-prolog::%unification-scratch-hash-mode-p scratch)))
        (is (not (cl-prolog::%unification-scratch-active-p scratch)))
        (is (notany (function identity) pairs))
        (is (zerop (hash-table-count table)))
        (is
          (not
            (cl-prolog::%unification-scratch-remember-pair
              scratch
              (cons :fresh nil)
              (cons :fresh nil))))
        (is (= 1 (cl-prolog::%unification-scratch-pair-count scratch)))
        (is (not (cl-prolog::%unification-scratch-hash-mode-p scratch)))
        (cl-prolog::%reset-unification-scratch scratch))))
  (deftest
    cyclic-unification-scratch-success-and-failure
    ()
    (let ((left (cons :node nil))
          (right (cons :node nil))
          (different (cons :different nil)))
      (setf (cdr left) left
            (cdr right) right
            (cdr different) different)
      (is (nth-value 1 (unify left right)))
      (is (not (nth-value 1 (unify left different))))))
  (deftest
    shared-dag-unification-scratch-success-and-failure
    ()
    (let* ((left-leaf (list :leaf))
           (right-leaf (list :leaf))
           (different-leaf (list :different))
           (left (list left-leaf left-leaf))
           (right (list right-leaf right-leaf))
           (different (list different-leaf different-leaf)))
      (is (nth-value 1 (unify left right)))
      (is (not (nth-value 1 (unify left different))))))
  (deftest
    unification-scratch-cleans-up-after-condition-and-nonlocal-exit
    ()
    (let* ((scratch (cl-prolog::%make-unification-scratch))
           (variable (fresh-logic-variable "?SCRATCH-EXIT")))
      (let ((cl-prolog::*unification-scratch* scratch))
        (is
          (eq
            :escaped
            (cl:catch (quote scratch-exit)
              (handler-bind ((type-error
                    (lambda (condition)
                      (declare (ignore condition))
                      (cl:throw (quote scratch-exit) :escaped))))
                (cl-prolog::%unify-indexed (list variable) (list :value) nil nil))
              :missed))))
      (is (not (cl-prolog::%unification-scratch-active-p scratch)))
      (is (zerop (cl-prolog::%unification-scratch-pair-count scratch)))
      (is
        (notany
          (function identity)
          (subseq (cl-prolog::%unification-scratch-pairs scratch) 0 2)))))
  (deftest
    nested-query-roots-use-independent-unification-scratches
    ()
    (let ((outer-scratch nil)
          (inner-scratch nil))
      (map-prolog-solutions
        (lambda (outer-solution)
          (declare (ignore outer-solution))
          (setf outer-scratch cl-prolog::*unification-scratch*)
          (map-prolog-solutions
            (lambda (inner-solution)
              (declare (ignore inner-solution))
              (setf inner-scratch cl-prolog::*unification-scratch*)
              (is (not (eq outer-scratch inner-scratch))))
            (make-rulebase)
            (quote (true)))
          (is (eq outer-scratch cl-prolog::*unification-scratch*)))
        (make-rulebase)
        (quote (true)))
      (is outer-scratch)
      (is inner-scratch)
      (is (not (eq outer-scratch inner-scratch)))
      (is (not (cl-prolog::%unification-scratch-active-p outer-scratch)))
      (is (not (cl-prolog::%unification-scratch-active-p inner-scratch)))
      (is (zerop (cl-prolog::%unification-scratch-pair-count outer-scratch)))
      (is (zerop (cl-prolog::%unification-scratch-pair-count inner-scratch)))))
  (deftest
    active-unification-scratch-uses-temporary-reentrant-scratch
    ()
    (let* ((scratch (cl-prolog::%make-unification-scratch))
           (marker-left (cons :marker-left nil))
           (marker-right (cons :marker-right nil))
           (left (cons :node nil))
           (right (cons :node nil)))
      (setf (cdr left) left
            (cdr right) right)
      (cl-prolog::%unification-scratch-remember-pair scratch marker-left marker-right)
      (setf (cl-prolog::%unification-scratch-active-p scratch) t)
      (let ((cl-prolog::*unification-scratch* scratch))
        (is
          (nth-value
            1
            (cl-prolog::%unify-indexed
              left
              right
              nil
              (cl-prolog::%make-environment-index nil)))))
      (is (cl-prolog::%unification-scratch-active-p scratch))
      (is (= 1 (cl-prolog::%unification-scratch-pair-count scratch)))
      (is (eq marker-left (svref (cl-prolog::%unification-scratch-pairs scratch) 0)))
      (is (eq marker-right (svref (cl-prolog::%unification-scratch-pairs scratch) 1)))
      (setf (cl-prolog::%unification-scratch-active-p scratch) nil)
      (cl-prolog::%reset-unification-scratch scratch)))
  (deftest
    active-hash-mode-unification-scratch-preserves-parent-state
    ()
    (let* ((scratch (cl-prolog::%make-unification-scratch))
           (pairs
          (loop for index below 33
                collect (cons (cons :left index) (cons :right index)))))
      (dolist (pair pairs)
        (cl-prolog::%unification-scratch-remember-pair scratch (car pair) (cdr pair)))
      (let ((pair-vector (cl-prolog::%unification-scratch-pairs scratch))
            (pair-table (cl-prolog::%unification-scratch-pair-table scratch))
            (left (cons :node nil))
            (right (cons :node nil)))
        (setf (cdr left) left
              (cdr right) right
              (cl-prolog::%unification-scratch-active-p scratch) t)
        (let ((cl-prolog::*unification-scratch* scratch))
          (is
            (nth-value
              1
              (cl-prolog::%unify-indexed
                left
                right
                nil
                (cl-prolog::%make-environment-index nil)))))
        (is (cl-prolog::%unification-scratch-active-p scratch))
        (is (cl-prolog::%unification-scratch-hash-mode-p scratch))
        (is (= 33 (cl-prolog::%unification-scratch-pair-count scratch)))
        (is (eq pair-vector (cl-prolog::%unification-scratch-pairs scratch)))
        (is (eq pair-table (cl-prolog::%unification-scratch-pair-table scratch)))
        (dolist (pair pairs)
          (is
            (cl-prolog::%unification-scratch-remember-pair scratch (car pair) (cdr pair))))
        (is (= 33 (cl-prolog::%unification-scratch-pair-count scratch)))
        (setf (cl-prolog::%unification-scratch-active-p scratch) nil)
        (cl-prolog::%reset-unification-scratch scratch))))
  #+sb-thread
  (deftest concurrent-query-roots-use-thread-local-unification-scratches ()
    (let* ((thread-count 4)
           (ready (sb-thread:make-semaphore :count 0))
           (release (sb-thread:make-semaphore :count 0))
           (results (make-array thread-count :initial-element nil))
           (threads
             (loop for index below thread-count collect
                   (let ((slot index))
                     (sb-thread:make-thread
                       (lambda ()
                         (let ((observed nil) (consistent-p t))
                           (map-prolog-solutions
                             (lambda (solution)
                               (declare (ignore solution))
                               (setf observed cl-prolog::*unification-scratch*)
                               (sb-thread:signal-semaphore ready)
                               (sb-thread:wait-on-semaphore release)
                               (setf consistent-p (eq observed cl-prolog::*unification-scratch*)))
                             (make-rulebase) (quote (true)))
                           (setf (aref results slot)
                                 (list observed consistent-p
                                       (not (cl-prolog::%unification-scratch-active-p observed))
                                       (zerop (cl-prolog::%unification-scratch-pair-count observed)))))))))))
      (is (sb-thread:wait-on-semaphore ready :n thread-count :timeout 5))
      (sb-thread:signal-semaphore release thread-count)
      (dolist (thread threads) (sb-thread:join-thread thread))
      (let ((scratches (loop for result across results collect (first result))))
        (is (every (function identity) scratches))
        (is (= thread-count (length (remove-duplicates scratches :test (function eq)))))
        (loop for result across results do (is (second result)) (is (third result)) (is (fourth result))))))
  #-sb-thread
  (deftest concurrent-query-roots-are-skipped-without-sb-thread ()
    (is (not (member :sb-thread *features*))))
  (deftest
    deep-cyclic-unification-crosses-scratch-inline-capacity
    ()
    (labels ((make-cycle (different-index)
               (let ((nodes (make-array 40)))
            (dotimes (index 40)
              (setf (aref nodes index) (cons
                  (if (eql index different-index) :different
                    :node)
                  nil)))
            (dotimes (index 40)
              (setf (cdr (aref nodes index)) (aref nodes (mod (1+ index) 40))))
            (aref nodes 0))))
      (let ((left (make-cycle nil))
            (matching (make-cycle nil))
            (different (make-cycle 39)))
        (is (nth-value 1 (unify left matching)))
        (is (not (nth-value 1 (unify left different)))))))) (deftest compiled-clause-template-preserves-alias-dag-cycle-and-improper-terms () (let* ((variable (fresh-logic-variable)) (shared (cons variable nil)) (root (cons shared shared)) (dotted (cons variable :tail)) (clause (make-clause (list (quote template-graph) variable variable root dotted) (list (list (quote template-body) variable root))))) (setf (cdr shared) shared) (let* ((template (cl-prolog::%compile-clause-template clause)) (first (cl-prolog::%materialize-clause-template template)) (second (cl-prolog::%materialize-clause-template template)) (first-head (clause-head first)) (second-head (clause-head second)) (first-root (fourth first-head)) (second-root (fourth second-head)) (first-shared (car first-root)) (second-shared (car second-root)) (first-body-goal (first (clause-body first))) (second-body-goal (first (clause-body second)))) (is (eq (second first-head) (third first-head))) (is (eq (second first-head) (car first-shared))) (is (eq (car first-root) (cdr first-root))) (is (eq first-shared (cdr first-shared))) (is (eq (second first-head) (car (fifth first-head)))) (is (eq :tail (cdr (fifth first-head)))) (is (eq (second first-head) (second first-body-goal))) (is (eq first-root (third first-body-goal))) (is (eq (second second-head) (third second-head))) (is (eq (second second-head) (car second-shared))) (is (eq (car second-root) (cdr second-root))) (is (eq second-shared (cdr second-shared))) (is (eq (second second-head) (second second-body-goal))) (is (eq second-root (third second-body-goal))) (is (not (eq (second first-head) (second second-head)))) (is (not (eq first-root second-root))) (is (not (eq first-shared second-shared))) (is (not (eq (fifth first-head) (fifth second-head))))))) (deftest stored-clause-template-isolates-input-public-views-and-proof-iterations () (let* ((payload (list :original)) (input (make-clause (list (quote stored-template) payload))) (rulebase (make-rulebase :clauses (list input)))) (setf (car payload) :input-mutated) (let* ((first-view (first (rulebase-visible-clauses rulebase))) (view-payload (second (clause-head first-view)))) (setf (car view-payload) :view-mutated)) (is (= 1 (length (query-prolog rulebase (quote (stored-template (:original))))))) (is (= 1 (length (query-prolog rulebase (quote (stored-template (:original))))))) (is (null (query-prolog rulebase (quote (stored-template (:input-mutated)))))) (is (null (query-prolog rulebase (quote (stored-template (:view-mutated)))))) (let* ((first-view (first (rulebase-visible-clauses rulebase))) (second-view (first (rulebase-visible-clauses rulebase))) (first-head (clause-head first-view)) (second-head (clause-head second-view))) (is (not (eq first-view second-view))) (is (not (eq first-head second-head))) (is (not (eq (second first-head) (second second-head)))) (is-equal (quote (:original)) (second first-head)) (is-equal (quote (:original)) (second second-head)))) (let* ((variable (fresh-logic-variable)) (alias-rulebase (make-rulebase :clauses (list (make-clause (list (quote template-alias) variable variable)))))) (is (= 1 (length (query-prolog alias-rulebase (quote (template-alias alpha alpha)))))) (is (null (query-prolog alias-rulebase (quote (template-alias alpha beta))))) (is (= 1 (length (query-prolog alias-rulebase (quote (template-alias beta beta)))))))))
