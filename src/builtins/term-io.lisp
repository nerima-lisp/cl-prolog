;;;; term_to_atom/2 and read_term_from_atom/3: convert between a term and its
;;;; textual (re-readable) representation, routing parser failures through the
;;;; engine's catchable ISO syntax/resource errors.

(in-package #:cl-prolog)

(defun %parse-term-from-text (text rulebase environment operation)
  "Parse one Prolog term from TEXT under RULEBASE's operator table and
double_quotes flag, converting parser failures into catchable ISO errors."
  (let ((*double-quotes* (%double-quotes-mode rulebase)))
    (handler-case (read-prolog-term text (rulebase-operator-table rulebase))
      (prolog-parser-resource-error (condition)
        (%raise-parser-resource-error condition environment operation))
      (prolog-parse-error (condition)
        (%raise-syntax-error condition environment operation)))))

(defun %term-text-source (value environment operation)
  "Return the textual source of VALUE (an atom, number, or CL string)."
  (cond
    ((logic-var-p value)
     (%raise-instantiation-error environment operation
                                 "the source text must be instantiated"))
    ((stringp value) value)
    ((%term-atom-p value) (%atom-text value))
    ((or (integerp value) (floatp value)) (%number-text value environment operation))
    (t (%raise-type-error "ATOM" value environment operation
                          "expected an atom, number, or string"))))

(define-builtin (term_to_atom term atom) (rulebase environment depth emit)
  (declare (cl:ignore depth))
  (let* ((operation (%iso-atom "TERM_TO_ATOM"))
         (resolved-term (logic-substitute term environment)))
    (if (logic-var-p resolved-term)
        ;; Parse mode: ATOM must be instantiated text.
        (let* ((text (%term-text-source (logic-substitute atom environment)
                                        environment operation))
               (parsed (%parse-term-from-text
                        text rulebase environment operation)))
          (%unify-emit term parsed environment emit))
        ;; Write mode: ATOM = the quoted, re-readable text of TERM.
        (%unify-emit atom (%text-atom (prolog-term-string resolved-term))
                     environment emit))))

(define-builtin (read_term_from_atom atom term options)
    (rulebase environment depth emit)
  (declare (cl:ignore depth))
  (let* ((operation (%iso-atom "READ_TERM_FROM_ATOM"))
         (text (%term-text-source (logic-substitute atom environment)
                                  environment operation))
         (resolved-options (logic-substitute options environment)))
    (unless (or (logic-var-p resolved-options) (%proper-list-p resolved-options))
      (%raise-type-error "LIST" resolved-options environment operation
                         "read_term_from_atom/3 options must be a proper list"))
    (%unify-emit term
                 (%parse-term-from-text text rulebase environment operation)
                 environment emit)))
