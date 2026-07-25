;;;; Ordered clause data model and operations: the clause/rulebase
;;;; structs, predicate-index maintenance, and insert/retract/visibility
;;;; queries.  Tabling data lives in table-variant.lisp; source-load
;;;; bookkeeping lives in source-registry.lisp.

(in-package #:cl-prolog)

(progn
  (defstruct (clause (:copier nil) (:constructor make-clause (head &optional (body (quote ())))))
    "A Horn clause. An empty BODY denotes a fact."
    (head (quote ()) :type list :read-only t)
    (body (quote ()) :type list :read-only t))
  (defstruct (%clause-template-reference (:copier nil) (:constructor %make-clause-template-reference (kind value)))
    (kind :literal :type (member :literal :variable :cons) :read-only t)
    (value nil :read-only t))
  (defstruct (%rule-instruction (:copier nil) (:constructor %make-rule-instruction (predicate operands)))
    (predicate nil :type symbol :read-only t)
    (operands #() :type simple-vector :read-only t))
  (defstruct (%rule-program (:copier nil) (:constructor %make-rule-program (variable-count head-operands body)))
    (variable-count 0 :type (integer 0 *) :read-only t)
    (head-operands #() :type simple-vector :read-only t)
    (body #() :type simple-vector :read-only t))
  (defstruct (%clause-template (:copier nil) (:constructor %make-clause-template (variable-count cons-cars cons-cdrs head body &optional rule-program)))
    (variable-count 0 :type (integer 0 *) :read-only t)
    (cons-cars #() :type simple-vector :read-only t)
    (cons-cdrs #() :type simple-vector :read-only t)
    (head nil :type %clause-template-reference :read-only t)
    (body nil :type %clause-template-reference :read-only t)
    (rule-program nil :type (or null %rule-program) :read-only t))
  (defun %rule-program-literal-p (term)
    (or (symbolp term) (numberp term) (characterp term)))
  (defun %compile-rule-program (clause)
    "Compile the restricted immutable rule instruction subset, or return NIL."
    (let ((variables (make-hash-table :test (function eq)))
          (seen-conses (make-hash-table :test (function eq)))
          (next-variable 0))
      (labels ((encode-operand (term)
                 (cond
                   ((logic-var-p term)
                    (multiple-value-bind (reference present-p)
                        (gethash term variables)
                      (if present-p
                          reference
                          (let ((reference (%make-clause-template-reference :variable next-variable)))
                            (setf (gethash term variables) reference)
                            (incf next-variable)
                            reference))))
                   ((%rule-program-literal-p term)
                    (%make-clause-template-reference :literal term))
                   (t (return-from %compile-rule-program nil))))
               (compile-call (goal)
                 (unless (consp goal)
                   (return-from %compile-rule-program nil))
                 (when (gethash goal seen-conses)
                   (return-from %compile-rule-program nil))
                 (setf (gethash goal seen-conses) t)
                 (let ((predicate (car goal))
                       (cursor (cdr goal))
                       (operands (make-array 4 :adjustable t :fill-pointer 0)))
                   (unless (and (symbolp predicate)
                                (not (logic-var-p predicate))
                                (not (string= (symbol-name predicate) "!")))
                     (return-from %compile-rule-program nil))
                   (loop
                     (cond
                       ((null cursor)
                        (return (%make-rule-instruction predicate (coerce operands (quote simple-vector)))))
                       ((not (consp cursor))
                        (return-from %compile-rule-program nil))
                       ((gethash cursor seen-conses)
                        (return-from %compile-rule-program nil))
                       (t
                        (setf (gethash cursor seen-conses) t)
                        (vector-push-extend (encode-operand (car cursor)) operands)
                        (setf cursor (cdr cursor)))))))
               (compile-body (body)
                 (cond
                   ((null body)
                    (return-from compile-body #()))
                   ((not (consp body))
                    (return-from %compile-rule-program nil)))
                 (let ((instructions (make-array 4 :adjustable t :fill-pointer 0))
                       (cursor body))
                   (loop
                     (cond
                       ((null cursor)
                        (return (coerce instructions (quote simple-vector))))
                       ((not (consp cursor))
                        (return-from %compile-rule-program nil))
                       ((gethash cursor seen-conses)
                        (return-from %compile-rule-program nil))
                       (t
                        (setf (gethash cursor seen-conses) t)
                        (vector-push-extend (compile-call (car cursor)) instructions)
                        (setf cursor (cdr cursor))))))))
        (let* ((head-instruction (compile-call (clause-head clause)))
               (body (compile-body (clause-body clause))))
          (%make-rule-program next-variable
                              (%rule-instruction-operands head-instruction)
                              body)))))
  (defun %compile-clause-template (clause)
    "Compile CLAUSE into an immutable graph template with stable IDs."
    (let ((variables (make-hash-table :test (function eq)))
          (conses (make-hash-table :test (function eq)))
          (cons-cars (make-array 8 :adjustable t :fill-pointer 0))
          (cons-cdrs (make-array 8 :adjustable t :fill-pointer 0))
          (next-variable 0)
          (rule-program (%compile-rule-program clause)))
      (labels ((encode (term)
                 (cond
                   ((logic-var-p term)
                    (multiple-value-bind (reference present-p) (gethash term variables)
                      (if present-p
                          reference
                          (let ((reference (%make-clause-template-reference :variable next-variable)))
                            (setf (gethash term variables) reference)
                            (incf next-variable)
                            reference))))
                   ((consp term)
                    (multiple-value-bind (reference present-p) (gethash term conses)
                      (if present-p
                          reference
                          (let* ((identifier (fill-pointer cons-cars))
                                 (reference (%make-clause-template-reference :cons identifier)))
                            (setf (gethash term conses) reference)
                            (vector-push-extend nil cons-cars)
                            (vector-push-extend nil cons-cdrs)
                            (setf (aref cons-cars identifier) (encode (car term))
                                  (aref cons-cdrs identifier) (encode (cdr term)))
                            reference))))
                   (t (%make-clause-template-reference :literal term)))))
        (let ((head (encode (clause-head clause)))
              (body (encode (clause-body clause))))
          (%make-clause-template next-variable
                                 (coerce cons-cars (quote simple-vector))
                                 (coerce cons-cdrs (quote simple-vector))
                                 head body rule-program)))))
  (declaim (inline %materialize-clause-template-reference))
  (defun %materialize-clause-template-reference (reference variables conses)
    (ecase (%clause-template-reference-kind reference)
      (:literal (%clause-template-reference-value reference))
      (:variable (svref variables (%clause-template-reference-value reference)))
      (:cons (svref conses (%clause-template-reference-value reference)))))
  (defun %materialize-clause-template (template)
    "Instantiate TEMPLATE with fresh variables and preallocated cons shells."
    (let* ((variable-count (%clause-template-variable-count template))
           (cons-cars (%clause-template-cons-cars template))
           (cons-cdrs (%clause-template-cons-cdrs template))
           (cons-count (length cons-cars))
           (variables (make-array variable-count))
           (conses (make-array cons-count)))
      (dotimes (index variable-count)
        (setf (svref variables index) (fresh-logic-variable)))
      (dotimes (index cons-count)
        (setf (svref conses index) (cons nil nil)))
      (dotimes (index cons-count)
        (let ((cell (svref conses index)))
          (setf (car cell) (%materialize-clause-template-reference (svref cons-cars index) variables conses)
                (cdr cell) (%materialize-clause-template-reference (svref cons-cdrs index) variables conses))))
      (make-clause
       (%materialize-clause-template-reference (%clause-template-head template) variables conses)
       (%materialize-clause-template-reference (%clause-template-body template) variables conses)))))

(defun %copy-clause (clause)
  "Copy CLAUSE's cons graph while preserving atoms, sharing, and cycles."
  (let ((copies (make-hash-table :test #'eq)))
    (labels ((copy-term (term)
               (if (consp term)
                   (multiple-value-bind (copy present-p)
                       (gethash term copies)
                     (if present-p
                         copy
                         (let ((copy (cons nil nil)))
                           (setf (gethash term copies) copy
                                 (car copy) (copy-term (car term))
                                 (cdr copy) (copy-term (cdr term)))
                           copy)))
                   term)))
      (make-clause (copy-term (clause-head clause))
                   (copy-term (clause-body clause))))))

(progn
  (defstruct (%stored-clause
              (:copier nil)
              (:constructor %make-stored-clause
                  (clause template module born-revision &optional source)))
    "Internal lifetime metadata for one clause in a rulebase."
    (clause (make-clause '()) :type clause :read-only t)
    (template nil :type %clause-template :read-only t)
    (module +default-prolog-module+ :type symbol :read-only t)
    (born-revision 0 :type (integer 0 *) :read-only t)
    (source nil :type (or null pathname) :read-only t)
    (died-revision nil :type (or null (integer 0 *))))

  (defun %make-owned-stored-clause
      (clause module born-revision &optional source)
    "Snapshot CLAUSE and compile its immutable instantiation template once."
    (let ((template (%compile-clause-template clause)))
      (%make-stored-clause (%copy-clause clause) template
                           module born-revision source)))

  (defun %materialize-stored-clause-for-proof (entry template)
    "Instantiate variable clauses, but share the owned snapshot of a ground clause."
    (if (zerop (%clause-template-variable-count template))
        (%stored-clause-clause entry)
        (%materialize-clause-template template))))

(progn
  (defstruct (%predicate-descriptor
              (:copier nil)
              (:constructor %make-predicate-descriptor
                  (entries symbol-first-argument-index
                   atom-first-argument-index variable-entries)))
    "Immutable current-state lookup data for one predicate."
    (entries '() :type list :read-only t)
    (symbol-first-argument-index (make-hash-table :test #'eq)
                                 :type hash-table :read-only t)
    (atom-first-argument-index (make-hash-table :test #'eql)
                               :type hash-table :read-only t)
    (variable-entries '() :type list :read-only t))

  (defstruct (rulebase (:copier nil)
                       (:constructor %make-rulebase
                           (entries entries-tail predicate-index predicate-tails
                            first-argument-index first-argument-tails
                            variable-head-index variable-head-tails
                            predicate-descriptors revision operator-table
                            predicate-properties io-context module-registry
                            source-registry prolog-flag-values char-conversions
                            table-declarations left-recursion-analysis)))
    "An ordered logical-update database of clauses."
    (entries '() :type list)
    (entries-tail '() :type list)
    (predicate-index (make-hash-table :test #'equal) :type hash-table)
    (predicate-tails (make-hash-table :test #'equal) :type hash-table)
    (first-argument-index (make-hash-table :test #'equal) :type hash-table)
    (first-argument-tails (make-hash-table :test #'equal) :type hash-table)
    (variable-head-index (make-hash-table :test #'equal) :type hash-table)
    (variable-head-tails (make-hash-table :test #'equal) :type hash-table)
    (predicate-descriptors (make-hash-table :test #'eq) :type hash-table)
    (revision 0 :type (integer 0 *))
    (operator-table *standard-operator-table* :type operator-table)
    (predicate-properties (make-hash-table :test #'equal) :type hash-table)
    (io-context (make-prolog-io-context) :type prolog-io-context)
    (module-registry (make-module-registry) :type module-registry)
    (source-registry (%make-source-registry) :type hash-table)
    (prolog-flag-values (make-hash-table :test #'equal) :type hash-table)
    (char-conversions (make-hash-table :test #'eql) :type hash-table)
    (table-declarations (make-hash-table :test #'equal) :type hash-table)
    (left-recursion-analysis (make-hash-table :test #'equal)
                             :type hash-table :read-only t)))

(defun %stored-clause-predicate-key (entry)
  "Return ENTRY's (module predicate arity) key, or NIL for a malformed head."
  (let ((head (clause-head (%stored-clause-clause entry))))
    (when (and (consp head) (symbolp (first head)))
      (list (%stored-clause-module entry)
            (first head)
            (length (rest head))))))

(defun %append-to-predicate-index-tail! (key entry index tails)
    "Append ENTRY to KEY's bucket in INDEX using TAILS in O(1)."
    (let ((cell (list entry))
          (tail (gethash key tails)))
      (if tail
          (setf (cdr tail) cell)
          (setf (gethash key index) cell))
      (setf (gethash key tails) cell)))

  (defun %insert-index-entry! (key entry position index tails)
    "Insert ENTRY into KEY's bucket at POSITION while maintaining its tail."
    (ecase position
      (:first
       (let* ((entries (gethash key index))
              (cell (cons entry entries)))
         (setf (gethash key index) cell)
         (unless entries
           (setf (gethash key tails) cell))))
      (:last
       (%append-to-predicate-index-tail! key entry index tails))))

  (defun %first-argument-index-key (value)
    "Return a package-independent exact-index key for a ground atomic VALUE."
    (cond
      ((logic-var-p value) nil)
      ((symbolp value) (list :symbol (symbol-name value)))
      ((atom value) (list :atom value))
      (t nil)))

  (defun %stored-clause-first-argument (entry)
    (let ((head (clause-head (%stored-clause-clause entry))))
      (and (consp (rest head)) (second head))))

  (defun %index-stored-clause-first-argument! (entry position
                                                exact-index exact-tails
                                                variable-index variable-tails)
    "Add an indexable ENTRY to the exact or variable-head first-argument index."
    (let ((predicate-key (%stored-clause-predicate-key entry)))
      (when predicate-key
        (let ((first-argument (%stored-clause-first-argument entry)))
          (cond
            ((logic-var-p first-argument)
             (%insert-index-entry! predicate-key entry position
                                   variable-index variable-tails))
            (t
             (let ((argument-key (%first-argument-index-key first-argument)))
               (when argument-key
                 (%insert-index-entry! (list predicate-key argument-key)
                                       entry position exact-index exact-tails)))))))))

(progn (defun %make-rulebase-predicate-index (entries)
  "Build the predicate and first-argument indexes for ENTRIES."
  (let ((predicate-index (make-hash-table :test #'equal))
        (predicate-tails (make-hash-table :test #'equal))
        (exact-index (make-hash-table :test #'equal))
        (exact-tails (make-hash-table :test #'equal))
        (variable-index (make-hash-table :test #'equal))
        (variable-tails (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (let ((key (%stored-clause-predicate-key entry)))
        (when key
          (%append-to-predicate-index-tail! key entry
                                            predicate-index predicate-tails)
          (%index-stored-clause-first-argument!
           entry :last exact-index exact-tails variable-index variable-tails))))
    (values predicate-index predicate-tails
            exact-index exact-tails variable-index variable-tails))) (defun %set-rulebase-predicate-descriptor! (descriptors module predicate arity descriptor)
  "Install DESCRIPTOR in the nested MODULE/PREDICATE/ARITY index."
  (let ((predicates (gethash module descriptors)))
    (cond
      (descriptor
       (unless predicates
         (setf predicates (make-hash-table :test #'eq)
               (gethash module descriptors) predicates))
       (let ((arities (gethash predicate predicates)))
         (unless arities
           (setf arities (make-hash-table :test #'eql)
                 (gethash predicate predicates) arities))
         (setf (gethash arity arities) descriptor)))
      (predicates
       (let ((arities (gethash predicate predicates)))
         (when arities
           (remhash arity arities)
           (when (zerop (hash-table-count arities))
             (remhash predicate predicates))
           (when (zerop (hash-table-count predicates))
             (remhash module descriptors)))))))
  descriptor)

(defun %rulebase-predicate-descriptor (rulebase module predicate arity)
  "Return the current immutable descriptor without changing any lookup table."
  (let* ((predicates (gethash module (rulebase-predicate-descriptors rulebase)))
         (arities (and predicates (gethash predicate predicates))))
    (and arities (gethash arity arities))))

(defun %build-predicate-descriptor (entries)
  "Build detached current-state lookup lists for ENTRIES."
  (let ((owned-entries (copy-list entries))
        (symbol-candidates (make-hash-table :test #'eq))
        (atom-candidates (make-hash-table :test #'eql))
        (variable-entries '()))
    (dolist (entry owned-entries)
      (let ((first-argument (%stored-clause-first-argument entry)))
        (cond
          ((logic-var-p first-argument)
           (push entry variable-entries))
          ((symbolp first-argument)
           (push entry (gethash first-argument symbol-candidates)))
          ((or (numberp first-argument) (characterp first-argument))
           (push entry (gethash first-argument atom-candidates))))))
    (setf variable-entries (nreverse variable-entries))
    (labels ((merge-candidates (exact-entries)
               (loop with exact = exact-entries
                     with variable = variable-entries
                     for entry in owned-entries
                     when (or (and exact
                                   (eq entry (first exact))
                                   (pop exact))
                              (and variable
                                   (eq entry (first variable))
                                   (pop variable)))
                       collect entry))
             (finish-index (index)
               (maphash
                (lambda (key exact-entries)
                  (setf (gethash key index)
                        (merge-candidates (nreverse exact-entries))))
                index)
               index))
      (%make-predicate-descriptor
       owned-entries
       (finish-index symbol-candidates)
       (finish-index atom-candidates)
       variable-entries))))

(defun %make-rulebase-predicate-descriptors (predicate-index revision)
  "Build the nested current-state descriptor index at REVISION."
  (let ((descriptors (make-hash-table :test #'eq)))
    (maphash
     (lambda (key entries)
       (destructuring-bind (module predicate arity) key
         (let ((visible-entries (%visible-stored-clauses entries revision)))
           (when visible-entries
             (%set-rulebase-predicate-descriptor!
              descriptors module predicate arity
              (%build-predicate-descriptor visible-entries))))))
     predicate-index)
    descriptors))

(defun %refresh-rulebase-predicate-descriptor! (rulebase module predicate arity)
  "Copy-on-write the one descriptor affected by a rulebase mutation."
  (let ((entries (%rulebase-predicate-entries-at-revision
                  rulebase module predicate arity
                  (rulebase-revision rulebase))))
    (%set-rulebase-predicate-descriptor!
     (rulebase-predicate-descriptors rulebase)
     module predicate arity
     (and entries (%build-predicate-descriptor entries)))))

(defun %predicate-descriptor-first-argument-entries (descriptor first-argument)
  "Return precomputed candidates for FIRST-ARGUMENT without mutating indexes."
  (cond
    ((logic-var-p first-argument)
     (%predicate-descriptor-entries descriptor))
    ((symbolp first-argument)
     (or (gethash first-argument
                  (%predicate-descriptor-symbol-first-argument-index descriptor))
         (%predicate-descriptor-variable-entries descriptor)))
    ((or (numberp first-argument) (characterp first-argument))
     (or (gethash first-argument
                  (%predicate-descriptor-atom-first-argument-index descriptor))
         (%predicate-descriptor-variable-entries descriptor)))
    (t
     (%predicate-descriptor-entries descriptor)))))

(defun %rulebase-source-state (rulebase canonical-pathname)
  "Return CANONICAL-PATHNAME's load state and whether it is registered."
  (let ((record (gethash canonical-pathname
                         (rulebase-source-registry rulebase))))
    (and record (%source-record-state record))))

(defun %rulebase-source-record (rulebase canonical-pathname)
  (gethash canonical-pathname (rulebase-source-registry rulebase)))

(defun %set-rulebase-source-state! (rulebase canonical-pathname state)
  "Record STATE for CANONICAL-PATHNAME and return STATE."
  (check-type state (member :loading :loaded))
  (let ((record (or (%rulebase-source-record rulebase canonical-pathname)
                    (%make-source-record state))))
    (setf (%source-record-state record) state
          (gethash canonical-pathname (rulebase-source-registry rulebase)) record)
    state))

(defun make-rulebase (&key (clauses '())
                           (io-context (make-prolog-io-context)))
  "Return a rulebase containing CLAUSES in resolution order."
  (let ((entries
          (mapcar (lambda (clause)
                    (%make-owned-stored-clause
                     clause +default-prolog-module+ 0))
                  clauses)))
    (multiple-value-bind
          (predicate-index predicate-tails
           exact-index exact-tails variable-index variable-tails)
        (%make-rulebase-predicate-index entries)
      (%make-rulebase
       entries (last entries)
       predicate-index predicate-tails
       exact-index exact-tails variable-index variable-tails
       (%make-rulebase-predicate-descriptors predicate-index 0)
       0 *standard-operator-table*
       (make-hash-table :test #'equal)
       io-context
       (make-module-registry)
       (%make-source-registry)
       (make-hash-table :test #'equal)
       (make-hash-table :test #'eql)
       (make-hash-table :test #'equal)
       (make-hash-table :test #'equal)))))

(defun %copy-rulebase (rulebase &optional (copy-clause #'identity))
  "Return a detached mutable copy suitable for transactional updates.
COPY-CLAUSE maps each stored clause into the copy; immutable templates are shared."
  (let ((entries
          (mapcar
           (lambda (entry)
             (let ((copy
                     (%make-stored-clause
                      (funcall copy-clause (%stored-clause-clause entry))
                      (%stored-clause-template entry)
                      (%stored-clause-module entry)
                      (%stored-clause-born-revision entry)
                      (%stored-clause-source entry))))
               (setf (%stored-clause-died-revision copy)
                     (%stored-clause-died-revision entry))
               copy))
           (rulebase-entries rulebase))))
    (multiple-value-bind
          (predicate-index predicate-tails
           exact-index exact-tails variable-index variable-tails)
        (%make-rulebase-predicate-index entries)
      (%make-rulebase
       entries (last entries)
       predicate-index predicate-tails
       exact-index exact-tails variable-index variable-tails
       (%make-rulebase-predicate-descriptors
        predicate-index (rulebase-revision rulebase))
       (rulebase-revision rulebase)
       (rulebase-operator-table rulebase)
       (%copy-hash-table (rulebase-predicate-properties rulebase))
       (%copy-prolog-io-context (rulebase-io-context rulebase))
       (module-registry-copy (rulebase-module-registry rulebase))
       (%copy-source-registry (rulebase-source-registry rulebase))
       (%copy-hash-table (rulebase-prolog-flag-values rulebase))
       (%copy-hash-table (rulebase-char-conversions rulebase))
       (let ((copy (make-hash-table :test #'equal)))
         (maphash (lambda (key owners)
                    (setf (gethash key copy) (copy-list owners)))
                  (rulebase-table-declarations rulebase))
         copy)
       (make-hash-table :test #'equal)))))

(defun copy-rulebase (rulebase)
  "Return a detached copy of RULEBASE, including its complete runtime state.

Stored clauses and their cons-based terms are copied, so mutating terms
reachable from one rulebase never affects the other. Immutable atoms and
persistent metadata such as operator tables may be shared."
  (check-type rulebase rulebase)
  (%copy-rulebase rulebase #'%copy-clause))

(defun rulebase-extend (rulebase clauses)
  "Return a detached copy of RULEBASE shadow-extended by CLAUSES.

CLAUSES retain their order and precede the clauses already visible in
RULEBASE.  Operator declarations, predicate properties, I/O state, modules,
source registrations, flags, and character conversions are copied as well."
  (let ((extended (copy-rulebase rulebase)))
    (dolist (clause (reverse clauses) extended)
      (rulebase-insert-clause! extended clause :position :first))))

(defun %replace-rulebase! (target source)
  "Replace TARGET's complete state with SOURCE after a successful transaction."
  (setf (rulebase-entries target) (rulebase-entries source)
        (rulebase-entries-tail target) (rulebase-entries-tail source)
        (rulebase-predicate-index target) (rulebase-predicate-index source)
        (rulebase-predicate-tails target) (rulebase-predicate-tails source)
        (rulebase-first-argument-index target)
        (rulebase-first-argument-index source)
        (rulebase-first-argument-tails target)
        (rulebase-first-argument-tails source)
        (rulebase-variable-head-index target)
        (rulebase-variable-head-index source)
        (rulebase-variable-head-tails target)
        (rulebase-variable-head-tails source)
        (rulebase-predicate-descriptors target)
        (%make-rulebase-predicate-descriptors
         (rulebase-predicate-index source)
         (rulebase-revision source))
        (rulebase-revision target) (rulebase-revision source)
        (rulebase-operator-table target) (rulebase-operator-table source)
        (rulebase-predicate-properties target)
        (rulebase-predicate-properties source)
        (rulebase-io-context target) (rulebase-io-context source)
        (rulebase-module-registry target) (rulebase-module-registry source)
        (rulebase-source-registry target) (rulebase-source-registry source)
        (rulebase-prolog-flag-values target)
        (rulebase-prolog-flag-values source)
        (rulebase-char-conversions target)
        (rulebase-char-conversions source)
        (rulebase-table-declarations target)
        (rulebase-table-declarations source))
  (clrhash (rulebase-left-recursion-analysis target))
  target)

(defun %rulebase-tabled-p (rulebase predicate arity
                           &optional (module +default-prolog-module+))
  (not (null (gethash (list module predicate arity)
                      (rulebase-table-declarations rulebase)))))

(defun %add-rulebase-table-declaration! (rulebase predicate arity owner
                                          &optional (module +default-prolog-module+))
  "Add OWNER's table declaration, advancing the revision on first ownership."
  (let* ((key (list module predicate arity))
         (owners (gethash key (rulebase-table-declarations rulebase))))
    (unless (member owner owners :test #'equal)
      (unless owners
        (%next-rulebase-revision! rulebase))
      (push owner (gethash key (rulebase-table-declarations rulebase))))
    rulebase))

(defun %remove-rulebase-table-declaration! (rulebase predicate arity owner
                                             &optional (module +default-prolog-module+))
  "Remove OWNER's declaration, advancing the revision when no owner remains."
  (let* ((key (list module predicate arity))
         (owners (gethash key (rulebase-table-declarations rulebase)))
         (remaining (remove owner owners :test #'equal)))
    (unless (= (length owners) (length remaining))
      (if remaining
          (setf (gethash key (rulebase-table-declarations rulebase)) remaining)
          (progn
            (remhash key (rulebase-table-declarations rulebase))
            (%next-rulebase-revision! rulebase))))
    rulebase))

(defun %remove-rulebase-table-declarations! (rulebase predicate arity
                                              &optional (module +default-prolog-module+))
  "Remove every table declaration for PREDICATE/ARITY in MODULE."
  (let ((key (list module predicate arity)))
    (when (remhash key (rulebase-table-declarations rulebase))
      (%next-rulebase-revision! rulebase))
    rulebase))

(defun %predicate-property-key (predicate arity module)
  (list module predicate arity))

(defun %rulebase-predicate-property (rulebase predicate arity
                                     &optional (module +default-prolog-module+))
  (gethash (%predicate-property-key predicate arity module)
           (rulebase-predicate-properties rulebase)))

(defun %set-rulebase-predicate-property! (rulebase predicate arity property
                                          &optional (module +default-prolog-module+))
  (setf (gethash (%predicate-property-key predicate arity module)
                 (rulebase-predicate-properties rulebase))
        property))

(defun %remove-rulebase-predicate-property! (rulebase predicate arity
                                              &optional (module +default-prolog-module+))
  "Remove PREDICATE/ARITY's declaration and return whether one existed."
  (remhash (%predicate-property-key predicate arity module)
           (rulebase-predicate-properties rulebase)))

(defun %rulebase-declared-predicate-indicators
    (rulebase &optional (module +default-prolog-module+))
  "Return declared predicate indicators in parser AST form (/ NAME ARITY)."
  (let ((indicators '()))
    (maphash (lambda (key property)
               (declare (cl:ignore property))
               (when (eq (first key) module)
                 (push (list '/ (second key) (third key)) indicators)))
             (rulebase-predicate-properties rulebase))
    indicators))

(defun %next-rulebase-revision! (rulebase)
  (clrhash (rulebase-left-recursion-analysis rulebase))
  (incf (rulebase-revision rulebase)))

(defun %stored-clause-visible-p (entry revision)
  (and (<= (%stored-clause-born-revision entry) revision)
       (let ((died (%stored-clause-died-revision entry)))
         (or (null died) (< revision died)))))

(defun %rulebase-snapshot (rulebase)
  "Return the current revision and a detached list of visible internal entries."
  (let ((revision (rulebase-revision rulebase)))
    (values revision
            (loop for entry in (rulebase-entries rulebase)
                  when (%stored-clause-visible-p entry revision)
                    collect entry))))

(defun rulebase-visible-clauses (rulebase)
  "Return detached clauses visible at one current logical-update snapshot."
  (multiple-value-bind (revision entries) (%rulebase-snapshot rulebase)
    (declare (cl:ignore revision))
    (mapcar (lambda (entry)
              (%copy-clause (%stored-clause-clause entry)))
            entries)))

(defun %rulebase-module-entries (rulebase module)
  "Return the visible stored clauses defined by MODULE."
  (multiple-value-bind (revision entries) (%rulebase-snapshot rulebase)
    (declare (cl:ignore revision))
    (remove module entries :test-not #'eq :key #'%stored-clause-module)))

(progn (defun %visible-stored-clauses (entries revision) (loop for entry in entries when (%stored-clause-visible-p entry revision) collect entry)) (defun %merge-indexed-entry-order (predicate-entries exact-entries variable-entries) "Merge two indexed subsequences according to PREDICATE-ENTRIES order." (loop with exact = exact-entries with variable = variable-entries for entry in predicate-entries when (or (and exact (eq entry (first exact)) (pop exact)) (and variable (eq entry (first variable)) (pop variable))) collect entry)))
  (defun %rulebase-predicate-entries-at-revision
    (rulebase module predicate arity revision)
  "Return PREDICATE/ARITY clauses visible in MODULE at REVISION."
  (%visible-stored-clauses
   (gethash (list module predicate arity) (rulebase-predicate-index rulebase))
   revision))


  (defun %rulebase-predicate-visible-p
    (rulebase module predicate arity revision)
  "Return true when PREDICATE/ARITY has a clause visible in MODULE at REVISION."
  (loop for entry in
          (gethash (list module predicate arity)
                   (rulebase-predicate-index rulebase))
        thereis (%stored-clause-visible-p entry revision)))


  (defun %rulebase-first-argument-entries-at-revision
      (rulebase module predicate arity argument-key revision)
    "Return exact and variable-head candidates in their original clause order."
    (let* ((predicate-key (list module predicate arity))
           (exact (gethash (list predicate-key argument-key)
                           (rulebase-first-argument-index rulebase)))
           (variable (gethash predicate-key (rulebase-variable-head-index rulebase))))
      (%visible-stored-clauses
       (cond ((null variable) exact)
             ((null exact) variable)
             (t (%merge-indexed-entry-order
                 (gethash predicate-key (rulebase-predicate-index rulebase))
                 exact variable)))
       revision)))

(defun %rulebase-predicate-entries (rulebase module predicate arity)
  "Return the current revision and immutable visible entries for one predicate."
  (let ((revision (rulebase-revision rulebase))
        (descriptor
          (%rulebase-predicate-descriptor rulebase module predicate arity)))
    (values revision
            (and descriptor (%predicate-descriptor-entries descriptor)))))

(defun rulebase-insert-clause! (rulebase clause
                                &key
                                  (position :last)
                                  (module +default-prolog-module+)
                                  source)
  "Insert CLAUSE at POSITION (:FIRST or :LAST) and return RULEBASE."
  (let ((entry
          (%make-owned-stored-clause
           clause module (%next-rulebase-revision! rulebase) source)))
    (ecase position
      (:first
       (let ((cell (cons entry (rulebase-entries rulebase))))
         (setf (rulebase-entries rulebase) cell)
         (when (null (cdr cell))
           (setf (rulebase-entries-tail rulebase) cell))))
      (:last
       (let ((cell (list entry))
             (tail (rulebase-entries-tail rulebase)))
         (if tail
             (setf (cdr tail) cell)
             (setf (rulebase-entries rulebase) cell))
         (setf (rulebase-entries-tail rulebase) cell))))
    (let ((key (%stored-clause-predicate-key entry)))
      (when key
        (%insert-index-entry!
         key entry position
         (rulebase-predicate-index rulebase)
         (rulebase-predicate-tails rulebase))
        (%index-stored-clause-first-argument!
         entry position
         (rulebase-first-argument-index rulebase)
         (rulebase-first-argument-tails rulebase)
         (rulebase-variable-head-index rulebase)
         (rulebase-variable-head-tails rulebase))
        (destructuring-bind (entry-module predicate arity) key
          (%refresh-rulebase-predicate-descriptor!
           rulebase entry-module predicate arity)))))
  rulebase)

(defun %rulebase-retract-entry! (rulebase entry)
  "Mark ENTRY dead and copy-on-write its predicate descriptor."
  (when (null (%stored-clause-died-revision entry))
    (let ((key (%stored-clause-predicate-key entry)))
      (setf (%stored-clause-died-revision entry)
            (%next-rulebase-revision! rulebase))
      (when key
        (destructuring-bind (module predicate arity) key
          (%refresh-rulebase-predicate-descriptor!
           rulebase module predicate arity))))
    t))

(defun %rulebase-retract-entries! (rulebase entries)
  "Assign one death revision to live ENTRIES and refresh affected descriptors."
  (let ((live (remove-if #'%stored-clause-died-revision entries)))
    (when live
      (let ((revision (%next-rulebase-revision! rulebase))
            (keys
              (remove-duplicates
               (remove nil (mapcar #'%stored-clause-predicate-key live))
               :test #'equal)))
        (dolist (entry live)
          (setf (%stored-clause-died-revision entry) revision))
        (dolist (key keys)
          (destructuring-bind (module predicate arity) key
            (%refresh-rulebase-predicate-descriptor!
             rulebase module predicate arity)))))
    (not (null live))))
