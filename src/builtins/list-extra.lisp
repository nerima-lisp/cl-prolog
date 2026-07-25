;;;; library(lists) predicates beyond the ISO core.
;;;;
;;;; These are the deterministic, non-meta list utilities SWI-Prolog exposes
;;;; through library(lists).  Meta-predicates that call a goal per element
;;;; (maplist, foldl, include, exclude, partition) live in apply.lisp.

(in-package #:cl-prolog)

(defun %check-builtin-output-length (count resource environment operation message)
  "Bound COUNT against *max-prolog-builtin-output-length*, raising a catchable
resource_error when it is exceeded.  Returns COUNT.  Shared by the list and
format builtins to cap attacker-controlled allocation."
  (when (and *max-prolog-builtin-output-length*
             (> count *max-prolog-builtin-output-length*))
    (%raise-resource-error resource environment operation message))
  count)

(defun %require-proper-list (value environment operation argument)
  "Return VALUE when it is a proper list, otherwise raise the ISO error."
  (cond
    ((logic-var-p value)
     (%raise-instantiation-error environment operation
                                 (format nil "~A must be instantiated" argument)))
    ((%proper-list-p value) value)
    (t (%raise-type-error "LIST" value environment operation
                          (format nil "~A must be a proper list" argument)))))

(defun %require-number (value environment operation)
  "Return VALUE when it is a Prolog number, otherwise raise the ISO error."
  (cond
    ((logic-var-p value)
     (%raise-instantiation-error environment operation
                                 "list elements must be instantiated numbers"))
    ((or (integerp value) (floatp value)) value)
    (t (%raise-type-error "NUMBER" value environment operation
                          "list elements must be numbers"))))

(defun %resolved-number-list (list-term environment operation argument)
  "Resolve LIST-TERM to a proper list of Prolog numbers."
  (let ((value (logic-substitute list-term environment)))
    (mapcar (lambda (element)
              (%require-number element environment operation))
            (%require-proper-list value environment operation argument))))

;;; sum_list/2, sumlist/2, max_list/2, min_list/2

(define-builtin ((sum_list sumlist) list-term sum) (rulebase environment depth emit)
  (declare (cl:ignore rulebase depth))
  (%unify-emit sum
               (reduce #'+ (%resolved-number-list list-term environment
                                                  (%iso-atom "SUM_LIST") "first argument")
                       :initial-value 0)
               environment emit))

