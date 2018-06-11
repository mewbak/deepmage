(import [asciimatics.event [KeyboardEvent]])
(import [asciimatics.screen [Screen]])
(import bitstring)

(defmacro word-idx [coords]
  `(do
    (+
      (get ~coords 0)
      (* self.ui.words-in-line
        (get ~coords 1)))))

(defmacro keymap [&rest key-tuples]
  (dict-comp
    (first tup)
    (if (> (len tup) 2)
      `(fn []
        (when ~(get tup 2)
          (do
            (setv self.old-coords self.coords)
            ~(second tup))))
      `(fn []
        (setv self.old-coords self.coords)
        ~(second tup)))
    [tup key-tuples]))

(defclass BasicCursor [object]
  (defn --init-- [self ui &optional coords]
    (setv self.ui ui)
    (setv self.coords (if coords coords (, 0 0)))
    (setv self.old-coords self.coords)
    (setv self.cursor-at-word 0)
    (setv self.alphabet "1234567890abcdef")
    (setv self.write-buffer [])
    (setv self.keys
      (keymap               ; we execute a function corresponding to a key
          [Screen.*key-right*   ; if a condition is satisfied
           (setv self.coords (, (+ (get self.coords 0) 1)
                                (get self.coords 1)))
           (< (.word-idx-in-file self) (- self.ui.total-words 1))]
          [Screen.*key-left*
           (setv self.coords (, (- (get self.coords 0) 1)
                                (get self.coords 1)))
           (> (.word-idx-in-file self) 0)]
          [Screen.*key-down*
           (setv self.coords (, (get self.coords 0)
                                (+ (get self.coords 1) 1)))
           (< (.word-idx-in-file self) (- self.ui.total-words self.ui.words-in-line))]
          [Screen.*key-up*
           (setv self.coords (, (get self.coords 0)
                                (- (get self.coords 1) 1)))
           (> (.word-idx-in-file self) (- self.ui.words-in-line 1))]
           [Screen.*key-home*
            (setv self.coords (, 0
                                 (get self.coords 1)))]
           [Screen.*key-end*
            (setv self.coords (, (- self.ui.words-in-line 1)
                                 (get self.coords 1)))]
           [Screen.*key-page-up*
            (do
              (setv self.ui.starting-word (- self.ui.starting-word self.ui.words-in-view))
              (setv self.ui.view-changed True))]
           [Screen.*key-page-down*
            (do
              (setv self.ui.starting-word (+ self.ui.starting-word self.ui.words-in-view))
              (setv self.ui.view-changed True))
            (< self.ui.starting-word (- self.ui.total-words self.ui.words-in-view))])))
  (defn word-idx-in-view [self]
    (word-idx self.coords))
  (defn old-word-idx-in-view [self]
    (word-idx self.old-coords))
  (defn word-idx-in-file [self]
    (+ self.ui.starting-word (word-idx self.coords)))
  (defn cursor-moved [self]
    (setv self.write-buffer [])
    (setv old-start self.ui.starting-word)
    (cond
      [(>= (get self.coords 0) self.ui.words-in-line)  ; checking the line boundaries
       (setv self.coords (, 0                          ; and handling edge cases
                            (+ (get self.coords 1) 1)))]
      [(< (get self.coords 0) 0)
        (setv self.coords (, (- self.ui.words-in-line 1)
                             (- (get self.coords 1) 1)))])
    (cond
      [(>= (get self.coords 1) self.ui.lines)
       (do (setv self.ui.starting-word (+ self.ui.starting-word self.ui.words-in-line))
           (setv self.coords (, (get self.coords 0)
                                (- self.ui.lines 1))))]
      [(< (get self.coords 1) 0)
       (do (setv self.ui.starting-word
             (if
               (> self.ui.starting-word 0)
               (- self.ui.starting-word self.ui.words-in-line)
               0))
           (setv self.coords (, (get self.coords 0)
                                0)))])
    (when (>  (.word-idx-in-file self) self.ui.total-words)
      (setv self.coords (, (- (% self.ui.total-words self.ui.words-in-line) 1)
                           (// (- self.ui.total-words self.ui.starting-word 1) self.ui.words-in-line))))
    (setv self.ui.starting-word
      (max 0
        (min self.ui.starting-word
          (+
            (- self.ui.total-words self.ui.words-in-line)
            (% self.ui.starting-word self.ui.words-in-line)))))
    (unless (= old-start self.ui.starting-word) (setv self.ui.view-changed True)))
  (defn handle-key-event [self k]
    (try
      ((get self.keys k))
      (except [KeyError] (return)))  ; if no keypress was recognized, we return early
      (.cursor-moved self))
  (defn get-human-readable-position-data [self]
    (-> "{}/{} {}"
        (.format
          (+ (.word-idx-in-file self) 1)
          self.ui.total-words
          self.coords)
        (+ (* " " self.ui.screen.width))))
  (defn write-at-cursor [self char]
    (unless (in (chr char) self.alphabet) (raise (ValueError "Not a hex digit")))
    (.append self.write-buffer char)
    (when (= (len self.write-buffer) self.ui.chars-per-word)
      (assoc self.ui.reader (.word-idx-in-file self)
        (-> (bitstring.ConstBitArray
              (+ "0x" (.join "" (list-comp (chr x) [x self.write-buffer]))))
            (get (slice None None -1))
            (get (slice None (.get-wordsize self.ui.reader)))
            (get (slice None None -1))))
      (setv self.ui.view-changed True)
      (.handle-key-event self Screen.*key-right*))))

(defclass BitCursor [BasicCursor]
  (defn --init-- [self ui &optional coords]
    (.--init-- (super BitCursor self) ui (when coords coords))
    (setv self.alphabet "01"))) ; TODO: moving the cursor by bits, not words