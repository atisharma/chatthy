"
Chat completion functions.
"

(require hyjinx.macros [defmethod]) 

(import hyjinx [llm first config])


(defn provider [client-name]
  "Get the API client object from the config."
  (let [client None
        cfg (:providers (config "server.toml"))
        _ (get cfg client-name)
        scheme (.pop _ "scheme" "tabby")
        api-key (.pop _ "api_key" None)
        model (.pop _ "model" None)
        client (match scheme
                 "anthropic" (llm.Anthropic :api-key api-key)
                 "openai" (llm.OpenAI :api-key api-key)
                 "tabby" (llm.TabbyClient :api-key api-key #** _))]
    (when model
     (llm.model-load client model))
    client))

(defmethod stream-completion [#^ str client-name #^ list messages #** kwargs]
  "Generate a streaming completion using the router API endpoint."
  (let [client (provider client-name)]
    (stream-completion client messages #** kwargs)))

(defmethod stream-completion [#^ llm.OpenAI client #^ list messages * [stream True] [max-tokens 4000] #** kwargs]
  "Generate a streaming completion using the chat completion endpoint."
  (let [messages (lfor m messages
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

