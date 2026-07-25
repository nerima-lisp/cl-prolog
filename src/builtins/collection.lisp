(in-package #:cl-prolog)

(defun %strip-existential-quantifiers (goal)
  "Return GOAL without leading (^ QUANTIFIED GOAL) forms and their variables."
  (let ((variables '()))
    (loop while (and (%proper-list-p goal)
                     (= (length goal) 3)
                     (and (symbolp (first goal))
                          (string= (symbol-name (first goal)) "^")))
          do (dolist (variable (%collect-variables (second goal)))
               (pushnew variable variables :test #'eq))
             (setf goal (third goal)))
    (values goal (nreverse variables))))

(defun %collect-template-solutions (template goal rulebase environment depth)
  "Collect copied TEMPLATE instances for every proof of GOAL."
  (let ((solutions '()))
    (%prove-bindings/k
     (logic-substitute goal environment)
     rulebase environment depth
     (lambda (extended)
       (push (%freshen-term (logic-substitute template extended)
                            (make-hash-table :test #'eq))
             solutions)))
    (nreverse solutions)))

(defun %bagof-free-variables (template goal existential-variables)
  "Return the free variables by which BAGOF and SETOF group solutions."
  (let ((template-variables (%collect-variables template)))
    (remove-if (lambda (variable)
                 (or (member variable template-variables :test #'eq)
                     (member variable existential-variables :test #'eq)))
               (%collect-variables goal))))

(defun %collect-grouped-solutions (template goal free-variables
                                    rulebase environment depth)
  "Collect (KEY . TEMPLATE) pairs while preserving proof order."
  (let ((solutions '()))
    (%prove-bindings/k
     (logic-substitute goal environment)
     rulebase environment depth
     (lambda (extended)
       (let ((table (make-hash-table :test #'eq)))
         (push (cons (%freshen-term
                      (mapcar (lambda (variable)
                                (logic-substitute variable extended))
                              free-variables)
                      table)
                     (%freshen-term (logic-substitute template extended) table))
               solutions))))
    (nreverse solutions)))

(defun %group-adjacent-by (items same-group-p)
  "Split ITEMS into runs of adjacent elements, starting a new run whenever
SAME-GROUP-P rejects the pair (run head, current item).  Runs and the items
within them keep their original order."
  (let ((groups '())
        (current '())
        (head nil))
    (dolist (item items)
      (if (and current (funcall same-group-p head item))
          (push item current)
          (progn
            (when current (push (nreverse current) groups))
            (setf head item
                  current (list item)))))
    (when current (push (nreverse current) groups))
    (nreverse groups)))

(defun %partition-solution-groups (solutions)
  "Partition SOLUTIONS by variant-equivalent keys in standard term order."
  (let* ((entries
           (stable-sort
            (mapcar (lambda (solution)
                      (list (%canonicalize-variant (car solution))
                            (car solution)
                            (cdr solution)))
                    solutions)
            (lambda (left right)
              (minusp (%compare-terms (first left) (first right))))))
         (groups (%group-adjacent-by
                  entries
                  (lambda (head entry)
                    (zerop (%compare-terms (first head) (first entry)))))))
    (stable-sort (mapcar (lambda (group)
                           (cons (second (first group))
                                 (mapcar #'third group)))
                         groups)
                 #'%prolog-term< :key #'car)))

(defun %emit-solution-group (free-variables key values bag environment emit)
  "Unify one grouped KEY and VALUES with the caller and emit on success."
  (let ((extended environment)
        (ok t))
    (loop for variable in free-variables
          for value in key
          while ok
          do (multiple-value-setq (extended ok)
               (unify variable value extended)))
    (when ok
      (%unify-emit bag values extended emit))))

(defun %prolog-term< (left right)
  "Compare terms using the standard Prolog order."
  (minusp (%compare-terms left right)))

(defun %standard-term-sort (values)
  "Return a stable standard-order copy of VALUES."
  (stable-sort (copy-list values) #'%prolog-term<))

(defun %standard-term-sort-unique (values)
  "Sort VALUES and remove adjacent terms whose standard comparison is zero."
  (let ((ordered (%standard-term-sort values))
        (result '()))
    (dolist (value ordered (nreverse result))
      (unless (and result (zerop (%compare-terms (car result) value)))
        (push value result)))))

(defun %emit-bagof-solutions (template quantified-goal bag setp
                              rulebase environment depth emit)
  (multiple-value-bind (goal existential-variables)
      (%strip-existential-quantifiers quantified-goal)
    (let* ((free-variables
             (%bagof-free-variables template goal existential-variables))
           (solutions
             (%collect-grouped-solutions template goal free-variables
                                         rulebase environment depth)))
      (dolist (group (%partition-solution-groups solutions))
        (let ((values (cdr group)))
          (when setp
            (setf values (%standard-term-sort-unique values)))
          (%emit-solution-group free-variables (car group) values bag
                                environment emit))))))

(define-builtin (findall template goal bag) (rulebase environment depth emit)
  (%unify-emit bag
               (%collect-template-solutions template goal rulebase environment depth)
               environment emit))

(define-builtin (findall template goal bag tail)
    (rulebase environment depth emit)
  (let ((solutions
          (%collect-template-solutions template goal rulebase environment depth)))
    (%unify-emit bag
                 (append solutions tail)
                 environment emit)))

(define-builtin (bagof template goal bag) (rulebase environment depth emit)
  (%emit-bagof-solutions template goal bag nil rulebase environment depth emit))

(define-builtin (setof template goal bag) (rulebase environment depth emit)
  (%emit-bagof-solutions template goal bag t rulebase environment depth emit))

(defun %key-value-term-p (term)
  (and (%proper-list-p term)
       (= (length term) 3)
       (symbolp (first term))
       (string= (symbol-name (first term)) "-")))

(defun %keysort-key (pair environment)
  (unless (%key-value-term-p pair)
    (%raise-type-error "PAIR" pair environment (%iso-atom "KEYSORT")
                       "KEYSORT/2 expects Key-Value pairs"))
  (second pair))

(defmacro define-standard-order-sort-builtin (name operation-name sort-fn)
  "Define NAME as a builtin resolving INPUT to a proper list and unifying
SORTED with (SORT-FN list), reporting ISO errors under OPERATION-NAME."
  `(define-builtin (,name input sorted) (rulebase environment depth emit)
     (let* ((values (%require-proper-list
                     (logic-substitute input environment)
                     environment (%iso-atom ,operation-name) "the input list"))
            (ordered (,sort-fn values)))
       (%unify-emit sorted ordered environment emit))))

(define-standard-order-sort-builtin sort "SORT" %standard-term-sort-unique)
(define-standard-order-sort-builtin msort "MSORT" %standard-term-sort)

(define-builtin (keysort input sorted) (rulebase environment depth emit)
  (let ((pairs (%require-proper-list (logic-substitute input environment)
                                       environment (%iso-atom "KEYSORT")
                                       "the input list")))
    (dolist (pair pairs)
      (%keysort-key pair environment))
    (%unify-emit sorted
                 (stable-sort (copy-list pairs) #'%prolog-term<
                              :key (lambda (pair)
                                     (%keysort-key pair environment)))
                 environment emit)))

;;; sort/4 -- key-and-order sort.  Key 0 selects the whole term; a positive
;;; key selects that argument of each compound.  Order is one of @<, @=<, @>,
;;; @>= ; @< and @> remove elements comparing equal on the key.

(defun %sort4-key (element key environment operation)
  "Return the sort key of ELEMENT for sort/4 KEY (0 = whole term)."
  (if (zerop key)
      element
      (progn
        (unless (and (%proper-list-p element) (> (length element) key))
          (%raise-type-error "COMPOUND" element environment operation
                             "sort/4 key argument exceeds the term's arity"))
        (nth key element))))

(defun %sort4-order (order environment operation)
  "Return (VALUES ASCENDING-P DEDUP-P) for a sort/4 order atom."
  (unless (%term-atom-p order)
    (if (logic-var-p order)
        (%raise-instantiation-error environment operation
                                    "sort/4 order must be instantiated")
        (%raise-type-error "ATOM" order environment operation
                           "sort/4 order must be an atom")))
  (let ((name (symbol-name order)))
    (cond
      ((string-equal name "@<")  (values t t))
      ((string-equal name "@=<") (values t nil))
      ((string-equal name "@>")  (values nil t))
      ((string-equal name "@>=") (values nil nil))
      (t (%raise-domain-error "ORDER" order environment operation
                              "sort/4 order must be @<, @=<, @> or @>=")))))

(define-builtin (sort key order input sorted) (rulebase environment depth emit)
  (let* ((operation (%iso-atom "SORT"))
         (key-value (logic-substitute key environment))
         (order-value (logic-substitute order environment))
         (values (%require-proper-list (logic-substitute input environment)
                                              environment operation
                                              "the input list")))
    (%require-bounded-integer key-value environment operation "sort/4 key")
    (multiple-value-bind (ascending-p dedup-p)
        (%sort4-order order-value environment operation)
      ;; Extract every key up front so an out-of-range key is reported even for
      ;; short lists and each key is computed once.
      (let* ((tagged (mapcar (lambda (element)
                               (cons (%sort4-key element key-value
                                                 environment operation)
                                     element))
                             values))
             (ordered (stable-sort tagged
                                   (lambda (a b)
                                     (let ((c (%compare-terms (car a) (car b))))
                                       (if ascending-p (minusp c) (plusp c))))))
             (result (if dedup-p
                         (let ((kept '()))
                           (dolist (cell ordered (nreverse kept))
                             (unless (and kept
                                          (zerop (%compare-terms (car (car kept))
                                                                 (car cell))))
                               (push cell kept))))
                         ordered)))
        (%unify-emit sorted (mapcar #'cdr result) environment emit)))))

;;; predsort/3 -- sort with a user comparison predicate call(Pred, Order, A, B),
;;; dropping elements whose comparison yields `='.

(defun %predsort-order (closure a b rulebase environment depth operation fail-tag)
  "Call CLOSURE(Order, A, B) and return -1/0/1 from the resulting order atom.
Throws FAIL-TAG when the comparison predicate has no proof, so predsort/3
fails (as in SWI) rather than raising."
  (let ((order-var (fresh-logic-variable "?PREDSORT-ORDER")))
    (multiple-value-bind (result-environment succeeded-p)
        (%first-proof-environment
         (%extend-callable-goal closure (list order-var a b) environment operation)
         rulebase environment depth)
      (unless succeeded-p
        (cl:throw fail-tag :fail))
      (let ((order (logic-substitute order-var result-environment)))
        (unless (%term-atom-p order)
          (%raise-type-error "ATOM" order environment operation
                             "predsort/3 comparison must bind an order atom"))
        (let ((name (symbol-name order)))
          (cond ((string-equal name "<") -1)
                ((string-equal name "=") 0)
                ((string-equal name ">") 1)
                (t (%raise-domain-error "ORDER" order environment operation
                                        "predsort/3 order must be <, = or >"))))))))

(define-builtin (predsort goal input sorted) (rulebase environment depth emit)
  (let* ((operation (%iso-atom "PREDSORT"))
         (closure (logic-substitute goal environment))
         (values (%require-proper-list (logic-substitute input environment)
                                              environment operation
                                              "the input list"))
         (fail-tag (list 'predsort-fail)))
    (when (logic-var-p closure)
      (%raise-instantiation-error environment operation
                                  "predsort/3 comparison predicate must be instantiated"))
    ;; Merge sort so each pair is compared once; `=' drops the later element.
    ;; MERGE-RUNS is iterative (accumulate + NREVERSE) to keep the control
    ;; stack O(log n) on large lists.
    (labels ((merge-runs (left right)
               (let ((accumulator '()))
                 (loop
                   (cond
                     ((null left) (return (nreconc accumulator right)))
                     ((null right) (return (nreconc accumulator left)))
                     (t (let ((order (%predsort-order closure (car left) (car right)
                                                      rulebase environment depth
                                                      operation fail-tag)))
                          (cond
                            ((minusp order) (push (pop left) accumulator))
                            ((plusp order) (push (pop right) accumulator))
                            (t ;; equal: keep the left element, drop the right
                             (push (pop left) accumulator)
                             (pop right)))))))))
             (sort-run (items)
               (if (or (null items) (null (cdr items)))
                   items
                   (let* ((half (floor (length items) 2))
                          (left (subseq items 0 half))
                          (right (subseq items half)))
                     (merge-runs (sort-run left) (sort-run right))))))
      (let ((result (cl:catch fail-tag (sort-run values))))
        (unless (eq result :fail)
          (%unify-emit sorted result environment emit))))))

;;; aggregate_all/3 -- count/sum/max/min/bag/set reductions over a goal.

(defun %aggregate-numbers (expr-template goal rulebase environment depth)
  "Collect the solutions of EXPR-TEMPLATE over GOAL and evaluate each as an
arithmetic expression, matching SWI's sum/max/min templates (a bare number
evaluates to itself)."
  (mapcar (lambda (value)
            (%evaluate-arithmetic-expression value environment))
          (%collect-template-solutions expr-template goal
                                       rulebase environment depth)))

(defmacro define-aggregate-spec-table (name &body definitions)
  `(defparameter ,name
     (list ,@(loop for (tag . body) in definitions
                   collect `(cons ,tag
                                  (lambda (argument collect numbers)
                                    (declare (cl:ignorable argument collect numbers))
                                    ,@body))))
     "Data table mapping each aggregate_all/3 tag to a reducer returning
\(VALUES RESULT FOUNDP); a false FOUNDP fails the goal instead of unifying.
COLLECT gathers ARGUMENT's solutions, NUMBERS additionally evaluates them."))

(define-aggregate-spec-table +aggregate-specs+
  ("count" (values (length (funcall collect argument)) t))
  ("sum" (values (reduce #'+ (funcall numbers argument) :initial-value 0) t))
  ;; max/min over no solutions fails rather than raising.
  ("max" (let ((found (funcall numbers argument)))
           (values (and found (reduce #'max found)) (and found t))))
  ("min" (let ((found (funcall numbers argument)))
           (values (and found (reduce #'min found)) (and found t))))
  ("bag" (values (funcall collect argument) t))
  ("set" (values (%standard-term-sort-unique (funcall collect argument)) t)))

(define-builtin (aggregate_all spec goal result) (rulebase environment depth emit)
  (let* ((operation (%iso-atom "AGGREGATE_ALL"))
         (resolved-spec (logic-substitute spec environment)))
    (flet ((collect (expression)
             (%collect-template-solutions expression goal rulebase
                                          environment depth))
           (numbers (expression)
             (%aggregate-numbers expression goal rulebase environment depth)))
      (multiple-value-bind (tag argument)
          (cond
            ;; count/0 as the bare atom `count'; any other bare atom is a
            ;; domain error rather than a zero-argument reduction.
            ((and (%term-atom-p resolved-spec)
                  (string-equal (symbol-name resolved-spec) "count"))
             (values "count" t))
            ((and (%proper-list-p resolved-spec) (= (length resolved-spec) 2)
                  (%term-atom-p (first resolved-spec)))
             (values (symbol-name (first resolved-spec)) (second resolved-spec)))
            ((logic-var-p resolved-spec)
             (%raise-instantiation-error
              environment operation
              "aggregate_all/3 template must be instantiated")))
        (let ((reducer (cdr (assoc tag +aggregate-specs+ :test #'string-equal))))
          (unless reducer
            (%raise-domain-error "AGGREGATE_SPEC" resolved-spec environment
                                 operation
                                 "unsupported aggregate_all/3 template"))
          (multiple-value-bind (value foundp)
              (funcall reducer argument #'collect #'numbers)
            (when foundp
              (%unify-emit result value environment emit))))))))

(define-builtin (:when test &rest variables) (rulebase environment depth emit)
  ;; TEST receives the solved value of each of VARIABLES.  The DSL compiles
  ;; (:when EXPR) guards into such functions; hand-written queries must pass
  ;; a function object too.
  (unless (functionp test)
    (%invalid-goal (list* :when test variables)
                   ":WHEN needs a guard function, got ~S (use the PROLOG ~
                    macro to compile expression guards)" test))
  (when (apply test
               (mapcar (lambda (variable)
                         (logic-substitute variable environment))
                       variables))
    (funcall emit environment)))
