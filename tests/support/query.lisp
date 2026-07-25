;;;; Query expectation helpers.
;;;;
;;;; DEFTEST-QUERIES and ASSERT-QUERY are cl-prolog.tests's own query
;;;; assertions no longer here: the suite dogfoods the public
;;;; CL-PROLOG/WEAVE package (src/weave.lisp) directly, inherited via
;;;; cl-prolog.tests's :USE clause.

(in-package #:cl-prolog.tests)

(defun prolog-goal-holds-p (source)
  "True when the goal SOURCE, read as Prolog source text, has a proof.

Lets a case be written the way a user would type it, so an assertion about ISO
conformance does not have to spell the engine's internal term shapes."
  (prolog-succeeds-p (make-rulebase) (read-prolog-term source)))

(defmacro deftest-prolog-goals (name &body sources)
  "Define one cl-weave case per Prolog goal SOURCE, each asserting it succeeds.

Each case is independent and labelled with its own source text, so a failure
names the goal that failed rather than the whole group."
  `(cl-weave:describe-sequential ,(string name)
     ,@(mapcar
        (lambda (source)
          `(cl-weave:it ,source
             (cl-weave:expect-has-assertions)
             (is (prolog-goal-holds-p ,source))))
        sources)))

(defmacro with-single-query-solution ((solution solutions rulebase query &rest options)
                                      &body body)
  "Execute QUERY once, assert that it yields exactly one solution, and bind it.

SOLUTIONS receives the full result list and SOLUTION receives the first solution.
Trailing OPTIONS are passed to QUERY-PROLOG."
  `(let ((,solutions (query-prolog ,rulebase ,query ,@options)))
     (is (= 1 (length ,solutions))
         "query must yield exactly one solution")
     (let ((,solution (first ,solutions)))
       ,@body)))
