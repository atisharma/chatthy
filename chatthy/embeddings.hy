"
Stuff to do with tokens and embeddings.

The tokenizer defaults to tiktoken's cl100k_default,
because it is fast and does not require pytorch.
"

(require hyrule [of])
(require hyjinx [defmethod])

(import tiktoken)

;; TODO image tokens

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

