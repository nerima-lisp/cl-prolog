;;;; Predicate-index maintenance and call/rule-resolution depth-limit tests.

(in-package #:cl-prolog.tests)

(defun stored-clause-heads (entries)
  "Return the clause head of each stored-clause entry in ENTRIES, in order."
  (mapcar (lambda (entry)
            (clause-head (cl-prolog::%stored-clause-clause entry)))
          entries))

(deftest predicate-index-excludes-unrelated-clauses-and-preserves-order ()
  (let* ((rulebase (make-rulebase))
         (index (cl-prolog::rulebase-predicate-index rulebase))
         (tails (cl-prolog::rulebase-predicate-tails rulebase))
         (key (list cl-prolog::+default-prolog-module+ 'indexed 1)))
    (is (null (cl-prolog::rulebase-entries rulebase)))
    (is (null (cl-prolog::rulebase-entries-tail rulebase)))
    (is-equal 0 (hash-table-count index))
    (is-equal 0 (hash-table-count tails))
    (rulebase-insert-clause! rulebase (make-clause '(indexed first))
                             :position :first)
    (is (eq (cl-prolog::rulebase-entries rulebase)
            (cl-prolog::rulebase-entries-tail rulebase)))
    (is (eq (gethash key index) (gethash key tails)))
    (let ((first-indexed-tail (gethash key tails)))
      (rulebase-insert-clause! rulebase (make-clause '(other between)))
      (is (eq first-indexed-tail (gethash key tails))))
    (rulebase-insert-clause! rulebase (make-clause '(indexed second)))
    (let ((global-tail (cl-prolog::rulebase-entries-tail rulebase))
          (indexed-tail (gethash key tails)))
      (rulebase-insert-clause! rulebase (make-clause '(indexed zeroth))
                               :position :first)
      (is (eq global-tail (cl-prolog::rulebase-entries-tail rulebase)))
      (is (eq indexed-tail (gethash key tails))))
    (is-equal '((indexed zeroth)
                (indexed first)
                (other between)
                (indexed second))
              (stored-clause-heads (cl-prolog::rulebase-entries rulebase)))
    (multiple-value-bind (revision entries)
        (cl-prolog::%rulebase-predicate-entries
         rulebase cl-prolog::+default-prolog-module+ 'indexed 1)
      (declare (cl:ignore revision))
      (is-equal '((indexed zeroth) (indexed first) (indexed second))
                (stored-clause-heads entries)))
    (is (eq (last (cl-prolog::rulebase-entries rulebase))
            (cl-prolog::rulebase-entries-tail rulebase)))
    (is (loop for predicate-key being the hash-keys of index
                using (hash-value entries)
              always
              (and (eq (last entries) (gethash predicate-key tails))
                   (equal entries
                          (remove-if-not
                           (lambda (entry)
                             (equal predicate-key
                                    (cl-prolog::%stored-clause-predicate-key
                                     entry)))
                           (cl-prolog::rulebase-entries rulebase))))))))

(deftest predicate-index-keeps-logical-update-history ()
  (let* ((rulebase (make-rulebase))
         (key (list cl-prolog::+default-prolog-module+ 'indexed 1)))
    (assert-query rulebase (assertz (indexed first)) :succeeds)
    (assert-query rulebase (assertz (indexed second)) :succeeds)
    (let ((snapshot (cl-prolog::rulebase-revision rulebase)))
      (assert-query rulebase (asserta (indexed zeroth)) :succeeds)
      (assert-query rulebase (retract (indexed first)) :succeeds)
      (is-equal '(((?x . zeroth)) ((?x . second)))
                (query-prolog rulebase '(indexed ?x)))
      (assert-query rulebase (assertz (indexed third)) :succeeds)
      (is-equal '(((?x . zeroth)) ((?x . second)) ((?x . third)))
                (query-prolog rulebase '(indexed ?x)))
      (let ((entries
              (gethash key
                       (cl-prolog::rulebase-predicate-index rulebase))))
        (is-equal '((indexed zeroth)
                    (indexed first)
                    (indexed second)
                    (indexed third))
                  (stored-clause-heads entries))
        (is (eq (last entries)
                (gethash key
                         (cl-prolog::rulebase-predicate-tails rulebase)))))
      (is-equal '((indexed first) (indexed second))
                (stored-clause-heads
                 (cl-prolog::%rulebase-predicate-entries-at-revision
                  rulebase cl-prolog::+default-prolog-module+
                  'indexed 1 snapshot)))
      (assert-query rulebase (abolish (/ indexed 1)) :succeeds)
      (is-equal '()
                (cl-prolog::%rulebase-predicate-entries-at-revision
                 rulebase cl-prolog::+default-prolog-module+ 'indexed 1
                 (cl-prolog::rulebase-revision rulebase)))
      (is-equal '((indexed first) (indexed second))
                (stored-clause-heads
                 (cl-prolog::%rulebase-predicate-entries-at-revision
                  rulebase cl-prolog::+default-prolog-module+
                  'indexed 1 snapshot))))))

(deftest predicate-visible-check-respects-logical-update-history ()
  (let* ((rulebase (make-rulebase))
         (module cl-prolog::+default-prolog-module+)
         (predicate 'visible-indexed)
         (arity 1)
         (key (list module predicate arity)))
    (rulebase-insert-clause!
     rulebase (make-clause '(visible-indexed dead-first)))
    (rulebase-insert-clause!
     rulebase (make-clause '(visible-indexed live-later)))
    (let* ((entries (gethash key
                             (cl-prolog::rulebase-predicate-index rulebase)))
           (dead-first (first entries))
           (live-later (second entries)))
      (is (cl-prolog::%rulebase-retract-entry! rulebase dead-first))
      (is (cl-prolog::%rulebase-predicate-visible-p
           rulebase module predicate arity
           (cl-prolog::rulebase-revision rulebase)))
      (is (cl-prolog::%rulebase-retract-entry! rulebase live-later))
      (let ((all-dead-revision (cl-prolog::rulebase-revision rulebase)))
        (is (not (cl-prolog::%rulebase-predicate-visible-p
                  rulebase module predicate arity all-dead-revision)))
        (rulebase-insert-clause!
         rulebase (make-clause '(visible-indexed born-after-snapshot)))
        (is (not (cl-prolog::%rulebase-predicate-visible-p
                  rulebase module predicate arity all-dead-revision)))
        (is (cl-prolog::%rulebase-predicate-visible-p
             rulebase module predicate arity
             (cl-prolog::rulebase-revision rulebase)))))))
 (deftest predicate-index-isolates-modules ()
  (let ((rulebase (make-rulebase)))
    (rulebase-insert-clause! rulebase (make-clause '(indexed alpha))
                             :module 'alpha)
    (rulebase-insert-clause! rulebase (make-clause '(indexed beta))
                             :module 'beta)
    (is-equal '((indexed alpha))
              (stored-clause-heads
               (cl-prolog::%rulebase-predicate-entries-at-revision
                rulebase 'alpha 'indexed 1
                (cl-prolog::rulebase-revision rulebase))))
    (is-equal '((indexed beta))
              (stored-clause-heads
               (cl-prolog::%rulebase-predicate-entries-at-revision
                rulebase 'beta 'indexed 1
                (cl-prolog::rulebase-revision rulebase))))))


(deftest predicate-index-copy-is-independent ()
  (let* ((rulebase (prolog ((indexed original))))
         (copy (cl-prolog::%copy-rulebase rulebase))
         (key (list cl-prolog::+default-prolog-module+ 'indexed 1)))
    (is (not (eq (cl-prolog::rulebase-entries rulebase)
                 (cl-prolog::rulebase-entries copy))))
    (is (not (eq (cl-prolog::rulebase-entries-tail rulebase)
                 (cl-prolog::rulebase-entries-tail copy))))
    (is (not (eq (cl-prolog::rulebase-predicate-index rulebase)
                 (cl-prolog::rulebase-predicate-index copy))))
    (is (not (eq (gethash key
                          (cl-prolog::rulebase-predicate-index rulebase))
                 (gethash key
                          (cl-prolog::rulebase-predicate-index copy)))))
    (is (not (eq (gethash key
                          (cl-prolog::rulebase-predicate-tails rulebase))
                 (gethash key
                          (cl-prolog::rulebase-predicate-tails copy)))))
    (rulebase-insert-clause! copy (make-clause '(indexed copied)))
    (is-equal '((indexed original))
              (stored-clause-heads
               (nth-value
                1 (cl-prolog::%rulebase-predicate-entries
                   rulebase cl-prolog::+default-prolog-module+
                   'indexed 1))))
    (is-equal '((indexed original) (indexed copied))
              (stored-clause-heads
               (nth-value
                1 (cl-prolog::%rulebase-predicate-entries
                   copy cl-prolog::+default-prolog-module+
                   'indexed 1))))
    (rulebase-insert-clause! rulebase
                             (make-clause '(indexed original-added)))
    (is-equal '((indexed original) (indexed original-added))
              (stored-clause-heads
               (nth-value
                1 (cl-prolog::%rulebase-predicate-entries
                   rulebase cl-prolog::+default-prolog-module+
                   'indexed 1))))
    (is-equal '((indexed original) (indexed copied))
              (stored-clause-heads
               (nth-value
                1 (cl-prolog::%rulebase-predicate-entries
                   copy cl-prolog::+default-prolog-module+
                   'indexed 1))))
    (is (eq (last (cl-prolog::rulebase-entries rulebase))
            (cl-prolog::rulebase-entries-tail rulebase)))
    (is (eq (last (cl-prolog::rulebase-entries copy))
            (cl-prolog::rulebase-entries-tail copy)))))

(deftest predicate-index-replace-reflects-transaction ()
  (let* ((rulebase (prolog ((indexed original))))
         (transaction (cl-prolog::%copy-rulebase rulebase))
         (key (list cl-prolog::+default-prolog-module+ 'indexed 1)))
    (rulebase-insert-clause! transaction (make-clause '(indexed committed)))
    (cl-prolog::%replace-rulebase! rulebase transaction)
    (is-equal '((indexed original) (indexed committed))
              (stored-clause-heads
               (nth-value
                1 (cl-prolog::%rulebase-predicate-entries
                   rulebase cl-prolog::+default-prolog-module+
                   'indexed 1))))
    (let ((discarded (cl-prolog::%copy-rulebase rulebase)))
      (rulebase-insert-clause! discarded
                               (make-clause '(indexed rolled-back))))
    (rulebase-insert-clause! rulebase
                             (make-clause '(indexed after-rollback)))
    (is-equal '((indexed original)
                (indexed committed)
                (indexed after-rollback))
              (stored-clause-heads
               (nth-value
                1 (cl-prolog::%rulebase-predicate-entries
                   rulebase cl-prolog::+default-prolog-module+
                   'indexed 1))))
    (is (eq (last (cl-prolog::rulebase-entries rulebase))
            (cl-prolog::rulebase-entries-tail rulebase)))
    (is (eq (last (gethash key
                           (cl-prolog::rulebase-predicate-index rulebase)))
            (gethash key
                     (cl-prolog::rulebase-predicate-tails rulebase))))))

(deftest predicate-index-proof-loop-preserves-arity-and-solution-order ()
  (let ((rulebase
          (prolog
           ((dispatch alpha))
           ((dispatch ?value) (helper ?value))
           ((dispatch beta))
           ((dispatch alpha extra))
           ((helper gamma)))))
    (is-equal (quote (nil))
              (query-prolog rulebase (quote (dispatch alpha))))
    (is-equal (quote (((?value . alpha))
                      ((?value . gamma))
                      ((?value . beta))))
              (query-prolog rulebase (quote (dispatch ?value))))
    (is-equal (quote (nil))
              (query-prolog rulebase (quote (dispatch alpha extra))))))

(progn
  (deftest predicate-index-bound-cyclic-root-keeps-full-snapshot-order ()
  (let* ((cycle (list (quote root)))
         (environment (list (cons (quote ?value) cycle)))
         (rulebase
           (prolog
            ((cyclic-index first))
            ((cyclic-index ?item))
            ((cyclic-index last))))
         (session (cl-prolog::%make-rulebase-table-session rulebase))
         (state
           (cl-prolog::%make-proof-state
            rulebase
            environment
            (cl-prolog::%make-environment-index environment)
            nil
            cl-prolog::+default-prolog-module+
            session
            (cl-prolog::%make-cut-tag)))
         (descriptor
           (cl-prolog::%rulebase-predicate-descriptor
            rulebase cl-prolog::+default-prolog-module+
            (quote cyclic-index) 1))
         (entries (cl-prolog::%predicate-descriptor-entries descriptor)))
    (setf (cdr cycle) cycle)
    (let ((snapshot
            (cl-prolog::%proof-predicate-entries
             (quote (cyclic-index ?value)) state)))
      (is (eq entries snapshot))
      (is-equal
       (quote ((cyclic-index first)
               (cyclic-index ?item)
               (cyclic-index last)))
       (stored-clause-heads snapshot))
      (setf (car cycle) (quote changed))
      (is (eq snapshot
              (cl-prolog::%proof-predicate-entries
               (quote (cyclic-index ?value)) state))))))

  (deftest tabled-cyclic-goal-retains-cyclic-answer ()
    (let* ((cycle (list (quote root)))
           (environment (list (cons (quote ?value) cycle)))
           (rulebase (prolog ((tabled-cycle ?item)))))
      (setf (cdr cycle) cycle)
      (cl-prolog::%add-rulebase-table-declaration!
       rulebase (quote tabled-cycle) 1 :test)
      (let ((answers
              (query-prolog rulebase (quote (tabled-cycle ?value))
                            :environment environment)))
        (is (= 1 (length answers)))
        (let ((resolved
                (cl-prolog:logic-substitute (quote ?value) (first answers))))
          (is (consp resolved))
          (is (eq resolved (cdr resolved)))))))

  (deftest predicate-index-proof-cache-follows-rulebase-revisions ()
    (let* ((rulebase (prolog ((indexed original))))
           (session (cl-prolog::%make-rulebase-table-session rulebase))
           (state
             (cl-prolog::%make-proof-state
              rulebase
              (quote ())
              (cl-prolog::%make-environment-index (quote ()))
              nil
              cl-prolog::+default-prolog-module+
              session
              (cl-prolog::%make-cut-tag)))
           (first-snapshot
             (cl-prolog::%proof-predicate-entries (quote (indexed ?value)) state)))
      (is (eq first-snapshot
              (cl-prolog::%proof-predicate-entries (quote (indexed ?value)) state)))
      (rulebase-insert-clause! rulebase (make-clause (quote (indexed added))))
      (let ((next-snapshot
              (cl-prolog::%proof-predicate-entries (quote (indexed ?value)) state)))
        (is (not (eq first-snapshot next-snapshot)))
        (is-equal (quote ((indexed original) (indexed added)))
                  (stored-clause-heads next-snapshot))))))

(deftest ordinary-predicates-are-not-replayed-for-tabling ()
  (let ((rulebase (prolog
                    ((run-once) (assertz marker)))))
    (assert-query rulebase (run-once) :succeeds)
    (is-equal 1 (length (query-prolog rulebase 'marker)))))

(deftest depth-counts-only-user-rule-resolution ()
  (let ((rb (prolog
              ((ready))
              ((through-call) (call ready))
              ((through-not) (not false)))))
    (is-equal '(nil) (query-prolog rb '(ready) :max-depth 0))
    (is-equal '(nil) (query-prolog rb '(through-call) :max-depth 1))
    (is-equal '(nil) (query-prolog rb '(through-not) :max-depth 1))
    (handler-case
        (progn
          (query-prolog rb '(through-call) :max-depth 0)
          (error "Expected a PROLOG-DEPTH-LIMIT-EXCEEDED"))
      (prolog-depth-limit-exceeded (condition)
        (is-equal '(through-call)
                  (prolog-depth-limit-exceeded-goal condition))))))

(deftest call-with-depth-limit-counts-rules-and-preserves-global-limit ()
  (let ((rb (prolog
              ((ready))
              ((one-deep) (ready))
              ((two-deep) (one-deep)))))
    (assert-query rb (call_with_depth_limit true 1 ?depth)
                  :ordered (((?depth . 1))))
    (let* ((solutions
             (query-prolog rb '(call_with_depth_limit true 0 ?result)))
           (result (logic-substitute '?result (first solutions))))
      (is (eq (cl-prolog::%iso-atom "DEPTH_LIMIT_EXCEEDED") result)))
    (assert-query rb (call_with_depth_limit (ready) 1 ?depth)
                  :ordered (((?depth . 1))))
    (assert-query rb (call_with_depth_limit (one-deep) 2 ?depth)
                  :ordered (((?depth . 2))))
    (assert-query rb (call_with_depth_limit (two-deep) 3 ?depth)
                  :ordered (((?depth . 3))))
    (let* ((solutions
             (query-prolog rb '(call_with_depth_limit (ready) 0 ?result)))
           (result (logic-substitute '?result (first solutions))))
      (is (eq (cl-prolog::%iso-atom "DEPTH_LIMIT_EXCEEDED") result)))
    (let* ((solutions
             (query-prolog rb '(call_with_depth_limit (two-deep) 2 ?result)))
           (result (logic-substitute '?result (first solutions))))
      (is (eq (cl-prolog::%iso-atom "DEPTH_LIMIT_EXCEEDED") result)))
    (signals-condition prolog-depth-limit-exceeded
      (query-prolog rb '(call_with_depth_limit (one-deep) 5 ?result)
                    :max-depth 0))))

(deftest call-with-depth-limit-is-cut-opaque ()
  (let ((rb (make-rulebase)))
    (is-equal
     '(((?depth . cl-prolog::depth_limit_exceeded) (?side . ?side))
       ((?depth . ?depth) (?side . fallback)))
     (query-prolog
      rb '(or (call_with_depth_limit (and ! fail) 0 ?depth)
              (= ?side fallback))))))

(deftest call-with-depth-limit-is-uncatchable-by-goal ()
  (let ((rb (prolog
              ((looping) (looping)))))
    (let* ((solutions
             (query-prolog
              rb
              '(call_with_depth_limit
                (catch (looping) ?caught true) 0 ?result)))
           (solution (first solutions)))
      ;; Unbound query variables are represented by self-bindings in solutions;
      ;; substituting through one would recurse indefinitely.
      (is (logic-var-p (cdr (assoc '?caught solution))))
      (is (eq (cl-prolog::%iso-atom "DEPTH_LIMIT_EXCEEDED")
              (logic-substitute '?result solution))))))

(deftest nested-call-with-depth-limit-overrides-only-the-inner-scope ()
  (let ((rb (prolog
              ((ready))
              ((one-deep) (ready)))))
    (assert-query
     rb
     (call_with_depth_limit
      (call_with_depth_limit (one-deep) 2 ?inner-depth)
      1 ?outer-depth)
     :ordered (((?inner-depth . 2) (?outer-depth . 1))))))

(deftest call-with-depth-limit-does-not-scope-over-the-caller-continuation ()
  (let ((rb (make-rulebase)))
    (assert-query
     rb
     (and (call_with_depth_limit true 1 ?depth)
          (= ?side ok))
     :ordered (((?depth . 1) (?side . ok))))))

(progn
(progn
  (deftest finite-proofs-are-unbounded-by-default ()
    (let ((rb (make-rulebase))
          (chain-length 20))
      (labels ((predicate-at (index)
                 (intern (format nil "DEPTH-~D" index) *package*)))
        (rulebase-insert-clause! rb (make-clause (list (predicate-at 0))))
        (loop for index from 1 to chain-length
              do (rulebase-insert-clause!
                  rb
                  (make-clause (list (predicate-at index))
                               (list (list (predicate-at (1- index)))))))
        (is-equal (quote (nil))
                  (query-prolog rb (list (predicate-at chain-length))))
        (is (handler-case
                (progn
                  (query-prolog rb (list (predicate-at chain-length))
                                :max-depth (1- chain-length))
                  nil)
              (prolog-depth-limit-exceeded () t))))))

  (deftest proof-state-environment-index-follows-binding-updates ()
    (let* ((rulebase (make-rulebase))
           (bindings (quote ((?seed . initial))))
           (state
             (cl-prolog::%make-proof-state
              rulebase
              bindings
              (cl-prolog::%make-environment-index bindings)
              nil
              cl-prolog::+default-prolog-module+
              (cl-prolog::%make-rulebase-table-session rulebase)
              (cl-prolog::%make-cut-tag)))
           (extended-bindings
             (acons (quote ?derived) (quote ?seed) bindings))
           (extended
             (cl-prolog::%state-with state :bindings extended-bindings)))
      (is-equal (quote initial)
                (cl-prolog::%logic-substitute-indexed
                 (quote ?derived)
                 (cl-prolog::proof-state-environment-index extended)))
      (is (not (eq (cl-prolog::proof-state-environment-index state)
                   (cl-prolog::proof-state-environment-index extended))))))

  (deftest proof-state-explicit-environment-index-takes-precedence ()
    (let* ((rulebase (make-rulebase))
           (bindings (quote ((?seed . initial))))
           (state
             (cl-prolog::%make-proof-state
              rulebase
              bindings
              (cl-prolog::%make-environment-index bindings)
              nil
              cl-prolog::+default-prolog-module+
              (cl-prolog::%make-rulebase-table-session rulebase)
              (cl-prolog::%make-cut-tag)))
           (updated-bindings (quote ((?seed . updated))))
           (supplied-index
             (cl-prolog::%make-environment-index
              (quote ((?seed . supplied)))))
           (updated
             (cl-prolog::%state-with
              state
              :bindings updated-bindings
              :environment-index supplied-index)))
      (is (eq supplied-index
              (cl-prolog::proof-state-environment-index updated)))
      (is-equal (quote supplied)
                (cl-prolog::%logic-substitute-indexed
                 (quote ?seed)
                 (cl-prolog::proof-state-environment-index updated)))))

  (deftest proof-state-unchanged-cut-tag-preserves-identity ()
    (let* ((rulebase (make-rulebase))
           (state
             (cl-prolog::%make-proof-state
              rulebase
              nil
              (cl-prolog::%make-environment-index nil)
              nil
              cl-prolog::+default-prolog-module+
              (cl-prolog::%make-rulebase-table-session rulebase)
              (cl-prolog::%make-cut-tag))))
      (is (eq state
              (cl-prolog::%state-with
               state
               :cut-tag (cl-prolog::proof-state-cut-tag state))))))

    (deftest proof-state-module-update-bypasses-unchanged-cut-tag-identity ()
    (let* ((rulebase (make-rulebase))
           (state
             (cl-prolog::%make-proof-state
              rulebase
              nil
              (cl-prolog::%make-environment-index nil)
              nil
              cl-prolog::+default-prolog-module+
              (cl-prolog::%make-rulebase-table-session rulebase)
              (cl-prolog::%make-cut-tag)))
           (updated
             (cl-prolog::%state-with
              state
              :cut-tag (cl-prolog::proof-state-cut-tag state)
              :module (quote other))))
      (is (not (eq state updated)))
      (is-equal (quote other)
                (cl-prolog::proof-state-module updated))))

  (deftest indexed-query-state-handles-initial-bindings-builtins-and-projection ()
    (is-equal
     (quote (((?left . ready) (?seed . ready) (?right . ready))))
     (query-prolog
      (make-rulebase)
      (quote ((= ?left ?seed) (= ?right ?left)))
      :environment (quote ((?seed . ready))))))

  (deftest constraint-hook-propagated-bindings-update-the-state-index ()
    (let ((hook-ran-p nil)
          (rulebase (prolog ((trigger)))))
      (let ((cl-prolog::*constraint-post-unify-hook*
              (lambda (environment emit)
                (funcall
                 emit
                 (if hook-ran-p
                     environment
                     (progn
                       (setf hook-ran-p t)
                       (acons (quote ?hooked)
                              (quote propagated)
                              environment)))))))
        (is-equal
         (quote (((?hooked . propagated))))
         (query-prolog
          rulebase
          (quote ((trigger) (= ?hooked propagated))))))))

  (deftest table-answer-replay-preserves-parent-index-for-projection ()
  (let ((rulebase
          (prolog
           ((tabled-source alpha))
           ((tabled-source beta)))))
    (cl-prolog::%add-rulebase-table-declaration!
     rulebase (quote tabled-source) 1 :test)
    (is-equal
     (quote
      (((?first . alpha) (?pair alpha alpha))
       ((?first . beta) (?pair beta beta))))
     (query-prolog
      rulebase
      (quote
       ((tabled-source ?first)
        (tabled-source ?first)
        (= ?pair (?first ?first)))))))))

(deftest predicate-descriptors-copy-on-write-every-mutation ()
  (let ((rulebase (make-rulebase))
        (module cl-prolog::+default-prolog-module+))
    (rulebase-insert-clause! rulebase (make-clause (quote (cow middle))))
    (let* ((middle-descriptor
             (cl-prolog::%rulebase-predicate-descriptor
              rulebase module (quote cow) 1))
           (middle-snapshot
             (cl-prolog::%predicate-descriptor-entries middle-descriptor)))
      (rulebase-insert-clause!
       rulebase (make-clause (quote (cow first))) :position :first)
      (let* ((first-descriptor
               (cl-prolog::%rulebase-predicate-descriptor
                rulebase module (quote cow) 1))
             (first-snapshot
               (cl-prolog::%predicate-descriptor-entries first-descriptor)))
        (is (not (eq middle-descriptor first-descriptor)))
        (is-equal
         (quote ((cow middle)))
         (stored-clause-heads middle-snapshot))
        (is-equal
         (quote ((cow first) (cow middle)))
         (stored-clause-heads first-snapshot))
        (rulebase-insert-clause!
         rulebase (make-clause (quote (cow last))) :position :last)
        (let* ((last-descriptor
                 (cl-prolog::%rulebase-predicate-descriptor
                  rulebase module (quote cow) 1))
               (last-snapshot
                 (cl-prolog::%predicate-descriptor-entries last-descriptor))
               (middle-entry (second last-snapshot)))
          (is (not (eq first-descriptor last-descriptor)))
          (is-equal
           (quote ((cow first) (cow middle) (cow last)))
           (stored-clause-heads last-snapshot))
          (is (cl-prolog::%rulebase-retract-entry! rulebase middle-entry))
          (let* ((retract-descriptor
                   (cl-prolog::%rulebase-predicate-descriptor
                    rulebase module (quote cow) 1))
                 (retract-snapshot
                   (cl-prolog::%predicate-descriptor-entries
                    retract-descriptor)))
            (is (not (eq last-descriptor retract-descriptor)))
            (is-equal
             (quote ((cow first) (cow last)))
             (stored-clause-heads retract-snapshot))
            (is-equal
             (quote ((cow first) (cow middle) (cow last)))
             (stored-clause-heads last-snapshot))
            (is (cl-prolog::%rulebase-retract-entries!
                 rulebase retract-snapshot))
            (is (null
                 (cl-prolog::%rulebase-predicate-descriptor
                  rulebase module (quote cow) 1)))
            (is (zerop
                 (hash-table-count
                  (cl-prolog::rulebase-predicate-descriptors rulebase))))))))))

(deftest predicate-descriptor-candidates-preserve-order-without-lookup-writes ()
  (let* ((rulebase
           (prolog
            ((indexed target exact-first))
            ((indexed ?value wildcard))
            ((indexed other excluded))
            ((indexed target exact-last))))
         (module cl-prolog::+default-prolog-module+)
         (descriptor
           (cl-prolog::%rulebase-predicate-descriptor
            rulebase module (quote indexed) 2))
         (root (cl-prolog::rulebase-predicate-descriptors rulebase))
         (predicates (gethash module root))
         (arities (gethash (quote indexed) predicates))
         (symbols
           (cl-prolog::%predicate-descriptor-symbol-first-argument-index
            descriptor))
         (atoms
           (cl-prolog::%predicate-descriptor-atom-first-argument-index
            descriptor))
         (counts
           (list (hash-table-count root)
                 (hash-table-count predicates)
                 (hash-table-count arities)
                 (hash-table-count symbols)
                 (hash-table-count atoms))))
    (is-equal
     (quote
      ((indexed target exact-first)
       (indexed ?value wildcard)
       (indexed target exact-last)))
     (stored-clause-heads
      (cl-prolog::%predicate-descriptor-first-argument-entries
       descriptor (quote target))))
    (is-equal
     (quote ((indexed ?value wildcard)))
     (stored-clause-heads
      (cl-prolog::%predicate-descriptor-first-argument-entries
       descriptor (quote absent))))
    (is-equal
     (quote
      ((indexed target exact-first)
       (indexed ?value wildcard)
       (indexed other excluded)
       (indexed target exact-last)))
     (stored-clause-heads
      (cl-prolog::%predicate-descriptor-first-argument-entries
       descriptor (quote ?query))))
    (is (null
         (cl-prolog::%rulebase-predicate-descriptor
          rulebase (make-symbol "MISSING-MODULE") (quote indexed) 2)))
    (is (null
         (cl-prolog::%rulebase-predicate-descriptor
          rulebase module (make-symbol "MISSING-PREDICATE") 2)))
    (is (null
         (cl-prolog::%rulebase-predicate-descriptor
          rulebase module (quote indexed) 3)))
    (cl-prolog::%predicate-descriptor-first-argument-entries
     descriptor (make-symbol "MISSING-FIRST-ARGUMENT"))
    (is-equal
     counts
     (list (hash-table-count root)
           (hash-table-count predicates)
           (hash-table-count arities)
           (hash-table-count symbols)
           (hash-table-count atoms)))))

(progn
  (deftest predicate-descriptor-high-cardinality-keys-preserve-order ()
    (let* ((key-count 512)
           (target 257)
           (rulebase
             (make-rulebase
              :clauses
              (append
               (loop for index below key-count
                     collect
                     (make-clause (list 'high-cardinality index 'exact-before)))
               (list (make-clause '(high-cardinality ?value wildcard)))
               (loop for index below key-count
                     collect
                     (make-clause (list 'high-cardinality index 'exact-after))))))
           (descriptor
             (cl-prolog::%rulebase-predicate-descriptor
              rulebase cl-prolog::+default-prolog-module+
              'high-cardinality 2)))
      (is-equal
       `((high-cardinality ,target exact-before)
         (high-cardinality ?value wildcard)
         (high-cardinality ,target exact-after))
       (stored-clause-heads
        (cl-prolog::%predicate-descriptor-first-argument-entries
         descriptor target)))))

  (deftest predicate-index-resolves-first-argument-aliases-before-selection ()
    (let* ((environment '((?outer . ?inner) (?inner . exact-after)))
           (rulebase
             (prolog
              ((alias-index exact-before exact-before))
              ((alias-index ?value wildcard))
              ((alias-index exact-after exact-after))))
           (session (cl-prolog::%make-rulebase-table-session rulebase))
           (state
             (cl-prolog::%make-proof-state
              rulebase
              environment
              (cl-prolog::%make-environment-index environment)
              nil
              cl-prolog::+default-prolog-module+
              session
              (cl-prolog::%make-cut-tag))))
      (is-equal
       '((alias-index ?value wildcard)
         (alias-index exact-after exact-after))
       (stored-clause-heads
        (cl-prolog::%proof-predicate-entries
         '(alias-index ?outer ?result) state))))))

(deftest predicate-descriptor-distinguishes-symbol-identity-and-eql-atoms ()
  (let* ((package-a
           (make-package
            (symbol-name (gensym "DESCRIPTOR-PACKAGE-A-")) :use (quote ())))
         (package-b
           (make-package
            (symbol-name (gensym "DESCRIPTOR-PACKAGE-B-")) :use (quote ()))))
    (unwind-protect
         (let* ((first (intern "SAME" package-a))
                (second (intern "SAME" package-b))
                (rulebase
                  (make-rulebase
                   :clauses
                   (list
                    (make-clause (list (quote identity-key) first (quote first)))
                    (make-clause
                     (quote (identity-key ?value wildcard)))
                    (make-clause
                     (list (quote identity-key) second (quote second))))))
                (descriptor
                  (cl-prolog::%rulebase-predicate-descriptor
                   rulebase cl-prolog::+default-prolog-module+
                   (quote identity-key) 2)))
           (is (not (eq first second)))
           (is-equal
            (list
             (list (quote identity-key) first (quote first))
             (quote (identity-key ?value wildcard)))
            (stored-clause-heads
             (cl-prolog::%predicate-descriptor-first-argument-entries
              descriptor first)))
           (is-equal
            (list
             (quote (identity-key ?value wildcard))
             (list (quote identity-key) second (quote second)))
            (stored-clause-heads
             (cl-prolog::%predicate-descriptor-first-argument-entries
              descriptor second))))
      (delete-package package-a)
      (delete-package package-b)))
  (let* ((rulebase
           (prolog
            ((atomic-key 42 number))
            ((atomic-key ?value wildcard))
            ((atomic-key #\x character))))
         (descriptor
           (cl-prolog::%rulebase-predicate-descriptor
            rulebase cl-prolog::+default-prolog-module+
            (quote atomic-key) 2)))
    (is-equal
     (quote ((atomic-key 42 number) (atomic-key ?value wildcard)))
     (stored-clause-heads
      (cl-prolog::%predicate-descriptor-first-argument-entries
       descriptor 42)))
    (is-equal
     (quote ((atomic-key ?value wildcard) (atomic-key #\x character)))
     (stored-clause-heads
      (cl-prolog::%predicate-descriptor-first-argument-entries
       descriptor #\x)))
    (is-equal
     (quote ((atomic-key ?value wildcard)))
     (stored-clause-heads
      (cl-prolog::%predicate-descriptor-first-argument-entries
       descriptor 99)))))

(deftest predicate-descriptor-leaves-mutable-compound-and-cyclic-terms-unindexed ()
  (let* ((string (copy-seq "string"))
         (bits (copy-seq #*101))
         (compound (list (quote compound) (quote value)))
         (cycle (cons (quote loop) nil))
         (rulebase (make-rulebase)))
    (setf (cdr cycle) cycle)
    (dolist (head
             (list (list (quote unindexed) string (quote string))
                   (list (quote unindexed) bits (quote bits))
                   (list (quote unindexed) compound (quote compound))
                   (list (quote unindexed) cycle (quote cycle))))
      (rulebase-insert-clause! rulebase (make-clause head)))
    (let* ((descriptor
             (cl-prolog::%rulebase-predicate-descriptor
              rulebase cl-prolog::+default-prolog-module+
              (quote unindexed) 2))
           (entries (cl-prolog::%predicate-descriptor-entries descriptor)))
      (is (zerop
           (hash-table-count
            (cl-prolog::%predicate-descriptor-symbol-first-argument-index
             descriptor))))
      (is (zerop
           (hash-table-count
            (cl-prolog::%predicate-descriptor-atom-first-argument-index
             descriptor))))
      (dolist (first-argument (list string bits compound cycle))
        (is (eq entries
                (cl-prolog::%predicate-descriptor-first-argument-entries
                 descriptor first-argument))))
      (setf (char string 0) #\X
            (aref bits 0) 0
            (car compound) (quote changed)
            (car cycle) (quote changed))
      (dolist (first-argument (list string bits compound cycle))
        (is (eq entries
                (cl-prolog::%predicate-descriptor-first-argument-entries
                 descriptor first-argument)))))))

(deftest predicate-descriptors-rebuild-on-copy-and-same-revision-replace ()
  (let* ((source
           (make-rulebase
            :clauses (list (make-clause (quote (replace-source value))))))
         (target
           (make-rulebase
            :clauses (list (make-clause (quote (replace-target value))))))
         (source-descriptor
           (cl-prolog::%rulebase-predicate-descriptor
            source cl-prolog::+default-prolog-module+
            (quote replace-source) 1))
         (target-descriptor
           (cl-prolog::%rulebase-predicate-descriptor
            target cl-prolog::+default-prolog-module+
            (quote replace-target) 1))
         (revision (cl-prolog::rulebase-revision target)))
    (is (= revision (cl-prolog::rulebase-revision source)))
    (cl-prolog::%replace-rulebase! target source)
    (let ((replacement-descriptor
            (cl-prolog::%rulebase-predicate-descriptor
             target cl-prolog::+default-prolog-module+
             (quote replace-source) 1)))
      (is (null
           (cl-prolog::%rulebase-predicate-descriptor
            target cl-prolog::+default-prolog-module+
            (quote replace-target) 1)))
      (is (not (eq target-descriptor replacement-descriptor)))
      (is (not (eq source-descriptor replacement-descriptor)))
      (is-equal
       (quote ((replace-source value)))
       (stored-clause-heads
        (cl-prolog::%predicate-descriptor-entries replacement-descriptor)))
      (let* ((copy (cl-prolog::%copy-rulebase target))
             (copy-descriptor
               (cl-prolog::%rulebase-predicate-descriptor
                copy cl-prolog::+default-prolog-module+
                (quote replace-source) 1)))
        (is (not (eq replacement-descriptor copy-descriptor)))
        (is (not
             (eq
              (cl-prolog::%predicate-descriptor-entries replacement-descriptor)
              (cl-prolog::%predicate-descriptor-entries copy-descriptor))))
        (is-equal
         (quote ((replace-source value)))
         (stored-clause-heads
          (cl-prolog::%predicate-descriptor-entries copy-descriptor)))))))
)

(progn
  (deftest table-answer-replay-reuses-ground-answer-across-consumers ()
    (let ((rulebase (prolog ((tabled-ground alpha)))))
      (cl-prolog::%add-rulebase-table-declaration!
       rulebase (quote tabled-ground) 1 :test)
      (let ((solutions
              (query-prolog
               rulebase
               (quote
                ((tabled-ground ?first)
                 (tabled-ground ?second)
                 (tabled-ground ?third))))))
        (is (= 1 (length solutions)))
        (let ((environment (first solutions)))
          (is-equal (quote alpha)
                    (logic-substitute (quote ?first) environment))
          (is-equal (quote alpha)
                    (logic-substitute (quote ?second) environment))
          (is-equal (quote alpha)
                    (logic-substitute (quote ?third) environment))))))

  (deftest table-answer-replay-freshens-nonground-answer-per-consumer ()
    (let ((rulebase (prolog ((tabled-variable ?item)))))
      (cl-prolog::%add-rulebase-table-declaration!
       rulebase (quote tabled-variable) 1 :test)
      (let ((solutions
              (query-prolog
               rulebase
               (quote
                ((tabled-variable ?first)
                 (tabled-variable ?second)
                 (= ?first alpha)
                 (= ?second beta))))))
        (is (= 1 (length solutions)))
        (let ((environment (first solutions)))
          (is-equal (quote alpha)
                    (logic-substitute (quote ?first) environment))
          (is-equal (quote beta)
                    (logic-substitute (quote ?second) environment)))))))
