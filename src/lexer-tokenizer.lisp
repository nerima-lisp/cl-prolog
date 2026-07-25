;;;; The character-stream tokenizer: reading one term's raw source text,
;;;; then scanning it into %token structs against an operator table's
;;;; lexemes (lexer-operator-lexemes.lisp), under lexer.lisp's resource
;;;; limits.

(in-package #:cl-prolog)

(defun %read-prolog-term-source (stream)
  "Read through one top-level term terminator without consuming the next term."
  (let ((delimiters '())
        (state :code)
        (previous nil)
        (position 0))
    (labels ((record-character (character out)
               (incf position)
               (%check-parser-limit "SOURCE_CHARACTERS"
                                    *max-prolog-source-characters*
                                    position
                                    position)
               (write-char character out))
             (expected-closer (character)
               (cdr (assoc character
                           '((#\( . #\)) (#\[ . #\]) (#\{ . #\}))
                           :test #'char=)))
             (open-delimiter (character)
               (%check-parser-limit "DELIMITER_DEPTH"
                                    *max-prolog-delimiter-depth*
                                    (1+ (length delimiters))
                                    position)
               (push (expected-closer character) delimiters))
             (close-delimiter (character)
               (unless delimiters
                 (%parse-error
                  "Unexpected closing Prolog delimiter ~C at source position ~D."
                  character position))
               (unless (char= character (first delimiters))
                 (%parse-error
                  "Mismatched Prolog delimiter ~C at source position ~D; expected ~C."
                  character position (first delimiters)))
               (pop delimiters)))
      (with-output-to-string (out)
        (loop for character = (read-char stream nil nil)
              do (unless character
                   (unless (member state '(:code :line-comment))
                     (%parse-error
                      "Unexpected end of Prolog input while reading ~A."
                      state))
                   (when delimiters
                     (%parse-error
                      "Unexpected end of Prolog input; expected closing delimiter ~C."
                      (first delimiters)))
                   (return))
                 (record-character character out)
                 (ecase state
                   (:code
                    (cond
                      ;; `0'c' is a character-code constant (ISO 6.4.4), not the
                      ;; start of a quoted atom, so its `'' must not put the
                      ;; splitter into :QUOTED and swallow the rest of the term.
                      ((and (char= character #\') (eql previous #\0))
                       (let ((next (read-char stream nil nil)))
                         (when next
                           (record-character next out)
                           (cond
                             ((char= next #\\)
                              (let ((escaped (read-char stream nil nil)))
                                (when escaped (record-character escaped out))))
                             ;; `0''' spells the quote character itself.
                             ((and (char= next #\')
                                   (eql (peek-char nil stream nil nil) #\'))
                              (record-character (read-char stream) out)))
                           (setf character next))))
                      ((char= character #\') (setf state :quoted))
                      ((char= character #\") (setf state :dquoted))
                      ((char= character #\%) (setf state :line-comment))
                      ((and (char= character #\/)
                            (eql (peek-char nil stream nil nil) #\*))
                       (record-character (read-char stream) out)
                       (setf state :block-comment))
                      ((member character '(#\( #\[ #\{))
                       (open-delimiter character))
                      ((member character '(#\) #\] #\}))
                       (close-delimiter character))
                      ((and (null delimiters)
                            (char= character #\.)
                            (not (and previous
                                      (digit-char-p previous)
                                      (let ((next
                                              (peek-char nil stream nil nil)))
                                        (and next (digit-char-p next))))))
                       (return))))
                   (:quoted
                    (cond
                      ((char= character #\\)
                       (setf state :quoted-escape))
                      ((char= character #\')
                       (if (eql (peek-char nil stream nil nil) #\')
                           (progn
                             (record-character (read-char stream) out)
                             (setf previous #\'))
                           (setf state :code)))))
                   (:quoted-escape (setf state :quoted))
                   (:dquoted
                    (cond
                      ((char= character #\\)
                       (setf state :dquoted-escape))
                      ((char= character #\")
                       (if (eql (peek-char nil stream nil nil) #\")
                           (progn
                             (record-character (read-char stream) out)
                             (setf previous #\"))
                           (setf state :code)))))
                   (:dquoted-escape (setf state :dquoted))
                   (:line-comment
                    (when (char= character #\Newline)
                      (setf state :code)))
                   (:block-comment
                    (when (and (char= character #\*)
                               (eql (peek-char nil stream nil nil) #\/))
                      (record-character (read-char stream) out)
                      (setf state :code))))
                 (setf previous character))))))

(defun %prolog-source-string (source)
  (etypecase source
    (string
     (%check-parser-limit "SOURCE_CHARACTERS"
                          *max-prolog-source-characters*
                          (length source)
                          (length source))
     source)
    (stream (%read-prolog-term-source source))))

(defun %tokenize-prolog (source &optional (operator-table *standard-operator-table*))
  (let* ((text (%prolog-source-string source))
         (length (length text))
         (position 0)
         (operator-lexemes (%operator-table-lexemes operator-table))
         (word-operators (car operator-lexemes))
         (symbolic-tokens (cdr operator-lexemes))
         (conversions *active-char-conversions*)
         (raw-mode nil)
         (token-count 0)
         (delimiters '())
         (tokens '()))
    (labels ((peek (&optional (offset 0))
               (let ((index (+ position offset)))
                 (when (< index length)
                   (let ((character (char text index)))
                     (if (and conversions (not raw-mode))
                         (or (gethash character conversions) character)
                         character)))))
             (take ()
               (prog1 (peek) (incf position)))
             (expected-closer (operator)
               (cond ((string= operator "(") ")")
                     ((string= operator "[") "]")
                     ((string= operator "{") "}")))
             (note-delimiter (operator start)
               (let ((closer (expected-closer operator)))
                 (cond
                   (closer
                    (%check-parser-limit "DELIMITER_DEPTH"
                                         *max-prolog-delimiter-depth*
                                         (1+ (length delimiters))
                                         start)
                    (push closer delimiters))
                   ((member operator '(")" "]" "}") :test #'string=)
                    (unless delimiters
                      (%parse-error
                       "Unexpected closing Prolog delimiter ~A at source position ~D."
                       operator start))
                    (unless (string= operator (first delimiters))
                      (%parse-error
                       "Mismatched Prolog delimiter ~A at source position ~D; expected ~A."
                       operator start (first delimiters)))
                    (pop delimiters)))))
             (emit (kind &optional value (start position))
               (unless (eq kind :eof)
                 (%check-parser-limit "TOKEN_COUNT"
                                      *max-prolog-tokens*
                                      (1+ token-count)
                                      start)
                 (incf token-count))
               (when (eq kind :operator)
                 (note-delimiter value start))
               (push (%token kind value start) tokens))
             (skip-line ()
               (loop while (and (peek) (not (char= (peek) #\Newline)))
                     do (take)))
             (skip-block ()
               (incf position 2)
               (loop until (and (peek) (peek 1)
                                (char= (peek) #\*)
                                (char= (peek 1) #\/))
                     do (unless (peek)
                          (%parse-error "Unterminated Prolog block comment."))
                        (take))
               (incf position 2))
             (scan-name ()
               (let ((start position))
                 (with-output-to-string (out)
                   (loop while (and (peek) (%identifier-character-p (peek)))
                         do (%check-parser-limit
                             "IDENTIFIER_LENGTH"
                             *max-prolog-identifier-length*
                             (1+ (- position start))
                             position)
                            (write-char (take) out)))))
             (scan-radix-escape (radix terminated-p)
               "Read the digits of a `\\xHH\\' or `\\OOO\\' escape as a character."
               (let ((digits (with-output-to-string (out)
                               (loop while (and (peek) (digit-char-p (peek) radix))
                                     do (write-char (take) out)))))
                 (when (zerop (length digits))
                   (%parse-error "Malformed Prolog character escape at position ~D."
                                 position))
                 ;; ISO 6.4.2.1 closes both forms with `\', which SWI also
                 ;; accepts without; tolerate the missing one either way.
                 (when (and terminated-p (eql (peek) #\\)) (take))
                 (let ((code (parse-integer digits :radix radix)))
                   (unless (< code char-code-limit)
                     (%parse-error "Prolog character escape ~S is out of range."
                                   digits))
                   (code-char code))))
             (scan-escape ()
               "Decode the escape sequence after a `\\', per ISO 6.4.2.1.

Returns NIL for a `\\'-newline continuation, which contributes no character."
               (let ((character (take)))
                 (case character
                   (#\a (code-char 7))
                   (#\b #\Backspace)
                   (#\f #\Page)
                   (#\n #\Newline)
                   (#\r #\Return)
                   (#\t #\Tab)
                   (#\v (code-char 11))
                   (#\e (code-char 27))
                   (#\0 (code-char 0))
                   (#\x (scan-radix-escape 16 t))
                   (#\Newline nil)
                   (t (if (digit-char-p character 8)
                          (progn (decf position) (scan-radix-escape 8 t))
                          ;; \\ \' \" \` and anything else stand for themselves.
                          character)))))
             (scan-quoted ()
               (take)
               (setf raw-mode t)
               (unwind-protect
                    (let ((content-length 0))
                      (labels ((write-content (character out)
                                 (incf content-length)
                                 (%check-parser-limit
                                  "QUOTED_LEXEME_LENGTH"
                                  *max-prolog-quoted-lexeme-length*
                                  content-length
                                  position)
                                 (write-char character out)))
                        (with-output-to-string (out)
                          (loop
                            (unless (peek)
                              (%parse-error "Unterminated quoted Prolog atom."))
                            (let ((character (take)))
                              (cond
                                ((and (char= character #\')
                                      (peek)
                                      (char= (peek) #\'))
                                 (take)
                                 (write-content #\' out))
                                ((char= character #\')
                                 (return))
                                ((and (char= character #\\) (peek))
                                 (let ((decoded (scan-escape)))
                                   (when decoded (write-content decoded out))))
                                (t
                                 (write-content character out))))))))
                 (setf raw-mode nil)))
             (scan-string ()
               ;; A "..." literal, mirroring SCAN-QUOTED but delimited by #\".
               ;; A doubled "" is a literal quote; \\-escapes are decoded.
               (take)
               (setf raw-mode t)
               (unwind-protect
                    (let ((content-length 0))
                      (labels ((write-content (character out)
                                 (incf content-length)
                                 (%check-parser-limit
                                  "QUOTED_LEXEME_LENGTH"
                                  *max-prolog-quoted-lexeme-length*
                                  content-length
                                  position)
                                 (write-char character out)))
                        (with-output-to-string (out)
                          (loop
                            (unless (peek)
                              (%parse-error "Unterminated Prolog string."))
                            (let ((character (take)))
                              (cond
                                ((and (char= character #\")
                                      (peek)
                                      (char= (peek) #\"))
                                 (take)
                                 (write-content #\" out))
                                ((char= character #\")
                                 (return))
                                ((and (char= character #\\) (peek))
                                 (let ((decoded (scan-escape)))
                                   (when decoded (write-content decoded out))))
                                (t
                                 (write-content character out))))))))
                 (setf raw-mode nil)))
             (block-comment-ahead-p ()
               (and (eql (peek) #\/) (eql (peek 1) #\*)))
             (scan-graphic-run ()
               "Consume the maximal run of graphic characters at POSITION.

Stops before a `/*' so an adjacent block comment still opens where it would
have without the run, as in `a +/* note */ b'."
               (let ((start position))
                 (loop while (and (%prolog-graphic-character-p (peek))
                                  (not (and (> position start)
                                            (block-comment-ahead-p))))
                       do (%check-parser-limit
                           "IDENTIFIER_LENGTH"
                           *max-prolog-identifier-length*
                           (1+ (- position start))
                           position)
                          (take))
                 (subseq text start position)))
             (end-token-follows-p ()
               "True when a lone `.' just consumed ends a clause: ISO 6.4.8
requires layout text, a comment, or end of input after the end token."
               (let ((next (peek)))
                 (or (null next)
                     (member next '(#\Space #\Tab #\Return #\Newline))
                     (char= next #\%))))
             (radix-digit-p (character radix)
               (and character (digit-char-p character radix)))
             (scan-radix-integer (radix)
               "Read the digits of an `0x'/`0o'/`0b' integer constant."
               (incf position 2)
               (let ((start position))
                 (loop while (radix-digit-p (peek) radix)
                       do (%check-parser-limit
                           "NUMERIC_LEXEME_LENGTH"
                           *max-prolog-numeric-lexeme-length*
                           (1+ (- position start))
                           position)
                          (take))
                 (parse-integer (subseq text start position) :radix radix)))
             (scan-character-code ()
               "Read an `0'c' character-code constant, per ISO 6.4.4."
               (incf position 2)
               (let ((character (peek)))
                 (cond
                   ((null character)
                    (%parse-error "Unterminated Prolog character-code constant."))
                   ;; `0''' is the quote itself, doubled as inside a quoted atom.
                   ((char= character #\')
                    (take)
                    (when (eql (peek) #\') (take))
                    (char-code #\'))
                   ((char= character #\\)
                    (take)
                    (let ((decoded (scan-escape)))
                      (unless decoded
                        (%parse-error
                         "A `\\'-newline continuation is not a character code."))
                      (char-code decoded)))
                   (t (take) (char-code character)))))
             (scan-number ()
               ;; ISO 6.4.4's non-decimal integer constants all begin with `0'.
               (when (and (char= (peek) #\0) (peek 1))
                 (let ((marker (char-downcase (peek 1))))
                   (case marker
                     (#\' (return-from scan-number (scan-character-code)))
                     (#\x (when (radix-digit-p (peek 2) 16)
                            (return-from scan-number (scan-radix-integer 16))))
                     (#\o (when (radix-digit-p (peek 2) 8)
                            (return-from scan-number (scan-radix-integer 8))))
                     (#\b (when (radix-digit-p (peek 2) 2)
                            (return-from scan-number (scan-radix-integer 2)))))))
               (let ((start position))
                 (labels ((take-number-character ()
                            (%check-parser-limit
                             "NUMERIC_LEXEME_LENGTH"
                             *max-prolog-numeric-lexeme-length*
                             (1+ (- position start))
                             position)
                            (take)))
                   (loop while (and (peek) (digit-char-p (peek)))
                         do (take-number-character))
                   (let ((float-p nil))
                     (when (and (peek) (peek 1)
                                (char= (peek) #\.)
                                (digit-char-p (peek 1)))
                       (setf float-p t)
                       (take-number-character)
                       (loop while (and (peek) (digit-char-p (peek)))
                             do (take-number-character)))
                     (when (and (peek) (member (peek) '(#\e #\E)))
                       (setf float-p t)
                       (take-number-character)
                       (when (and (peek) (member (peek) '(#\+ #\-)))
                         (take-number-character))
                       (unless (and (peek) (digit-char-p (peek)))
                         (%parse-error "Malformed Prolog exponent."))
                       (loop while (and (peek) (digit-char-p (peek)))
                             do (take-number-character)))
                     (let ((lexeme (subseq text start position)))
                       (if float-p
                           (let ((*read-default-float-format* 'double-float))
                             (read-from-string lexeme))
                           (parse-integer lexeme))))))))
      (loop while (peek)
            do (let ((start position))
                 (cond
                   ((member (peek) '(#\Space #\Tab #\Return #\Newline))
                    (take))
                   ((char= (peek) #\%)
                    (skip-line))
                   ((and (char= (peek) #\/)
                         (peek 1)
                         (char= (peek 1) #\*))
                    (skip-block))
                   ((char= (peek) #\')
                    (emit :quoted-atom (scan-quoted) start))
                   ((char= (peek) #\")
                    (emit :string (scan-string) start))
                   ((digit-char-p (peek))
                    (emit :number (scan-number) start))
                   ((or (upper-case-p (peek)) (char= (peek) #\_))
                    (emit :variable (scan-name) start))
                   ((lower-case-p (peek))
                    (let ((name (scan-name)))
                      (if (member name word-operators :test #'string=)
                          (emit :operator name start)
                          (emit :atom name start))))
                   ;; A run of graphic characters is one token, per ISO 6.4.2 --
                   ;; not the longest declared operator that happens to prefix
                   ;; it, which would split `===' into `==' and `='.
                   ((%prolog-graphic-character-p (peek))
                    (let ((run (scan-graphic-run)))
                      (cond
                        ((and (string= run ".") (end-token-follows-p))
                         (emit :operator "." start))
                        ((member run symbolic-tokens :test #'string=)
                         (emit :operator run start))
                        ;; An undeclared graphic token is simply an atom.
                        (t (emit :atom run start)))))
                   (t
                    (let ((operator
                            (find-if
                             (lambda (candidate)
                               (and (<= (+ position (length candidate)) length)
                                    (loop for index from 0 below (length candidate)
                                          always (eql (char candidate index)
                                                      (peek index)))))
                             symbolic-tokens)))
                      (if operator
                          (progn
                            (incf position (length operator))
                            (emit :operator operator start))
                          (let ((character (take)))
                            (if (char= character #\!)
                                (emit :atom "!" start)
                                (%parse-error
                                 "Unexpected Prolog character ~S at source position ~D."
                                 character start)))))))))
      (when delimiters
        (%parse-error
         "Unexpected end of Prolog input; expected closing delimiter ~A."
         (first delimiters)))
      (emit :eof nil position)
      (coerce (nreverse tokens) 'vector))))

(defun %current-token (parser)
  (aref (%parser-tokens parser) (%parser-position parser)))

(defun %peek-token (parser &optional (offset 1))
  "Return the token OFFSET positions past the current one.

Reading past the end yields the terminating :EOF token, which every token
vector carries, so a caller never has to bounds-check its lookahead."
  (let ((tokens (%parser-tokens parser)))
    (aref tokens (min (+ (%parser-position parser) offset)
                      (1- (length tokens))))))

(defun %accept-token (parser kind &optional value)
  (let ((token (%current-token parser)))
    (when (and (eq kind (%token-kind token))
               (or (null value) (equal value (%token-value token))))
      (incf (%parser-position parser))
      token)))

(defun %expect-token (parser kind &optional value)
  (or (%accept-token parser kind value)
      (%parse-error "Expected Prolog token ~S~@[ ~S~], got ~S."
                    kind value (%current-token parser))))
