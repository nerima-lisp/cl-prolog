;;;; format/1,2,3, tab/1, and print/1 output tests.  Uses the with-io-rulebase
;;;; fixture (defined in builtin-io-terms-test.lisp) to capture current-output.

(in-package #:cl-prolog.tests)

(defmacro assert-format-output (format-string arguments expected)
  "Run format/2 with FORMAT-STRING and ARGUMENTS and assert its captured
current-output equals EXPECTED."
  `(with-io-rulebase (rulebase input output) ""
     (assert-query rulebase
                   (cl-prolog::format ,format-string ,arguments)
                   :succeeds)
     (is (string= (get-output-stream-string output) ,expected))))

(deftest format-renders-basic-directives ()
  (assert-format-output "int=~w atom=~a q=~q" (42 hello (foo bar))
                        "int=42 atom=hello q=foo(bar)")
  (assert-format-output "~d and ~d" (1 2) "1 and 2")
  (assert-format-output "literal ~~ tilde" () "literal ~ tilde")
  (assert-format-output "~a" (plain) "plain"))

(deftest format-renders-numeric-directives ()
  (assert-format-output "~2f" (3.14159d0) "3.14")
  (assert-format-output "~2d" (12345) "123.45")
  (assert-format-output "~d" (12345) "12345")
  (assert-format-output "~D" (1234567) "1,234,567")
  (assert-format-output "~16r" (255) "ff")
  (assert-format-output "~8R" (64) "100")
  (assert-format-output "~c~c" (104 105) "hi"))

(deftest format-renders-newlines-and-strings ()
  (assert-format-output "a~nb" () (format nil "a~%b"))
  (assert-format-output "~s" ((104 105)) "hi")
  (assert-format-output "~s" (abc) "abc"))

(deftest format-column-control-fills-and-aligns ()
  ;; ~t marks a fill point; ~N| sets an absolute column.  The segment "[hi"
  ;; is 3 columns wide, so reaching column 10 needs 7 fill characters.
  (let ((gap (make-string 7 :initial-element #\Space)))
    (assert-format-output "[~t~w~10|]" (hi)
                          (concatenate 'string "[" gap "hi]"))
    (assert-format-output "[~w~t~10|]" (hi)
                          (concatenate 'string "[hi" gap "]"))
    ;; With no ~t fill point the segment is written as-is and padded right.
    (assert-format-output "[~w~10|]" (hi)
                          (concatenate 'string "[hi" gap "]")))
  (assert-format-output "~`-t~10|" () (make-string 10 :initial-element #\-)))

(deftest format-relative-column-control-after-absolute-commit ()
  (assert-format-output "aa~tbb~10|cc~tdd~8+ee" ()
                        "aa      bbcc    ddee"))

(deftest format-reports-too-few-arguments ()
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::format "~w ~w" (only)) :signals)))

(deftest tab-writes-spaces ()
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::tab 4) :succeeds)
    (is (string= (get-output-stream-string output) "    "))))

(deftest print-writes-quoted-term ()
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::print (foo bar)) :succeeds)
    (is (string= (get-output-stream-string output) "foo(bar)"))))

(deftest format-additional-directives ()
  (assert-format-output "~e" (3.14d0) "3.140000e+0")
  (assert-format-output "~2e" (3.14159d0) "3.14e+0")
  (assert-format-output "~g" (3.14d0) "3.14000")
  (assert-format-output "~a" (42) "42")
  (assert-format-output "~3c" (120) "xxx")
  (assert-format-output "~4d" (12) "0.0012")
  (assert-format-output "~r" (64) "100")
  (assert-format-output "~s" ((104 105)) "hi")
  ;; ~p quotes like print/1, unlike ~w.
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::format "~p" (|a b|)) :succeeds)
    (is (string= (get-output-stream-string output) "'a b'")))
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::format "~w" (|a b|)) :succeeds)
    (is (string= (get-output-stream-string output) "a b"))))

(deftest format-star-and-fill-directives ()
  ;; ~* takes the count/column from the next argument.
  (assert-format-output "~*c" (3 120) "xxx")
  ;; fill character in the middle: "ab" then dots to column 8, then "cd".
  (assert-format-output "ab~`.t~8|cd" ()
                        (concatenate 'string "ab" (make-string 6 :initial-element #\.) "cd"))
  ;; two column stops on one line.
  (assert-format-output "~w~t~6|~w~t~12|" (a b)
                        (concatenate 'string "a" (make-string 5 :initial-element #\Space)
                                     "b" (make-string 5 :initial-element #\Space))))

(deftest format-error-contracts-are-catchable ()
  (with-io-rulebase (rulebase input output) ""
    ;; malformed / unknown directives raise catchable ISO errors
    (assert-query rulebase (cl-prolog::format "~" ()) :signals)
    (assert-query rulebase (cl-prolog::format "~5" ()) :signals)
    (assert-query rulebase (cl-prolog::format "~z" (1)) :signals)
    (assert-query rulebase (cl-prolog::format "~40r" (5)) :signals)
    ;; argument type errors
    (assert-query rulebase (cl-prolog::format "~d" (foo)) :signals)
    (assert-query rulebase (cl-prolog::format "~a" ((foo bar))) :signals)
    (assert-query rulebase (cl-prolog::format "~2f" (foo)) :signals)
    (assert-query rulebase (cl-prolog::format "~c" (bar)) :signals)
    (assert-query rulebase (cl-prolog::format "~c" (-1)) :signals)
    (assert-query rulebase (cl-prolog::format "~s" (42)) :signals)
    ;; unbound / wrong-typed format string
    (assert-query rulebase (cl-prolog::format ?f ()) :signals)
    (assert-query rulebase (cl-prolog::format 42 ()) :signals)))

(deftest format-resource-limits-are-catchable ()
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::format "~999999999c" (65)) :signals)
    (assert-query rulebase (cl-prolog::format "~999999999n" ()) :signals)
    (assert-query rulebase (cl-prolog::format "~t~2000000000|" ()) :signals)
    (assert-query rulebase (cl-prolog::tab 999999999) :signals)))

(deftest format-tab-print-stream-arities ()
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::format "hello") :succeeds)
    (is (string= (get-output-stream-string output) "hello")))
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::format cl-prolog::user_output "x=~w" (1))
                  :succeeds)
    (is (string= (get-output-stream-string output) "x=1")))
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::tab cl-prolog::user_output 3) :succeeds)
    (is (string= (get-output-stream-string output) "   ")))
  (with-io-rulebase (rulebase input output) ""
    (assert-query rulebase (cl-prolog::print cl-prolog::user_output (foo bar))
                  :succeeds)
    (is (string= (get-output-stream-string output) "foo(bar)"))))
