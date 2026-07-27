;;;; Unification and substitution.
;;;;
;;;; Environments are association lists mapping logic variables to terms.
;;;; They are persistent: UNIFY never mutates an environment, it extends it,
;;;; so backtracking is simply "keep using the older environment".
;;;; Variable identity lives in logic-variable.lisp and the environment
;;;; index it unifies against lives in environment-index.lisp.

(in-package #:cl-prolog)

(defun %occurs-p-indexed (var term index)
    (let ((seen nil))
      (labels ((occurs-p (node)
                 (let ((resolved (%walk-term-indexed node index)))
              (cond
                ((eq var resolved) t)
                ((not (consp resolved)) nil)
                ((and seen (gethash resolved seen)) nil)
                (t
                  (unless seen
                    (setf seen (make-hash-table :test (function eq))))
                  (setf (gethash resolved seen) t)
                  (or (occurs-p (car resolved)) (occurs-p (cdr resolved))))))))
        (occurs-p term))))
  (defun %occurs-p (var term env)
    (%occurs-p-indexed var term (%make-environment-index env)))

(defconstant +unification-scratch-inline-pair-capacity+ 32)
  (defstruct
      (%unification-scratch
        (:constructor %make-unification-scratch ()))
    (pairs nil :type (or null simple-vector))
    (pair-count 0 :type fixnum)
    (pair-table nil :type (or null hash-table))
    (hash-mode-p nil :type boolean)
    (active-p nil :type boolean))
  (defvar *unification-scratch* nil)
  (declaim
    (inline
      %unification-scratch-remember-pair
      %reset-unification-scratch))
  (defun %unification-scratch-remember-pair (scratch left right)
  "Return true for a remembered directed EQ pair; otherwise remember it."
  (declare (type %unification-scratch scratch)
           (optimize (speed 3) (safety 1)))
  (if (%unification-scratch-hash-mode-p scratch)
      (let* ((table
               (the hash-table
                 (%unification-scratch-pair-table scratch)))
             (rights
               (or (gethash left table)
                   (setf (gethash left table)
                         (make-hash-table :test (function eq))))))
        (multiple-value-bind (value presentp) (gethash right rights)
          (declare (ignore value))
          (if presentp
              t
              (progn
                (setf (gethash right rights) t)
                (incf (%unification-scratch-pair-count scratch))
                nil))))
      (let ((pairs (%unification-scratch-pairs scratch))
            (count (%unification-scratch-pair-count scratch)))
        (declare (type (or null simple-vector) pairs)
                 (type fixnum count))
        (when pairs
          (dotimes (pair-index count)
            (let ((offset (* 2 pair-index)))
              (when
                  (and
                    (eq left (svref (the simple-vector pairs) offset))
                    (eq right
                        (svref (the simple-vector pairs) (1+ offset))))
                (return-from %unification-scratch-remember-pair t)))))
        (if (< count +unification-scratch-inline-pair-capacity+)
            (let* ((pairs
                     (or pairs
                         (setf (%unification-scratch-pairs scratch)
                               (make-array
                                 (* 2
                                    +unification-scratch-inline-pair-capacity+)))))
                   (offset (* 2 count)))
              (setf (svref pairs offset) left
                    (svref pairs (1+ offset)) right
                    (%unification-scratch-pair-count scratch) (1+ count))
              nil)
            (let ((table
                    (or (%unification-scratch-pair-table scratch)
                        (setf
                          (%unification-scratch-pair-table scratch)
                          (make-hash-table
                            :test
                            (function eq)
                            :size
                            +unification-scratch-inline-pair-capacity+)))))
              (dotimes (pair-index count)
                (let* ((offset (* 2 pair-index))
                       (stored-left (svref (the simple-vector pairs) offset))
                       (stored-right
                         (svref (the simple-vector pairs) (1+ offset)))
                       (rights
                         (or (gethash stored-left table)
                             (setf (gethash stored-left table)
                                   (make-hash-table :test (function eq))))))
                  (setf (gethash stored-right rights) t)))
              (let ((rights
                      (or (gethash left table)
                          (setf (gethash left table)
                                (make-hash-table :test (function eq))))))
                (setf (gethash right rights) t))
              (setf (%unification-scratch-hash-mode-p scratch) t
                    (%unification-scratch-pair-count scratch) (1+ count))
              nil)))))
  (defun %reset-unification-scratch (scratch)
  "Release references retained by SCRATCH and make it reusable."
  (declare (type %unification-scratch scratch)
           (optimize (speed 3) (safety 1)))
  (let ((pairs (%unification-scratch-pairs scratch))
        (count (%unification-scratch-pair-count scratch))
        (table (%unification-scratch-pair-table scratch)))
    (when pairs
      (fill
        pairs nil
        :end
        (* 2
           (min count +unification-scratch-inline-pair-capacity+))))
    (when table
      (clrhash table))
    (setf (%unification-scratch-pair-count scratch) 0
          (%unification-scratch-hash-mode-p scratch) nil
          (%unification-scratch-active-p scratch) nil))
  nil)

(defun %unify-indexed (left right env base-index
                       &optional index-owned-p (occurs-check t))
  "Unify using BASE-INDEX, returning environment, success flag, and new index.
INDEX-OWNED-P permits in-place extension of a caller-owned transient index.
When OCCURS-CHECK is NIL the occurs check is skipped, so a variable may bind to
a term containing it (producing a rational/cyclic term)."
  (let* ((candidate *unification-scratch*)
         (scratch
           (if (and candidate
                    (not (%unification-scratch-active-p candidate)))
               candidate
               (%make-unification-scratch))))
    (let ((*unification-scratch* scratch))
      (setf (%unification-scratch-active-p scratch) t)
      (unwind-protect
          (let ((index base-index)
                (copied-p index-owned-p))
            (labels ((ensure-writable-index ()
                       (unless copied-p
                         (setf index (%copy-environment-index index)
                               copied-p t)))
                     (extend-environment (variable term environment)
                       (ensure-writable-index)
                       (let ((binding (cons variable term)))
                         (push
                           (cons binding
                                 (%environment-index-next-binding-rank index))
                           (%environment-index-overlay index))
                         (incf (%environment-index-overlay-length index))
                         (decf (%environment-index-next-binding-rank index))
                         (when (= (%environment-index-overlay-length index)
                                  +environment-index-overlay-threshold+)
                           (setf index (%compact-environment-index index)))
                         (cons binding environment)))
                     (unify-terms (left right environment)
                       (setf left (%walk-term-indexed left index)
                             right (%walk-term-indexed right index))
                       (cond
                         ((eq left right) (values environment t))
                         ((logic-var-p left)
                          (if (and occurs-check
                                   (%occurs-p-indexed left right index))
                              (values nil nil)
                              (values
                                (extend-environment left right environment)
                                t)))
                         ((logic-var-p right)
                          (unify-terms right left environment))
                         ((and (consp left) (consp right))
                          (if (%unification-scratch-remember-pair
                                scratch left right)
                              (values environment t)
                              (multiple-value-bind (extended ok)
                                  (unify-terms
                                    (car left)
                                    (car right)
                                    environment)
                                (if ok
                                    (unify-terms
                                      (cdr left)
                                      (cdr right)
                                      extended)
                                    (values nil nil)))))
                         ((and
                            (symbolp left)
                            (symbolp right)
                            (%same-atom-text-p left right))
                          (values environment t))
                         ((equal left right) (values environment t))
                         (t (values nil nil)))))
              (multiple-value-bind (extended ok)
                  (unify-terms left right env)
                (if ok
                    (values extended t index)
                    (values nil nil base-index)))))
        (%reset-unification-scratch scratch)))))

(defun unify (left right &optional (env (quote ())) (occurs-check t))
  "Unify LEFT and RIGHT against ENV.

Returns (VALUES EXTENDED-ENV T) on success and (VALUES NIL NIL) on failure.
OCCURS-CHECK defaults to T; pass NIL to allow cyclic bindings (see the
`occurs_check' Prolog flag).  Kept positional (not &key) so the hot
clause-resolution path pays no keyword-dispatch cost."
  (let ((*unification-scratch* (%make-unification-scratch)))
    (multiple-value-bind (extended ok index)
        (%unify-indexed
          left right env (%make-environment-index env 1) t occurs-check)
      (declare (ignore index))
      (values extended ok))))

(defun %logic-substitute-indexed (template index)
  "Apply INDEX to TEMPLATE while preserving dotted and cyclic structure."
  (let ((root (%walk-term-indexed template index)))
    (if (not (consp root))
        root
        (let ((copies (%make-freshening-map)))
          (labels ((copy-resolved-term (resolved)
                     (if (consp resolved)
                         (multiple-value-bind (copy present-p)
                             (%freshening-map-lookup resolved copies)
                           (if present-p
                               copy
                               (let ((copy (cons nil nil)))
                                 (%freshening-map-insert resolved copy copies)
                                 (setf (car copy)
                                       (substitute-term (car resolved))
                                       (cdr copy)
                                       (substitute-term (cdr resolved)))
                                 copy)))
                         resolved))
                   (substitute-term (term)
                     (copy-resolved-term
                       (%walk-term-indexed term index))))
            (copy-resolved-term root))))))

(defun logic-substitute (template env)
  "Recursively apply ENV to TEMPLATE, preserving dotted structure."
  (%logic-substitute-indexed template (%make-environment-index env)))

(defun %collect-variables (term)
  "Return the logic variables of TERM in first-appearance order."
  (let ((seen (make-hash-table :test #'eq))
        (seen-conses (make-hash-table :test #'eq))
        (variables '()))
    (labels ((walk (node)
               (cond
            ((logic-var-p node)
              (when *logic-variable-ordinals*
                (%register-logic-variable node))
              (unless (gethash node seen)
                (setf (gethash node seen) t)
                (push node variables)))
            ((consp node)
              (unless (gethash node seen-conses)
                (setf (gethash node seen-conses) t)
                (walk (car node))
                (walk (cdr node)))))))
      (walk term))
    (nreverse variables)))

(defconstant +freshening-map-threshold+ 12)
  (defstruct (%freshening-map (:constructor %make-freshening-map ()))
    (entries (make-array (* 2 +freshening-map-threshold+) :initial-element nil))
    (count 0 :type fixnum)
    (table nil :type (or null hash-table)))
  (defun %freshening-map-lookup (key mapping)
    (if (hash-table-p mapping)
        (gethash key mapping)
        (let ((table (%freshening-map-table mapping)))
          (if table
              (gethash key table)
              (let ((entries (%freshening-map-entries mapping))
                    (count (%freshening-map-count mapping)))
                (loop for index below count
                      for offset = (* index 2)
                      when (eq key (svref entries offset))
                        do (return (values (svref entries (1+ offset)) t))
                      finally (return (values nil nil))))))))
  (defun %freshening-map-insert (key value mapping)
    (cond
      ((hash-table-p mapping)
       (setf (gethash key mapping) value))
      ((%freshening-map-table mapping)
       (setf (gethash key (%freshening-map-table mapping)) value))
      (t
       (let ((count (%freshening-map-count mapping))
             (entries (%freshening-map-entries mapping)))
         (if (< count +freshening-map-threshold+)
             (progn
               (setf (svref entries (* count 2)) key
                     (svref entries (1+ (* count 2))) value)
               (incf (%freshening-map-count mapping))
               value)
             (let ((table (make-hash-table
                            :test (function eq)
                            :size (* 2 +freshening-map-threshold+))))
               (dotimes (index count)
                 (let ((offset (* index 2)))
                   (setf (gethash (svref entries offset) table)
                         (svref entries (1+ offset)))))
               (setf (%freshening-map-table mapping) table
                     (%freshening-map-entries mapping) nil
                     (gethash key table) value)
               value))))))
  (defun %freshen-term
      (term table &optional (copies (make-hash-table :test (function eq))))
    "Copy TERM, replacing each logic variable via TABLE with a fresh one.
COPIES preserves cons identity and cycles across calls that share it."
    (labels ((freshen (node)
               (cond
                 ((logic-var-p node)
                  (multiple-value-bind (fresh present-p)
                      (%freshening-map-lookup node table)
                    (if present-p
                        fresh
                        (%freshening-map-insert
                          node (fresh-logic-variable "?FRESH") table))))
                 ((consp node)
                  (multiple-value-bind (copy present-p)
                      (%freshening-map-lookup node copies)
                    (if present-p
                        copy
                        (let ((copy (cons nil nil)))
                          (%freshening-map-insert node copy copies)
                          (setf (car copy) (freshen (car node))
                                (cdr copy) (freshen (cdr node)))
                          copy))))
                 (t node))))
      (freshen term)))

(defun %term-has-variables-p (term)
  "True when TERM contains at least one logic variable."
  (cond
    ((logic-var-p term) t)
    ((not (consp term)) nil)
    (t
     (let ((seen (make-hash-table :test #'eq)))
       (labels ((has-variables-p (node)
                  (cond
                    ((logic-var-p node) t)
                    ((not (consp node)) nil)
                    ((gethash node seen) nil)
                    (t
                     (setf (gethash node seen) t)
                     (or (has-variables-p (car node))
                         (has-variables-p (cdr node)))))))
         (has-variables-p term))))))

(defun %freshen-clause (clause)
  "Return CLAUSE with all logic variables consistently renamed to fresh ones."
  (let ((mapping (%make-freshening-map)))
    (make-clause
      (%freshen-term (clause-head clause) mapping mapping)
      (mapcar
        (lambda (goal)
          (%freshen-term goal mapping mapping))
        (clause-body clause)))))
