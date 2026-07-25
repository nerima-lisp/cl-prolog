;;;; Goal normalization and CPS proof search.
;;;;
;;;; The engine keeps clause data and proof search separate: queries are
;;;; normalized here, then proven against the builtin registry, foreign
;;;; predicate hook, facts, and rules.  The state threaded through the
;;;; continuation is defined in proof-state.lisp.

(in-package #:cl-prolog)

(declaim (ftype function %proper-list-p %prove-goal/k %prove-clauses/k %prove-rule/k))

(defmacro %with-propagated-bindings
    ((propagated propagated-index extended extended-index) &body body)
  "Evaluate BODY for EXTENDED's bindings, routing through the constraint hook.

BODY sees PROPAGATED and PROPAGATED-INDEX. When *CONSTRAINT-POST-UNIFY-HOOK*
is set it decides which propagated bindings BODY runs on, and how often."
  (let ((continue (gensym "CONTINUE")))
    `(flet ((,continue (,propagated)
              (let ((,propagated-index
                      (%environment-index-after-bindings
                       ,propagated ,extended ,extended-index)))
                ,@body)))
       (if *constraint-post-unify-hook*
           (funcall *constraint-post-unify-hook* ,extended (function ,continue))
           (,continue ,extended)))))

(defun %conjunction-p (query)
  "True when QUERY is already a list of goals rather than a single goal."
  (and (consp query)
       (or (consp (first query))
           (eq (first query) '!))))

(defun %normalize-query (query)
  "Coerce QUERY into a list of goals."
  (cond
    ((null query) '())
    ((%conjunction-p query) query)
    (t (list query))))

(defun %goal-form-p (goal)
  "True when GOAL is a proper callable goal form."
  (and (consp goal)
       (%proper-list-p goal)
       (symbolp (first goal))))

(defun %ensure-goal-form (goal)
  "Normalize bare-symbol goals to list form."
  (if (symbolp goal)
      (list goal)
      goal))

(defun %goal-predicate-indicator (goal)
  "Return the ISO predicate indicator for normalized GOAL."
  (list '/ (first goal) (length (rest goal))))

(defun %proof-module-entries (state &optional (module (proof-state-module state)))
  "Return one revision-stable module snapshot shared by the current query."
  (let* ((rulebase (proof-state-rulebase state))
         (session (proof-state-table-session state))
         (key (list rulebase (rulebase-revision rulebase) module)))
    (multiple-value-bind (entries present-p)
        (gethash key (%table-session-module-entries session))
      (if present-p
          entries
          (setf (gethash key (%table-session-module-entries session))
                (%rulebase-module-entries rulebase module))))))

(defun %proof-predicate-entries
    (goal state &optional (module (proof-state-module state)))
  "Return the immutable current descriptor entries for GOAL."
  (let* ((rulebase (proof-state-rulebase state))
         (predicate (first goal))
         (arity (length (rest goal)))
         (descriptor
           (%rulebase-predicate-descriptor
            rulebase module predicate arity)))
    (when descriptor
      (if (plusp arity)
          (%predicate-descriptor-first-argument-entries
           descriptor
           (%logic-substitute-indexed
            (second goal)
            (proof-state-environment-index state)))
          (%predicate-descriptor-entries descriptor)))))

(defun %rulebase-defines-goal-p (state module predicate arity)
  "True when RULEBASE contains or declares MODULE:PREDICATE/ARITY."
  (let ((rulebase (proof-state-rulebase state)))
    (or (%rulebase-predicate-property rulebase predicate arity module)
        (%rulebase-predicate-descriptor
         rulebase module predicate arity))))

(defun %qualified-goal-p (goal)
  (and (%goal-form-p goal)
       (= (length goal) 3)
       (eq (first goal)
           (let* ((cached (load-time-value (%prolog-symbol ":") t))
                  (home (symbol-package cached)))
             (if (and home
                      (eq (find-package (quote #:cl-prolog)) home))
                 cached
                 (%prolog-symbol ":"))))))

(defun %resolve-qualified-module (module state)
  "Resolve MODULE through the current bindings and validate it as a module atom."
  (let* ((environment (proof-state-bindings state))
         (resolved
           (%logic-substitute-indexed
            module (proof-state-environment-index state)))
         (context (%iso-atom "CALL")))
    (when (logic-var-p resolved)
      (%raise-instantiation-error environment context
                                  "module qualifier must be instantiated"))
    (unless (symbolp resolved)
      (%raise-type-error "ATOM" resolved environment context
                         "module qualifier must be an atom"))
    (unless (gethash resolved
                     (module-registry-modules
                      (rulebase-module-registry (proof-state-rulebase state))))
      (%raise-existence-error "MODULE" resolved environment context
                              "unknown module"))
    resolved))

(defun %resolve-user-goal (goal state &optional explicit-module)
  (let* ((rulebase (proof-state-rulebase state))
         (registry (rulebase-module-registry rulebase))
         (caller (or explicit-module (proof-state-module state)))
         (predicate (first goal))
         (arity (length (rest goal)))
         (local-descriptor
           (and (not explicit-module)
                (%rulebase-predicate-descriptor
                 rulebase caller predicate arity))))
    (if local-descriptor
        (values goal caller)
        (let ((local-p
                (lambda (module name count)
                  (%rulebase-defines-goal-p state module name count))))
          (values goal
                  (if explicit-module
                      (module-registry-resolve-qualified
                       registry caller predicate arity local-p)
                      (module-registry-resolve
                       registry caller predicate arity local-p)))))))

(defun %continue-matching-fact (goal entry state succeed)
  "Unify GOAL against stored fact ENTRY and continue with the extended state."
  (let* ((clause (%stored-clause-clause entry))
         (template (%stored-clause-template entry)))
    (when (eq (first goal) (first (clause-head clause)))
      (let ((program (%clause-template-rule-program template))
            (parent-bindings (proof-state-bindings state))
            (parent-index (proof-state-environment-index state)))
        (multiple-value-bind (extended ok extended-index)
            (if (and program
                     (zerop (length (%rule-program-body program))))
                (let* ((variable-count
                         (%rule-program-variable-count program))
                       (variables
                         (if (zerop variable-count)
                             #()
                             (make-array variable-count))))
                  (dotimes (index variable-count)
                    (setf (svref variables index)
                          (%fresh-rule-program-variable)))
                  (%unify-rule-program-head
                   goal program variables parent-bindings parent-index))
                (let ((fresh-head
                        (clause-head
                         (%materialize-stored-clause-for-proof entry template))))
                  (%unify-indexed
                   goal fresh-head parent-bindings parent-index nil)))
          (when ok
            (%with-propagated-bindings
                (propagated propagated-index extended extended-index)
              (funcall succeed
                       (%state-with
                        state
                        :bindings propagated
                        :environment-index propagated-index)))))))))

(defun %matching-rule-p (goal clause)
  "True when CLAUSE can be considered for GOAL."
  (and (consp (clause-head clause))
       (eq (first goal) (first (clause-head clause)))))

(defun %prove-goals/k (goals state succeed)
  "Prove conjunction GOALS, calling SUCCEED with each solution state.

Each goal's solutions continue into the rest of the conjunction rebased
onto this conjunction's own cut barrier, so a callee's barrier never leaks
into the caller's remaining goals."
  (if (endp goals)
      (funcall succeed state)
      (let ((cut-tag (proof-state-cut-tag state)))
        (%prove-goal/k (first goals) state
                       (lambda (next-state)
                         (%prove-goals/k (rest goals)
                                         (%state-with next-state :cut-tag cut-tag)
                                         succeed))))))

(defun %resolve-dispatched-goal (goal state environment context)
  "Validate GOAL is callable after substitution and qualification.
Return (VALUES NORMALIZED-GOAL EXPLICIT-MODULE)."
  (let ((resolved-goal
          (%logic-substitute-indexed
           goal (proof-state-environment-index state))))
    (when (logic-var-p resolved-goal)
      (%raise-instantiation-error environment context
                                  "callable term must be instantiated"))
    (unless (or (symbolp resolved-goal)
                (%goal-form-p resolved-goal))
      (%invalid-goal resolved-goal
                     "a goal must be a symbol or a proper list headed by a symbol"))
    (let* ((qualified-p (%qualified-goal-p resolved-goal))
           (callable-goal
             (if qualified-p (third resolved-goal) resolved-goal)))
      (when (logic-var-p callable-goal)
        (%raise-instantiation-error environment context
                                    "callable term must be instantiated"))
      (unless (or (symbolp callable-goal)
                  (%goal-form-p callable-goal))
        (%invalid-goal resolved-goal
                       "a goal must be a symbol or a proper list headed by a symbol"))
      (values (%ensure-goal-form callable-goal)
              (and qualified-p
                   (%resolve-qualified-module (second resolved-goal) state))))))

(defun %prove-goal-dispatch/k (goal state succeed)
  "Prove GOAL from STATE after any active depth-limit accounting."
  (let* ((*current-table-session* (proof-state-table-session state))
         (environment (proof-state-bindings state))
         (context (%iso-atom "CALL")))
    (multiple-value-bind (normalized-goal explicit-module solver)
        (if (and (%goal-form-p goal)
                 (symbolp (first goal))
                 (not (logic-var-p (first goal)))
                 (not (%qualified-goal-p goal)))
            (let* ((predicate (first goal))
                   (arity (length (rest goal)))
                   (builtin-solver (%goal-solver predicate arity))
                   (foreign-solver (%foreign-goal-solver predicate arity))
                   (static-solver (or builtin-solver foreign-solver)))
              (if static-solver
                  (multiple-value-bind (resolved-goal resolved-module)
                      (%resolve-dispatched-goal goal state environment context)
                    (values resolved-goal resolved-module static-solver))
                  (values goal nil nil)))
            (multiple-value-bind (resolved-goal resolved-module)
                (%resolve-dispatched-goal goal state environment context)
              (let* ((predicate (first resolved-goal))
                     (arity (length (rest resolved-goal)))
                     (builtin-solver (%goal-solver predicate arity))
                     (foreign-solver (%foreign-goal-solver predicate arity)))
                (values resolved-goal resolved-module
                        (or builtin-solver foreign-solver)))))
      (when (and (eq (first normalized-goal) (quote !))
                 (null (rest normalized-goal)))
        (funcall succeed state)
        (cl:throw (proof-state-cut-tag state) t))
      (cond
        (solver
         (when explicit-module
           (%find-prolog-module
            (rulebase-module-registry (proof-state-rulebase state))
            explicit-module "invoke qualified goal"))
         (let* ((solver-state
                  (if explicit-module
                      (%state-with state :module explicit-module)
                      state))
                (*current-prolog-module* (proof-state-module solver-state))
                (*caller-cut-tag* (proof-state-cut-tag solver-state)))
           (funcall solver
                    normalized-goal
                    (proof-state-rulebase solver-state)
                    (proof-state-bindings solver-state)
                    (proof-state-remaining-depth solver-state)
                    (lambda (bindings)
                      (funcall succeed
                               (%state-with solver-state :bindings bindings))))))
        (t
         (multiple-value-bind (resolved-user-goal defining-module)
             (%resolve-user-goal normalized-goal state explicit-module)
           (if defining-module
               (%prove-clauses/k resolved-user-goal
                                 (%state-with state :module defining-module)
                                 succeed)
               (%raise-existence-error
                "PROCEDURE" (%goal-predicate-indicator normalized-goal)
                environment context
                "the invoked predicate is not defined"))))))))

(defun %prove-goal/k (goal state succeed)
  "Prove GOAL, counting every dispatched call for local depth limits."
  (if (null *call-depth-limit-token*)
      (%prove-goal-dispatch/k goal state succeed)
      (progn
        (when (zerop *call-depth-limit-remaining*)
          (cl:throw *call-depth-limit-token* *call-depth-limit-token*))
        (let ((*call-depth-limit-remaining*
                (1- *call-depth-limit-remaining*))
              (*call-depth-limit-used*
                (1+ *call-depth-limit-used*)))
          (%prove-goal-dispatch/k goal state succeed)))))

(defun %prove-with-cut-tag/k (query rulebase bindings remaining-depth cut-tag
                              succeed &optional (module *current-prolog-module*))
  "Prove QUERY under an existing cut barrier CUT-TAG."
  (let ((*unification-scratch*
          (or *unification-scratch* (%make-unification-scratch))))
    (%prove-goals/k
     (%normalize-query query)
     (%make-proof-state
      rulebase
      bindings
      (%make-environment-index bindings)
      remaining-depth
      module
      (or *current-table-session*
          (%make-rulebase-table-session rulebase))
      cut-tag)
     (lambda (state)
       (funcall succeed (proof-state-bindings state))))))

(defun %prove-bindings/k (query rulebase bindings remaining-depth succeed
                          &optional (module *current-prolog-module*))
  "Prove QUERY and call SUCCEED with each resulting binding environment.

QUERY runs behind its own cut barrier: a cut inside it never prunes the
caller's alternatives, matching ISO CALL/1 opacity."
  (let ((cut-tag (%make-cut-tag)))
    (cl:catch cut-tag
      (%prove-with-cut-tag/k query rulebase bindings remaining-depth cut-tag
                             succeed module))))

(defun %prove-transparent/k (query rulebase bindings remaining-depth succeed)
  "Prove QUERY sharing the caller's cut barrier.

Cut-transparent control constructs must call this at solver entry, before
any nested proof rebinds *CALLER-CUT-TAG*."
  (%prove-with-cut-tag/k query rulebase bindings remaining-depth
                         *caller-cut-tag* succeed))

(defun %prove-raw-clauses/k (goal state succeed)
  "Prove GOAL within one predicate invocation and consume its cut.

The fresh CATCH tag is this invocation cut barrier: a cut in any clause
body throws here, abandoning the remaining clause alternatives."
  (let ((cut-tag (%make-cut-tag)))
    (cl:catch cut-tag
      (dolist (entry (%proof-predicate-entries goal state))
        (let ((clause (%stored-clause-clause entry)))
          (if (null (clause-body clause))
              (%continue-matching-fact goal entry state succeed)
              (when (%matching-rule-p goal clause)
                (%prove-rule/k goal entry state cut-tag succeed))))))))

(progn
  (declaim (inline %rule-program-operand-value))
  (defun %rule-program-operand-value (operand variables)
    (ecase (%clause-template-reference-kind operand)
      (:literal (%clause-template-reference-value operand))
      (:variable (svref variables (%clause-template-reference-value operand)))))
  (defun %unify-rule-program-head (goal program variables environment parent-index)
    "Unify GOAL arguments with PROGRAM operands without materializing a rule head."
    (let ((arguments (cdr goal))
          (operands (%rule-program-head-operands program))
          (extended environment)
          (index parent-index))
      (dotimes (operand-index (length operands) (values extended t index))
        (multiple-value-bind (next-extended ok next-index)
            (%unify-indexed (car arguments)
                            (%rule-program-operand-value
                             (svref operands operand-index) variables)
                            extended index (not (eq index parent-index)))
          (unless ok
            (return-from %unify-rule-program-head
              (values nil nil parent-index)))
          (setf extended next-extended
                index next-index
                arguments (cdr arguments))))))
  (defun %materialize-rule-program-goal (instruction variables)
    "Materialize one instruction with shared fresh variables."
    (let* ((operands (%rule-instruction-operands instruction))
           (arguments nil))
      (loop for index downfrom (1- (length operands)) to 0
            do (push (%rule-program-operand-value
                      (svref operands index) variables)
                     arguments))
      (cons (%rule-instruction-predicate instruction) arguments)))
  (defun %prove-rule-program-body/k (program variables goal-cache pc state succeed)
    "Execute PROGRAM body from PC, materializing each reached goal at most once."
    (let ((body (%rule-program-body program)))
      (if (= pc (length body))
          (funcall succeed state)
          (let* ((cut-tag (proof-state-cut-tag state))
                 (goal (or (svref goal-cache pc)
                           (setf (svref goal-cache pc)
                                 (%materialize-rule-program-goal
                                  (svref body pc) variables)))))
            (%prove-goal/k
             goal state
             (lambda (next-state)
               (%prove-rule-program-body/k
                program variables goal-cache (1+ pc)
                (%state-with next-state :cut-tag cut-tag)
                succeed)))))))
  (defun %prove-rule-program/k (goal program state cut-tag succeed)
    "Resolve GOAL using the restricted immutable rule instruction path."
    (let* ((variables (make-array (%rule-program-variable-count program)))
           (goal-cache (make-array (length (%rule-program-body program))
                                   :initial-element nil))
           (parent-bindings (proof-state-bindings state))
           (parent-index (proof-state-environment-index state)))
      (dotimes (index (length variables))
        (setf (svref variables index) (%fresh-rule-program-variable)))
      (multiple-value-bind (extended ok extended-index)
          (%unify-rule-program-head
           goal program variables parent-bindings parent-index)
        (when ok
          (%with-propagated-bindings
              (propagated propagated-index extended extended-index)
            (%prove-rule-program-body/k
             program variables goal-cache 0
             (%state-descending-into-rule
              state propagated propagated-index goal cut-tag)
             succeed))))))
  (defun %prove-generic-rule/k (goal entry state cut-tag succeed)
    "Resolve GOAL through the general graph-template rule path."
    (let ((fresh-rule (%materialize-stored-clause-for-proof
                       entry (%stored-clause-template entry)))
          (parent-bindings (proof-state-bindings state))
          (parent-index (proof-state-environment-index state)))
      (multiple-value-bind (extended ok extended-index)
          (%unify-indexed goal (clause-head fresh-rule)
                          parent-bindings parent-index nil)
        (when ok
          (%with-propagated-bindings
              (propagated propagated-index extended extended-index)
            (%prove-goals/k
             (clause-body fresh-rule)
             (%state-descending-into-rule
              state propagated propagated-index goal cut-tag)
             succeed))))))
  (defun %prove-rule/k (goal entry state cut-tag succeed)
    "Resolve GOAL against one stored rule; a cut in the body prunes the clause list."
    (let* ((template (%stored-clause-template entry))
           (program (%clause-template-rule-program template)))
      (if program
          (%prove-rule-program/k goal program state cut-tag succeed)
          (%prove-generic-rule/k goal entry state cut-tag succeed)))))

(defmacro %with-first-solution (block-name (continuation-var) &body body)
  "Return a one-shot success continuation for a proof search wrapped in
BLOCK-NAME: run BODY once with CONTINUATION-VAR bound to the reached
proof state, then unwind out of BLOCK-NAME with BODY's final value.

All but the last form of BODY are spliced directly into the lambda body,
so a leading (declare ...) stays legal; the last form supplies the value
passed to (return-from BLOCK-NAME ...)."
  `(lambda (,continuation-var)
     ,@(butlast body)
     (return-from ,block-name ,(car (last body)))))

(defun %provable-p (query rulebase environment depth
                    &optional (module +default-prolog-module+))
  "Return true when QUERY has at least one proof."
  (let ((*unification-scratch*
          (or *unification-scratch* (%make-unification-scratch))))
    (%with-logic-variable-order
      (block provable
        (let ((cut-tag (%make-cut-tag)))
          (cl:catch cut-tag
            (%prove-goals/k
             (%normalize-query query)
             (%make-proof-state
              rulebase
              environment
              (%make-environment-index environment)
              depth
              module
              (%make-rulebase-table-session rulebase)
              cut-tag)
             (%with-first-solution provable (state)
               (declare (cl:ignore state))
               t))))
        nil))))
