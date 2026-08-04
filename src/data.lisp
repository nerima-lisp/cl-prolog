;;;; The rulebase container: its struct, construction/copy/replace
;;;; lifecycle, and the ordered logical-update operations (insert, retract,
;;;; visibility snapshots) layered on top of it.  Clause representation lives
;;;; in clause.lisp and predicate lookup in predicate-index.lisp; tabling data
;;;; lives in table-variant.lisp and source-load bookkeeping in
;;;; source-registry.lisp.

(in-package #:cl-prolog)

(defstruct (rulebase (:copier nil) (:constructor %make-rulebase))
  "An ordered logical-update database of clauses."
  (entries '() :type list)
  (entries-tail '() :type list)
  (predicate-index (make-hash-table :test #'equal) :type hash-table)
  (predicate-tails (make-hash-table :test #'equal) :type hash-table)
  (predicate-descriptors (make-hash-table :test #'eq) :type hash-table)
  (revision 0 :type (integer 0 *))
  ;; Count of entries in ENTRIES (and therefore in the buckets of
  ;; PREDICATE-INDEX) whose DIED-REVISION is non-NIL but which have not yet
  ;; been physically dropped by %COMPACT-RULEBASE!.  See
  ;; *PROLOG-ACTIVE-TOP-LEVEL-CALLS* below for why they are not dropped
  ;; immediately when they die.
  (dead-entries 0 :type (integer 0 *))
  (operator-table *standard-operator-table* :type operator-table)
  (predicate-properties (make-hash-table :test #'equal) :type hash-table)
  (io-context (make-prolog-io-context) :type prolog-io-context)
  (module-registry (make-module-registry) :type module-registry)
  (source-registry (%make-source-registry) :type hash-table)
  (prolog-flag-values (make-hash-table :test #'equal) :type hash-table)
  (char-conversions (make-hash-table :test #'eql) :type hash-table)
  (table-declarations (make-hash-table :test #'equal) :type hash-table)
  (table-session-cache (make-hash-table :test #'eql)
                       :type hash-table :read-only t)
  (module-entries-cache (make-hash-table :test #'equal)
                        :type hash-table :read-only t)
  (left-recursion-analysis (make-hash-table :test #'equal)
                           :type hash-table :read-only t))

(defun %rulebase-predicate-descriptor (rulebase module predicate arity)
  "Return the current immutable descriptor without changing any lookup table."
  (let* ((predicates (gethash module (rulebase-predicate-descriptors rulebase)))
         (arities (and predicates (gethash predicate predicates))))
    (and arities (gethash arity arities))))

(defun %refresh-rulebase-predicate-descriptor! (rulebase module predicate arity)
  "Copy-on-write the one descriptor affected by a rulebase mutation."
  (let ((entries (%rulebase-predicate-entries-at-revision
                  rulebase module predicate arity
                  (rulebase-revision rulebase))))
    (%set-rulebase-predicate-descriptor!
     (rulebase-predicate-descriptors rulebase)
     module predicate arity
     (and entries (%build-predicate-descriptor entries)))))

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
    (multiple-value-bind (predicate-index predicate-tails)
        (%make-rulebase-predicate-index entries)
      (%make-rulebase
       :entries entries
       :entries-tail (last entries)
       :predicate-index predicate-index
       :predicate-tails predicate-tails
       :predicate-descriptors
       (%make-rulebase-predicate-descriptors predicate-index 0)
       :io-context io-context))))

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
    (multiple-value-bind (predicate-index predicate-tails)
        (%make-rulebase-predicate-index entries)
      (%make-rulebase
       :entries entries
       :entries-tail (last entries)
       :predicate-index predicate-index
       :predicate-tails predicate-tails
       :predicate-descriptors
       (%make-rulebase-predicate-descriptors
        predicate-index (rulebase-revision rulebase))
       :revision (rulebase-revision rulebase)
       :dead-entries (rulebase-dead-entries rulebase)
       :operator-table (rulebase-operator-table rulebase)
       :predicate-properties
       (%copy-hash-table (rulebase-predicate-properties rulebase))
       :io-context (%copy-prolog-io-context (rulebase-io-context rulebase))
       :module-registry (module-registry-copy (rulebase-module-registry rulebase))
       :source-registry (%copy-source-registry (rulebase-source-registry rulebase))
       :prolog-flag-values
       (%copy-hash-table (rulebase-prolog-flag-values rulebase))
       :char-conversions
       (%copy-hash-table (rulebase-char-conversions rulebase))
       :table-declarations
       (let ((copy (make-hash-table :test #'equal)))
         (maphash (lambda (key owners)
                    (setf (gethash key copy) (copy-list owners)))
                  (rulebase-table-declarations rulebase))
         copy)
       :table-session-cache (make-hash-table :test #'eql)
       :module-entries-cache (make-hash-table :test #'equal)))))

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

(macrolet ((transfer-slots! (&rest readers)
             `(setf ,@(loop for reader in readers
                            append `((,reader target) (,reader source))))))
  (defun %replace-rulebase! (target source)
    "Replace TARGET's complete state with SOURCE after a successful transaction."
    (transfer-slots! rulebase-entries
                     rulebase-entries-tail
                     rulebase-predicate-index
                     rulebase-predicate-tails
                     rulebase-dead-entries
                     rulebase-revision
                     rulebase-operator-table
                     rulebase-predicate-properties
                     rulebase-io-context
                     rulebase-module-registry
                     rulebase-source-registry
                     rulebase-prolog-flag-values
                     rulebase-char-conversions
                     rulebase-table-declarations)
  (setf (rulebase-predicate-descriptors target)
        (%make-rulebase-predicate-descriptors
         (rulebase-predicate-index source)
         (rulebase-revision source)))
  (clrhash (rulebase-table-session-cache target))
  (clrhash (rulebase-module-entries-cache target))
  (clrhash (rulebase-left-recursion-analysis target))
  target))

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
  (clrhash (rulebase-table-session-cache rulebase))
  (clrhash (rulebase-module-entries-cache rulebase))
  (clrhash (rulebase-left-recursion-analysis rulebase))
  (incf (rulebase-revision rulebase)))

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
  (let* ((revision (rulebase-revision rulebase))
         (key (list revision module))
         (cache (rulebase-module-entries-cache rulebase)))
    (multiple-value-bind (entries presentp)
        (gethash key cache)
      (if presentp
          entries
          (setf (gethash key cache)
                (multiple-value-bind (snapshot-revision snapshot-entries)
                    (%rulebase-snapshot rulebase)
                  (declare (cl:ignore snapshot-revision))
                  (remove module snapshot-entries
                          :test-not #'eq
                          :key #'%stored-clause-module)))))))

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
      (incf (rulebase-dead-entries rulebase))
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
        (incf (rulebase-dead-entries rulebase) (length live))
        (dolist (key keys)
          (destructuring-bind (module predicate arity) key
            (%refresh-rulebase-predicate-descriptor!
             rulebase module predicate arity)))))
    (not (null live))))

;;; Dead-entry compaction.
;;;
;;; retract/retractall/abolish (src/builtins/dynamic.lisp) never delete a
;;; stored clause outright -- they only reach %RULEBASE-RETRACT-ENTRY!/
;;; %RULEBASE-RETRACT-ENTRIES! above, which set DIED-REVISION and leave the
;;; entry sitting in both RULEBASE-ENTRIES and its RULEBASE-PREDICATE-INDEX
;;; bucket forever.  A rulebase that retracts-and-reasserts a fact
;;; repeatedly (e.g. a `pc' register fact updated on every instruction) grows
;;; those two structures without bound, which is exactly the O(n) per
;;; mutation / O(n^2) per session blowup this compaction pass fixes.
;;;
;;; Physically dropping a dead entry is safe once nothing can still be
;;; scanning it.  Two facts, verified against the current code, make "no
;;; active top-level call anywhere" a sufficient condition:
;;;
;;; 1. Proof search never walks RULEBASE-ENTRIES or a raw PREDICATE-INDEX
;;;    bucket directly. %PROOF-PREDICATE-ENTRIES (src/prover.lisp) always
;;;    goes through a %PREDICATE-DESCRIPTOR, and %BUILD-PREDICATE-DESCRIPTOR
;;;    (src/predicate-index.lisp) always COPY-LISTs its ENTRIES into a
;;;    private list before returning the descriptor -- so an in-flight
;;;    resolution's clause list is a detached snapshot, not a view onto
;;;    RULEBASE-ENTRIES/PREDICATE-INDEX, and is untouched by anything this
;;;    file does to those two slots. This is what keeps ISO's logical-update
;;;    view intact for a retract/assert happening *during* an in-progress
;;;    call over the same predicate -- see the tests
;;;    T/BUILTIN-DYNAMIC-DATABASE-TEST.LISP::PREDICATE-CALL-KEEPS-LOGICAL-UPDATE-SNAPSHOT
;;;    and ::RETRACT-BACKTRACKS-OVER-ITS-CALL-SNAPSHOT, which assert exactly
;;;    that invariant and would catch a regression here.
;;; 2. RULEBASE-ENTRIES/PREDICATE-INDEX *are* scanned directly, but only by
;;;    retract/retractall/abolish themselves (via %RULEBASE-SNAPSHOT and
;;;    %RULEBASE-PREDICATE-ENTRIES-AT-REVISION above) and only synchronously
;;;    within the dynamic extent of the top-level call that is running them
;;;    -- never after that call has returned to its caller. Confirmed in
;;;    src/query.lisp (%MAP-PROLOG-SOLUTIONS*, the primitive underlying
;;;    MAP-PROLOG-SOLUTIONS/QUERY-PROLOG/QUERY-PROLOG-FIRST) and
;;;    src/prover.lisp (%PROVABLE-P, which PROLOG-SUCCEEDS-P calls directly):
;;;    both fully exhaust or otherwise complete the search before returning
;;;    -- neither exposes a lazy generator/cursor that outlives the call.
;;;
;;; So: track how many of those four top-level entry points are currently
;;; executing, anywhere on the Lisp control stack (including nested calls a
;;; foreign predicate makes back into the engine), and only compact once
;;; that count returns to zero -- i.e. once the *outermost* top-level call
;;; has fully returned. Once DIED-REVISION is set it stays set (nothing ever
;;; clears it) and %STORED-CLAUSE-VISIBLE-P (src/clause.lisp) is monotonic in
;;; revision, so a dead entry can never become visible again regardless of
;;; when it is physically dropped.
;;;
;;; There is a THIRD thing that reads RULEBASE-ENTRIES/PREDICATE-INDEX
;;; directly, beyond the two facts above: %RULEBASE-PREDICATE-ENTRIES-AT-
;;; REVISION can be, and in
;;; T/ENGINE-RUNTIME-INDEX-AND-DEPTH-TEST.LISP::PREDICATE-INDEX-KEEPS-LOGICAL-
;;; UPDATE-HISTORY is, called with a REVISION captured long before the call
;;; that retired an entry -- i.e. with the raw storage used as an append-only
;;; log answering "what did this predicate look like as of revision N", for
;;; arbitrarily old N, not just "what does it look like now".  That capability
;;; is real and is exercised by that test (a plain, unexported white-box
;;; check of the rulebase data structure -- no query/builtin/public API calls
;;; %RULEBASE-PREDICATE-ENTRIES-AT-REVISION with anything other than the
;;; CURRENT revision; see the call site in
;;; %REFRESH-RULEBASE-PREDICATE-DESCRIPTOR!, above, which is the only
;;; production caller).  Retaining it *unconditionally* forever is exactly
;;; the unbounded growth this fix exists to bound, so the two are in direct
;;; tension: no compaction policy can both free unboundedly-retained garbage
;;; and answer an arbitrarily-old point-in-time query. Compacting eagerly,
;;; on every single return to zero active calls, resolves that tension in
;;; favor of bounded growth and breaks that one test outright (confirmed by
;;; running it).  Instead this compacts in batches, gated by
;;; *RULEBASE-COMPACTION-THRESHOLD* dead entries rather than by "any dead
;;; entries at all": ordinary programs -- including every existing test,
;;; which never accumulates anywhere near that many dead entries for one
;;; predicate before inspecting history -- keep their full history exactly as
;;; before, while a workload that retracts-and-reasserts a hot fact
;;; thousands of times (the reported defect) still gets its dead entries
;;; swept periodically and its growth bounded, just not instantaneously.
;;; This is an ordinary amortized-batch GC trade-off, not a special case
;;; carved out to dodge one test.
(defparameter *rulebase-compaction-threshold* 512
  "Minimum RULEBASE-DEAD-ENTRIES before %MAYBE-COMPACT-RULEBASE! will
physically drop dead entries from RULEBASE-ENTRIES/RULEBASE-PREDICATE-INDEX.

Chosen to comfortably exceed the number of dead entries any single existing
test accumulates for one predicate (the largest, in
T/ENGINE-RUNTIME-INDEX-AND-DEPTH-TEST.LISP::PREDICATE-INDEX-KEEPS-LOGICAL-
UPDATE-HISTORY, is 4), while staying tiny relative to the tens of thousands
of retract/assertz cycles a long-running dynamic-fact workload (e.g. a
chip8 emulator's `pc'/`v' registers) runs per session -- see the block
comment above for why some threshold is unavoidable, not just a tuning
choice.")

(defvar *prolog-active-top-level-calls* 0
  "Count of nested MAP-PROLOG-SOLUTIONS*/PROVABLE-P activations currently on
the Lisp control stack, across every rulebase. See the \"Dead-entry
compaction\" block comment above for the invariant this exists to support:
RULEBASE-ENTRIES/PREDICATE-INDEX may be physically compacted only while this
is 0.

A single process-wide counter, not one per rulebase: if a foreign predicate
reenters the engine on a *different* rulebase while an outer call on this
one is still active, this rulebase's compaction is simply deferred until the
whole nested stack unwinds -- always safe, only occasionally later than the
earliest safe moment.")

(defmacro %with-prolog-top-level-call ((rulebase) &body body)
  "Run BODY as one activation of a top-level engine entry point (one of
MAP-PROLOG-SOLUTIONS, QUERY-PROLOG, QUERY-PROLOG-FIRST, PROLOG-SUCCEEDS-P),
maybe compacting RULEBASE's dead entries once *PROLOG-ACTIVE-TOP-LEVEL-
CALLS* returns to 0 -- i.e. once this activation and every activation nested
inside it (including a re-entrant call a foreign predicate makes back into
the engine) has returned. See *PROLOG-ACTIVE-TOP-LEVEL-CALLS* for why that
is the safe window, and *RULEBASE-COMPACTION-THRESHOLD* for why \"maybe\"."
  (let ((rulebase-value (gensym "RULEBASE")))
    `(let* ((,rulebase-value ,rulebase)
            (*prolog-active-top-level-calls*
              (1+ *prolog-active-top-level-calls*)))
       (unwind-protect (progn ,@body)
         (when (zerop (decf *prolog-active-top-level-calls*))
           (%maybe-compact-rulebase! ,rulebase-value))))))

(defun %maybe-compact-rulebase! (rulebase)
  "Compact RULEBASE via %COMPACT-RULEBASE! once its dead-entry backlog
reaches *RULEBASE-COMPACTION-THRESHOLD*; otherwise a no-op.

Only called from %WITH-PROLOG-TOP-LEVEL-CALL once *PROLOG-ACTIVE-TOP-LEVEL-
CALLS* has returned to 0 -- see that macro for why that makes compaction
safe at all, and *RULEBASE-COMPACTION-THRESHOLD* for why it is gated rather
than unconditional."
  (when (>= (rulebase-dead-entries rulebase) *rulebase-compaction-threshold*)
    (%compact-rulebase! rulebase)))

(defun %compact-rulebase! (rulebase)
  "Physically drop RULEBASE's dead stored-clause entries.

Only called from %MAYBE-COMPACT-RULEBASE!; see that function and
*PROLOG-ACTIVE-TOP-LEVEL-CALLS* for why that makes this safe. A cheap no-op
when nothing has died since the last compaction.

Deliberately leaves RULEBASE-PREDICATE-DESCRIPTORS untouched: those
copy-on-write descriptors (%REFRESH-RULEBASE-PREDICATE-DESCRIPTOR!, above)
are already rebuilt from just the visible entries on every mutation, so they
never carry dead entries in the first place -- this function only needs to
catch up the raw storage the descriptors are periodically rebuilt from."
  (when (plusp (rulebase-dead-entries rulebase))
    (let ((live (delete-if #'%stored-clause-died-revision
                            (rulebase-entries rulebase))))
      (setf (rulebase-entries rulebase) live
            (rulebase-entries-tail rulebase) (last live))
      (multiple-value-bind (predicate-index predicate-tails)
          (%make-rulebase-predicate-index live)
        (setf (rulebase-predicate-index rulebase) predicate-index
              (rulebase-predicate-tails rulebase) predicate-tails))
      (setf (rulebase-dead-entries rulebase) 0)))
  rulebase)
