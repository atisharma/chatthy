"
Synthesise prompts for retreival-augmented generation.
"

(require trag.template [deftemplate])

(import asyncio)
(import itertools [accumulate])
(import numpy [sum cumsum])
(import re)

(import fvdb [faiss info similar ingest])
(import fvdb.summaries [extractive-summary])
(import fvdb.embeddings [force-import])

(import chatthy.server.state [get-vdb get-ws list-ws])
(import chatthy.embeddings [token-count])


(force-import) ; front-load the delay from loading embeddings


;; * templates
;; -----------------------------------------------------------------------------

(deftemplate summary) ; topic, bullet, paragraph, query, complete_json
(deftemplate retrieval) ; rag, extract, summary_relevance


;; * form messages text with vdb context
;; -----------------------------------------------------------------------------

(defn extract-output [#^ str text]
  "Use tags and regex to extract the text between `<rag:output>` and `</rag:output>`,
  that resulted from the reply of the model to the instruction from `vdb-extracts`
  or `vdb-summaries`."
  (let [pattern (re.compile r"<rag:output>(.*?)</rag:output>" re.DOTALL)]
    (.join "\n" (re.findall pattern text))))

(defn :async vdb-extracts
  [#^ str query
   *
   #^ str profile
   #^ int max-length 
   #^ int [max-results 20]
   #^ int [min-results 3]
   #^ str [key "extract"]]
  "Return formatted extracts from a vdb query.
  Use as a user instruction.
  Return as many results as fit in `max-length` tokens.
  If less than `min-results` results fit in that length,
  retry using summaries instead of extracts."
  (let [v             (await (get-vdb profile))
        results       (similar v query :top max-results)
        ;; Use pre-computed length, otherwise, calculate.
        ;; Neither are accurate for the LLM anyway.
        lengths       (lfor r results
                        (:length r (token-count (get r key))))
        ;; Keep as many results as fit in max-length context
        top           (sum (< (cumsum lengths) max-length))
        extract-list  (lfor r results
                        (retrieval "extract" #** r))
        documents     (.join "\n\n" (cut extract-list top))]
    (cond
      ;; Failure.
      (= top 0)
      "No documents could be retrieved."

      ;; If we have enough results, return,
      (>= top min-results)
      (retrieval "rag" :documents documents :query query)

      ;; otherwise they are too long and we should try the summaries.
      :else
      (await (vdb-extracts query
                           :profile profile 
                           :max-length max-length
                           :max-results max-results 
                           :min-results 0
                           :key "summary")))))

(defn :async vdb-info [* #^ str profile]
  "Get information about the vdb."
  (info (await (get-vdb profile))))

(defn :async vdb-reload [* #^ str profile]
  "Reload the vdb."
  (await (get-vdb profile :reload True)))


;; * form messages text from workspace files
;; -----------------------------------------------------------------------------

(defn workspace-messages [profile]
  "Make a list of user-assistant message pairs to inject at the beginning of the chat.
  Provide one user message per document, empty assistant reply."
  (let [docs (list-ws profile :include-ignored False)
        msgs []]
    (for [doc docs]
      (.append msgs {"role" "user" "content" (retrieval "document" :source doc :text (get-ws profile doc))})
      (.append msgs {"role" "assistant" "content" "Contextual data noted."}))
    msgs))
