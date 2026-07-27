;;;; Tabling data: the %table-entry/%table-session structs recording
;;;; memoized answers, and variant canonicalization (%canonicalize-variant,
;;;; %variant-graph-key, %instantiate-variant) used to key and replay them.

(in-package #:cl-prolog)

(defstruct (%table-entry (:copier nil)
                         (:constructor %make-table-entry ()))
  "Variant-call answers accumulated during one tabled proof."
  (answers '() :type list)
  (answers-tail '() :type list)
  (answer-count 0 :type (integer 0 *))
  (answer-index (make-hash-table :test #'equal)
                :type hash-table :read-only t)
  (cyclic-answer-index (make-hash-table :test #'equal)
                       :type hash-table :read-only t))

(defstruct (%table-answer (:copier nil)
                          (:constructor %make-table-answer
                              (term contains-variables-p)))
  "An immutable canonical answer and whether replay must freshen variables."
  (term nil :read-only t)
  (contains-variables-p nil :type boolean :read-only t))

(defstruct (%table-session
                         (:copier nil)
                         (:constructor %make-table-session
                             (entries module-entries predicate-entries)))
  "Tables shared by every proof nested within one public query."
  (entries (make-hash-table :test (function equal))
           :type hash-table :read-only t)
  (module-entries (make-hash-table :test (function equal))
                  :type hash-table :read-only t)
  (predicate-entries (make-hash-table :test (function equal))
                     :type hash-table :read-only t))

(defparameter +variant-variable-marker+ (gensym "VARIANT-VARIABLE-")
  "Unforgeable marker used in canonical table keys and answers.")

(defun %make-rulebase-table-session (rulebase)
  (declare (ignore rulebase))
  (%make-table-session
   (make-hash-table :test (function equal))
   (make-hash-table :test (function equal))
   (make-hash-table :test (function equal))))

(defun %canonicalize-variant (term &optional environment-index)
  "Rename TERM variables by first occurrence after resolving ENVIRONMENT-INDEX.
The second value reports whether the resolved graph contains a cons cycle; the
third reports whether its canonical form contains logical variable markers."
  (let ((variables (make-hash-table :test (function eq)))
        (copies (make-hash-table :test (function eq)))
        (active (make-hash-table :test (function eq)))
        (next-index 0)
        (cyclic-p nil)
        (contains-variables-p nil))
    (labels ((resolve (node)
               (if environment-index
                   (%walk-term-indexed node environment-index)
                   node))
             (canonicalize (term)
               (let ((node (resolve term)))
                 (cond
                   ((logic-var-p node)
                    (setf contains-variables-p t)
                    (or (gethash node variables)
                        (setf (gethash node variables)
                              (list +variant-variable-marker+
                                    (prog1 next-index (incf next-index))))))
                   ((consp node)
                    (multiple-value-bind (copy present-p)
                        (gethash node copies)
                      (if present-p
                          (progn
                            (when (gethash node active)
                              (setf cyclic-p t))
                            copy)
                          (let ((copy (cons nil nil)))
                            (setf (gethash node copies) copy
                                  (gethash node active) t
                                  (car copy) (canonicalize (car node))
                                  (cdr copy) (canonicalize (cdr node)))
                            (remhash node active)
                            copy))))
                   (t node)))))
      (values (canonicalize term) cyclic-p contains-variables-p))))

(defun %variant-graph-key (term)
  "Return an EQUAL-safe encoding of TERM's cons graph."
  (let ((identities (make-hash-table :test #'eq))
        (next-index 0))
    (labels ((encode (node)
               (if (consp node)
                   (multiple-value-bind (index present-p)
                       (gethash node identities)
                     (if present-p
                         (list :reference index)
                         (let ((index (prog1 next-index
                                        (incf next-index))))
                           (setf (gethash node identities) index)
                           (list :cons index
                                 (encode (car node))
                                 (encode (cdr node))))))
                   (list :atom node))))
      (encode term))))

(defun %instantiate-variant (term)
  "Replace canonical variable markers in TERM with fresh logic variables.
Ground subtrees are shared because unification never mutates terms."
  (let ((variables nil)
        (copies (make-hash-table :test #'eq)))
    (labels ((instantiate (node)
               (cond
                 ((and (consp node)
                       (eq (first node) +variant-variable-marker+)
                       (consp (rest node))
                       (null (cddr node)))
                  (let ((table (or variables
                                   (setf variables
                                         (make-hash-table :test #'equal)))))
                    (or (gethash node table)
                        (setf (gethash node table)
                              (fresh-logic-variable "?TABLE")))))
                 ((consp node)
                  (multiple-value-bind (copy present-p)
                      (gethash node copies)
                    (if present-p
                        copy
                        (let ((copy (cons nil nil)))
                          (setf (gethash node copies) copy)
                          (let ((new-car (instantiate (car node)))
                                (new-cdr (instantiate (cdr node))))
                            (setf (car copy) new-car
                                  (cdr copy) new-cdr)
                            (if (and (eq new-car (car node))
                                     (eq new-cdr (cdr node)))
                                (progn
                                  (setf (gethash node copies) node)
                                  node)
                                copy))))))
                 (t node))))
      (instantiate term))))
