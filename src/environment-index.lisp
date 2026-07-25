;;;; Environment indexing: an identity-keyed view over an association-list
;;;; environment, with a bounded overlay so extending an environment stays
;;;; cheap, plus the variable dereferencing (walk) built on top of it.

(in-package #:cl-prolog)

(defconstant +environment-index-overlay-threshold+ 8)
(defstruct (%environment-index
    (:constructor %make-environment-index-object
      (table overlay overlay-length next-binding-rank)))
  (table (make-hash-table :test (function eq)) :type hash-table)
  (overlay nil :type list)
  (overlay-length 0 :type (integer 0 *))
  (next-binding-rank -1 :type integer))
(defun %environment-index-entry (variable index)
  "Return the newest entry for VARIABLE from INDEX."
  (dolist (binding (%environment-index-overlay index)
           (gethash variable (%environment-index-table index)))
    (when (eq variable (car binding))
      (return (values (cdr binding) t)))))
(defun %make-environment-index (environment &optional (additional-capacity 0))
  "Index ENVIRONMENT by variable identity while preserving first-binding wins."
  (check-type additional-capacity (integer 0 *))
  (let ((table
          (make-hash-table
            :test
            (function eq)
            :size
            (+ (length environment) additional-capacity)))
        (rank 0))
    (dolist (binding environment)
      (multiple-value-bind (entry present-p)
          (gethash (car binding) table)
        (declare (ignore entry))
        (unless present-p
          (setf (gethash (car binding) table)
                (cons (cdr binding) rank))))
      (incf rank))
    (%make-environment-index-object table nil 0 -1)))
(defun %copy-environment-index (index)
  "Return a writable index object sharing the immutable contents of INDEX."
  (%make-environment-index-object
    (%environment-index-table index)
    (%environment-index-overlay index)
    (%environment-index-overlay-length index)
    (%environment-index-next-binding-rank index)))
(defun %compact-environment-index (index)
  "Merge the bounded overlay into a new immutable base table."
  (if (zerop (%environment-index-overlay-length index))
      index
      (let ((table
              (make-hash-table
                :test
                (function eq)
                :size
                (+ (hash-table-count (%environment-index-table index))
                   (%environment-index-overlay-length index)))))
        (maphash
          (lambda (variable entry)
            (setf (gethash variable table) entry))
          (%environment-index-table index))
        (labels ((install-oldest-first (overlay)
                   (when overlay
                     (install-oldest-first (cdr overlay))
                     (let ((binding (car overlay)))
                       (setf (gethash (car binding) table)
                             (cdr binding))))))
          (install-oldest-first (%environment-index-overlay index)))
        (%make-environment-index-object
          table
          nil
          0
          (%environment-index-next-binding-rank index)))))
(defun %extend-environment-index (index bindings)
  "Return INDEX extended by BINDINGS ordered oldest to newest."
  (let ((extended (%copy-environment-index index)))
    (dolist (binding bindings extended)
      (push
        (cons
          (car binding)
          (cons
            (cdr binding)
            (%environment-index-next-binding-rank extended)))
        (%environment-index-overlay extended))
      (incf (%environment-index-overlay-length extended))
      (decf (%environment-index-next-binding-rank extended))
      (when (= (%environment-index-overlay-length extended)
               +environment-index-overlay-threshold+)
        (setf extended (%compact-environment-index extended))))))
(defun %environment-index-after-bindings
    (bindings parent-bindings parent-index)
  "Reuse PARENT-INDEX for an unchanged environment or extend a prepended prefix."
  (if (eq bindings parent-bindings)
      parent-index
      (let ((reversed-prefix (quote ()))
            (tail bindings))
        (loop until (eq tail parent-bindings)
              do (unless (consp tail)
                   (return-from
                     %environment-index-after-bindings
                     (%make-environment-index bindings)))
                 (push (car tail) reversed-prefix)
                 (setf tail (cdr tail)))
        (%extend-environment-index parent-index reversed-prefix))))
(defun %alias-cycle-representative (start index)
  "Choose the earliest effective binding in the alias cycle containing START."
  (let* ((entry (%environment-index-entry start index))
         (representative start)
         (best-rank (cdr entry))
         (term (car entry)))
    (loop until (eq term start)
          for term-entry = (%environment-index-entry term index)
          when (< (cdr term-entry) best-rank)
            do (setf representative term
                     best-rank (cdr term-entry))
          do (setf term (car term-entry))
          finally (return representative))))
(defun %walk-term-indexed (term index)
  (when (not (logic-var-p term))
    (return-from %walk-term-indexed term))
  (let ((checkpoint term)
        (cursor term)
        (power 1)
        (distance 0))
    (loop
      (multiple-value-bind (entry present-p)
          (%environment-index-entry cursor index)
        (unless present-p
          (return cursor))
        (setf cursor (car entry)))
      (unless (logic-var-p cursor)
        (return cursor))
      (incf distance)
      (when (eq checkpoint cursor)
        (return (%alias-cycle-representative cursor index)))
      (when (= distance power)
        (setf checkpoint cursor
              power (* 2 power)
              distance 0)))))
(defun %walk-term (term env)
  "Chase TERM through ENV until it is unbound or not a variable."
  (%walk-term-indexed term (%make-environment-index env)))