(defmacro %define-list-extremum-builtin (name reducer operation)
  "Define a fold-over-numbers builtin that fails on the empty list."
  `(define-builtin (,name list-term extremum) (rulebase environment depth emit)
     (declare (cl:ignore rulebase depth))
     (let ((numbers (%resolved-number-list list-term environment
                                           (%iso-atom ,operation) "first argument")))
       (when numbers
         (%unify-emit extremum (reduce ,reducer numbers) environment emit)))))

(%define-list-extremum-builtin max_list #'max "MAX_LIST")
(%define-list-extremum-builtin min_list #'min "MIN_LIST")

;;; numlist/3

(define-builtin (numlist low high list-term) (rulebase environment depth emit)
  (declare (cl:ignore rulebase depth))
  (let ((operation (%iso-atom "NUMLIST"))
        (low-value (logic-substitute low environment))
        (high-value (logic-substitute high environment)))
    (dolist (bound (list low-value high-value))
      (cond
        ((logic-var-p bound)
         (%raise-instantiation-error environment operation
                                     "numlist/3 bounds must be instantiated"))
        ((not (integerp bound))
         (%raise-type-error "INTEGER" bound environment operation
                            "numlist/3 bounds must be integers"))))
    (when (<= low-value high-value)
      (%check-builtin-output-length
       (1+ (- high-value low-value)) "LIST_LENGTH" environment operation
       "numlist/3 range exceeds the configured length limit")
      (%unify-emit list-term
                   (loop for n from low-value to high-value collect n)
                   environment emit))))

;;; list_to_set/2 -- deduplicate under standard order of terms (==),
;;; preserving first-occurrence order.  O(n log n): tag each element with its
;;; index, sort by standard order (index breaks ties), drop adjacent
;;; duplicates keeping the earliest index, then restore original order.

(define-builtin (list_to_set list-term set) (rulebase environment depth emit)
  (declare (cl:ignore rulebase depth))
  (let* ((value (logic-substitute list-term environment))
         (elements (%require-proper-list value environment
                                         (%iso-atom "LIST_TO_SET") "first argument"))
         (tagged (loop for element in elements
                       for index from 0
                       collect (cons index element)))
         (sorted (stable-sort (copy-list tagged)
                              (lambda (a b)
                                (let ((order (%compare-terms (cdr a) (cdr b))))
                                  (if (zerop order)
                                      (< (car a) (car b))
                                      (minusp order))))))
         (unique '())
         (previous nil))
    (dolist (cell sorted)
      (when (or (null previous)
                (not (zerop (%compare-terms (cdr previous) (cdr cell)))))
        (push cell unique))
      (setf previous cell))
    (%unify-emit set
                 (mapcar #'cdr (sort unique #'< :key #'car))
                 environment emit)))

;;; subtract/3, intersection/3, union/3 -- membership tested by unifiability.
;;; Unlike SWI's memberchk, a successful unification's bindings are discarded
;;; rather than propagated, so these never bind variables in the caller's
;;; terms; on ground lists the behavior is identical to SWI.  This divergence
;;; is documented in docs/src/semantics.md.

(defun %unifiable-member-p (item list environment)
  "True when ITEM unifies with some element of LIST, discarding bindings."
  (some (lambda (element) (nth-value 1 (unify item element environment))) list))

(define-builtin (subtract set-a set-b difference) (rulebase environment depth emit)
  (declare (cl:ignore rulebase depth))
  (let ((operation (%iso-atom "SUBTRACT"))
        (a (logic-substitute set-a environment))
        (b (logic-substitute set-b environment)))
    (%require-proper-list a environment operation "first argument")
    (%require-proper-list b environment operation "second argument")
    (%unify-emit difference
                 (remove-if (lambda (element)
                              (%unifiable-member-p element b environment))
                            a)
                 environment emit)))

(define-builtin (intersection set-a set-b common) (rulebase environment depth emit)
  (declare (cl:ignore rulebase depth))
  (let ((operation (%iso-atom "INTERSECTION"))
        (a (logic-substitute set-a environment))
        (b (logic-substitute set-b environment)))
    (%require-proper-list a environment operation "first argument")
    (%require-proper-list b environment operation "second argument")
    (%unify-emit common
                 (remove-if-not (lambda (element)
                                  (%unifiable-member-p element b environment))
                                a)
                 environment emit)))

(define-builtin (union set-a set-b combined) (rulebase environment depth emit)
  (declare (cl:ignore rulebase depth))
  (let ((operation (%iso-atom "UNION"))
        (a (logic-substitute set-a environment))
        (b (logic-substitute set-b environment)))
    (%require-proper-list a environment operation "first argument")
    (%require-proper-list b environment operation "second argument")
    ;; union(A, B, C): the elements of A not in B, followed by all of B.
    (%unify-emit combined
                 (append (remove-if (lambda (element)
                                      (%unifiable-member-p element b environment))
                                    a)
                         b)
                 environment emit)))

;;; permutation/2 -- nondeterministic; enumerates permutations of the
;;; instantiated list argument.

(define-builtin (permutation list-term permuted) (rulebase environment depth emit)
  (declare (cl:ignore rulebase depth))
  (let* ((operation (%iso-atom "PERMUTATION"))
         (source (logic-substitute list-term environment))
         (target (logic-substitute permuted environment)))
    (multiple-value-bind (elements result-variable)
        (cond
          ((%proper-list-p source) (values source permuted))
          ((%proper-list-p target) (values target list-term))
          (t (%raise-instantiation-error
              environment operation
              "permutation/2 requires one proper-list argument")))
      (labels ((permute (remaining accumulator current-environment)
                 (if (null remaining)
                     (%unify-emit result-variable (reverse accumulator)
                                  current-environment emit)
                     ;; Select each position in a single pass: SKIPPED holds
                     ;; the already-passed elements (reversed), so the rest is
                     ;; built with one REVAPPEND instead of NTH + two SUBSEQs.
                     ;; Handles duplicate and numeric elements without EQ.
                     (let ((skipped '()))
                       (loop for cell on remaining
                             do (permute (revappend skipped (cdr cell))
                                         (cons (car cell) accumulator)
                                         current-environment)
                                (push (car cell) skipped))))))
        (permute elements '() environment)))))
