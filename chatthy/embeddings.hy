"
Stuff to do with tokens and embeddings.

The tokenizer defaults to tiktoken's o200k_base,
because it is fast, modern and does not require pytorch.
"

(require hyrule [of])
(require hyjinx [defmethod])

(import functools [lru-cache])
(import tiktoken)

;; TODO image handling
;; TODO remote embeddings endpoint (done in chasm?)

;; the default encoder / tokenizer is set as state in tiktoken module
;(setv default-tokenizer (tiktoken.get-encoding "cl100k_base"))
(setv default-tokenizer (tiktoken.get-encoding "o200k_base"))

(defmethod encode [#^ (of list dict) x * [tokenizer default-tokenizer]]
  "Return the embedding tokens for x (list of chat messages)."
  (tokenizer.encode (.join "\n" (lfor m x (:content m)))))

(defmethod encode [x * [tokenizer default-tokenizer]]
  "Return the embedding tokens for x
  (anything with a meaningful __str__ or __repr__)."
  (tokenizer.encode (str x)))

(defn token-count [x * [tokenizer default-tokenizer]]
  "Return the number of embedding tokens, roughly, of x
  (anything with a meaningful __str__ or __repr__)."
  (len (encode x :tokenizer tokenizer)))


(defclass APITokenizer []
  "Remote endpoint embeddings."
  ;; TODO
  (defn encode [self text]))
