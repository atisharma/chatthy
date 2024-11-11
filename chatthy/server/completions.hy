"
Chat completion functions.
"

(require hyrule [of])
(require hyjinx [defmethod])

(import hyjinx [llm first first last config hash-id coroutine])

(import chatthy.embeddings [token-count])
(import chatthy.server.state [cfg])


(defn truncate [messages * [dropped []] [space (:max-tokens cfg 600)]]
  "Shorten the chat history if it gets too long, in which case
  split it and return two lists, the kept messages, and the dropped messages (in pairs).
  Use `space` to preserve space for new output or other messages that are not
  to be dropped.
  Returns `[messages, dropped]`."
  (let [context-length (:context-length cfg 30000)
        ;; Any system message must be in the first position
        ;; or will be silently discarded.
        system-msg (when (and messages
                              (= (:role (first messages))
                                 "system"))
                     (:content (first messages)))
        ;; We assume alternating pairs, 
        chat-msgs (lfor m messages
                    :if (not (= (:role m) "system"))
                    m)
        ;; and need enough space to include chat msgs + system msg + new text.
        truncation-length (- context-length space)
        token-length (token-count messages)]
    (if (> token-length truncation-length)
      ;; If the total is too long, move the first two non-system messages
      ;; to the discard list and recurse.
      (let [kept (cut chat-msgs 2 None)
            new-dropped (+ dropped (cut chat-msgs 0 2))]
        (if system-msg
          (truncate (+ [system-msg] kept) :dropped new-dropped :space space)
          (truncate kept :dropped new-dropped :space space)))
      [messages dropped])))

(defn provider [client-name]
  "Get the API client object from the config."
  (let [client None
        cfg (:providers cfg)
        provider-config (.copy (get cfg client-name)) ; so it's there next time
        scheme (.pop provider-config "scheme" "tabby")
        api-key (.pop provider-config "api_key" None)
        model (.pop provider-config "model" None)
        client (match scheme
                 "anthropic" (llm.Anthropic :api-key api-key)
                 "openai" (llm.OpenAI :api-key api-key)
                 "tabby" (llm.TabbyClient :api-key api-key #** provider-config))]
    (when model
      (llm.model-load client model))
    client))

;; FIXME doesn't work
(defn :async async-stream-completion [#* args #** kwargs]
  "Async generate a streaming completion using the router API endpoint."
  (await (coroutine stream-completion #* args #** kwargs)))

(defmethod stream-completion [#^ str client-name #^ list messages #** kwargs]
  "Generate a streaming completion using the router API endpoint."
  (let [client (provider client-name)]
    (stream-completion client messages #** kwargs)))

(defmethod stream-completion [#^ llm.OpenAI client #^ list messages * [stream True] [max-tokens 4000] #** kwargs]
  "Generate a streaming completion using the chat completion endpoint."
  (let [;; clean non-content fields
        messages (lfor m messages
                       :if (in (:role m) ["user" "assistant" "system"])
                       {"role" (:role m)
                        "content" (:content m)})
        stream (client.chat.completions.create
                 :model (.pop kwargs "model" (getattr client "model" None))
                 :messages messages
                 :stream stream
                 :max-tokens max-tokens
                 #** client._defaults
                 #** kwargs)]
    (for [chunk stream :if chunk.choices]
      (let [text (. (. (first chunk.choices) delta) content)]
        (if text
          (yield text)
          (yield ""))))))

(defmethod stream-completion [#^ llm.Anthropic client #^ list messages * [max-tokens 4000] #** kwargs]
  "Generate a streaming completion using the messages endpoint."
  (let [system-messages (.join "\n"
                               (lfor m messages
                                     :if (= (:role m) "system")
                                     (:content m)))
        ;; clean non-content fields
        messages (lfor m messages
                       :if (in (:role m) ["user" "assistant"])
                       {"role" (:role m)
                        "content" (:content m)})]
    (with [stream (client.messages.stream
                    :model (.pop kwargs "model" (getattr client "model" "claude-3-5-sonnet"))
                    :system system-messages
                    :messages messages
                    :max-tokens max-tokens
                    #** client._defaults
                    #** kwargs)]
      (for [text stream.text-stream :if text]
        (yield text)))))

