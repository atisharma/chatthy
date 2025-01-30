"
Implements server's RPC methods (commands)
"

(require hyrule.argmove [-> ->>])

(import hyjinx.lib [first last short-id])
(import hyjinx.wire [wrap rpc rpcs])

(import inspect [signature])
(import re)
(import tabulate [tabulate])
(import time [time])

(import trag [retrieve])
(require trag.template [deftemplate])

(import chatthy [__version__])
(import chatthy.server.completions [stream-completion truncate])
(import chatthy.embeddings [token-count])
(import chatthy.server.rag [vdb-extracts vdb-info vdb-reload
                            extract-output
                            workspace-messages])
(import chatthy.server.state [cfg
                              socket
                              get-prompts get-prompt update-prompt
                              get-chat set-chat delete-chat copy-chat rename-chat list-chats
                              get-ws write-ws drop-ws rename-ws list-ws
                              get-account set-account update-account])


(deftemplate summary)

;; * Client RPC message handling
;; -----------------------------------------------------------------------------

(defn :async client-rpc [sid method #** kwargs]
  "Remotely call a client method with kwargs that a client expects.
  Wraps and sends the message to the client."
  (let [msg {"method" method #** kwargs}]
    (await (.send-multipart socket [sid (wrap msg)]))))

;; * The server's RPC methods, offered to the client, registered to hyjinx.wire
;; -----------------------------------------------------------------------------

(defn :async [rpc] status [* sid #** kwargs]
  "HIDDEN
  Respond to a status request with a status update."
  (await (client-rpc sid "status" :result f"v{__version__} ✅")))

(defn :async [rpc] echo [* sid result #** kwargs]
  "HIDDEN
  Send a chat message to the client."
  (await (client-rpc sid
                     "echo"
                     :result {"role" "server" "content" result})))

(defn :async [rpc] account [* sid profile #** kwargs]
  "Show account details."
  ;; TODO return dict, not text
  (let [d-account (get-account profile)]
    (.pop d-account "prompts" None)
    (await (echo :sid sid
                 :result (+ f"account {profile}\n\n"
                            (tabulate (.items d-account)
                                      :maxcolwidths [None 60]))))))

(defn :async [rpc] prompts [* sid profile [name None] [prompt None] #** kwargs]
  "Gets/sets a named system prompt for a user. With just name given, edit it. With no kwargs, list them."
  (let [prompts (get-prompts profile)]
    (cond
      ;; client has specified both prompt name and text, so set the prompt
      (and name prompt)
      (update-prompt profile prompt-name prompt)

      ;; client hasn't specified prompt text, so just get and return
      (and name)
      (await (client-rpc :sid sid
                         :method "set_prompt"
                         :name name
                         :prompt (.get prompts name "")))

      ;; client specifies nothing, so just list them
      :else
      (await (client-rpc sid "prompts"
                         :result (sorted
                                   (lfor [k v] (.items prompts)
                                     {"prompt" k "prompt text" v})
                                   :key :prompt))))))

(defn :async [rpc] providers [* sid #** kwargs]
  "List the providers available to clients."
  (await (client-rpc sid "providers"
                     :result (sorted (list (.keys (:providers cfg)))))))

(defn :async [rpc] commands [* sid #** kwargs]
  "List the commands advertised to clients."
  ;; RPCs with docstring starting with 'HIDDEN' are not advertised.
  (await (client-rpc sid
                     "commands"
                     :result (lfor [k v] (.items rpcs)
                               :if (and v.__doc__
                                        (not (.startswith v.__doc__ "HIDDEN")))
                               (let [sig (->> (signature v)
                                              (str)
                                              (re.sub r"sid, " "")
                                              (re.sub r", \*\*kwargs" "")
                                              (re.sub r"\(\*" "")
                                              (re.sub r"\)" "")
                                              (re.sub r", " " :")
                                              (re.sub r" :profile" "")
                                              (re.sub r" :provider" "")
                                              (re.sub r" :chat" "")
                                              (re.sub r"=['\w]+" ""))]
                                 {"command" k
                                  "kwargs" sig
                                  "docstring" (.replace v.__doc__ "  " "\n")})))))

(defn :async [rpc] vdbinfo [* sid profile #** kwargs]
  "Show info on the state of the vdb."
  (let [d-info (await (vdb-info :profile profile))]
    (await (echo :sid sid
                 :result (+ f"vdb for {profile}\n\n"
                            (tabulate (.items d-info)))))))

(defn :async [rpc] vdbreload [* sid profile #** kwargs]
  "Reload the vdb (e.g. after adding files)."
  (await (vdb-reload :profile profile)))


;; * chat management
;; TODO smooth slight inconsistency between ws and chat management
;; -----------------------------------------------------------------------------

(defn :async [rpc] chats [* sid profile #** kwargs]
  "List the user's saved chats."
  (await (client-rpc sid "chats" :result (list-chats profile))))

(defn :async [rpc] destroy [* sid profile chat #** kwargs]
  "Destroy a chat (by default, the current chat)."
  (delete-chat profile chat)
  (await (messages :sid sid :profile profile :chat chat))
  (await (client-rpc sid "info" :result "Chat destroyed.")))

(defn :async [rpc] rename [* sid profile chat to #** kwargs]
  "Rename the user's chat."
  (rename-chat profile chat to)
  (await (chats :sid sid :profile profile)))

(defn :async [rpc] fork [* sid profile chat to #** kwargs]
  "Make a copy of the user's chat."
  (copy-chat profile chat to)
  (await (chats :sid sid :profile profile)))


;; * workspace management
;; -----------------------------------------------------------------------------

(defn :async [rpc] ws
  [*
   sid
   profile
   [drop False]
   [ignore False]
   [fname False]
   [text ""]
   [arxiv False]
   [news False]
   [url False]
   [wikipedia False]
   [youtube False]
   #** kwargs]
  "With kwarg `:drop fname`, completely remove file `drop` from the profile's workspace.
  With `:ignore fname`, toggle ignore status of file `ignore`.
  With `:fname fname`, store `:text \"text\"` into a file in the profile's current workspace.
  With `:youtube id`, put the transcript of a youtube video in the workspace.
  With `:url \"url\"`, put a the contents of a url the workspace.
  With `:arxiv \"search topic\"`, put a the results of an arXiv search (abstracts) in the workspace.
  With `:wikipedia \"topic\"`, put a wikipedia article in the workspace.
  Otherwise list files available in a profile's workspace."
  (cond
    ;; ws files from sources
    youtube
    (let [text (retrieve.youtube youtube :punctuate (:punctuate cfg False))
          fname f"youtube-{youtube}"]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded transcript for YouTube video {youtube} into context workspace.")))

    url
    (let [text (retrieve.url url)
          fname (retrieve.filename-from-url url)]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded {url} into context workspace, saved as '{fname}'.")))

    arxiv
    (let [text (retrieve.arxiv arxiv)
          fname (+ "arxiv-" (short-id arxiv))]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded arXiv search into context workspace, saved as '{fname}'.")))

    news
    (let [text (retrieve.ddg-news news)
          fname (+ "news-" (short-id news))]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded news query into context workspace, saved as '{fname}'.")))

    wikipedia
    (let [text (retrieve.wikipedia wikipedia)
          fname (+ "wikipedia-" (short-id wikipedia))]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded wikipedia query into context workspace, saved as '{fname}'.")))

    (and fname text)
    (do
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded file '{fname}' into context workspace.")))

    ;; print contents
    fname
    (await (client-rpc sid "info" :result (.join "\n\n" [f"Contents of workspace file {fname}:"
                                                         (get-ws profile fname)])))

    ;; ws file management
    drop
    (do
      (drop-ws profile drop)
      (await (client-rpc sid "info" :result f"Dropped '{drop}' from context workspace.")))

    ignore
    (let [new-fname (if (.startswith ignore "__")
                      (cut ignore 2 None)
                      (+ "__" ignore))]
      (rename-ws profile ignore new-fname)
      (await (client-rpc sid "info" :result f"Toggled ignore for '{ignore}' in context workspace.")))

    ;; else just list files
    :else (await (client-rpc sid "workspace" :result (lfor fname (list-ws profile)
                                                           {"name" fname
                                                            "ignored" (.startswith fname "__")
                                                            "length" (token-count (get-ws profile fname))})))))


;; * management of messages, generation
;; -----------------------------------------------------------------------------

(defn :async stream-reply [sid chat provider messages #** kwargs]
  "Request and stream a reply from the provider's API."
  (let [reply ""]
    (for [:async chunk (stream-completion provider messages #** kwargs)]
      (+= reply chunk)
      (await (client-rpc sid "chunk" :result chunk :chat chat))
      (await (client-rpc sid "status" :result "streaming ✅")))
    (await (client-rpc sid "chunk" :result "\n\n" :chat chat))
    (await (client-rpc sid "status" :result "ready ✅"))
    reply))

(defn :async [rpc] messages [* sid profile chat #** kwargs]
  "HIDDEN
  Send all the user's messages.
  "
  (await (client-rpc sid
                     "messages"
                     :chat (get-chat profile chat)
                     :workspace (workspace-messages profile))))

(defn :async [rpc] undo [* sid profile chat #** kwargs]
  "Destroy the last message pair (default current chat)."
  (let [messages (cut (get-chat profile chat) -2)]
    (set-chat messages profile chat))
  (await (messages :sid sid :profile profile :chat chat)))

;; TODO consolidate `chat`, `vdb` and `smry` rpcs.

(defn :async [rpc] chat [* sid profile chat prompt-name line provider #** kwargs]
  "HIDDEN
  Normal chat RPC, return input to client followed by a stream of the reply.
  Add the new message pair to the saved chat."
  (await (client-rpc sid "echo" :result {"role" "user" "content" line}))
  (let [system-prompt (get-prompt profile prompt-name)
        system-msg {"role" "system" "content" system-prompt}
        usr-msg {"role" "user" "content" line "timestamp" (time)}
        ws-msgs (workspace-messages profile)
        saved-messages (get-chat profile chat)
        [messages dropped] (truncate saved-messages
                                     :space (+ (:max-tokens cfg 600)
                                               (token-count system-prompt)
                                               (token-count ws-msgs)
                                               (token-count line))
                                     :provider provider)
        sent-messages [system-msg #* ws-msgs #* messages usr-msg]
        reply (await (stream-reply sid chat provider sent-messages #** kwargs))]
    (.append saved-messages usr-msg)
    (.append saved-messages {"role" "assistant" "content" (.strip reply) "timestamp" (time)})
    (set-chat saved-messages profile chat)))

(defn :async [rpc] vdb [* sid profile chat prompt-name query provider #** kwargs]
  "HIDDEN
  Do RAG using the vdb alongside the chat context to respond to the query.
  `prompt_name` optionally specifies use of a particular prompt (by name).
  `query` specifies the text of the query."
  ;; FIXME  guard against final user message being too long;
  ;;        recursion depth in `truncate`?
  ;; TODO offer as tool
  (await (client-rpc sid "status" :result "querying ⏳"))
  (await (client-rpc sid "echo" :result {"role" "user" "content" query}))
  (let [context-length (:context-length (get cfg "providers" provider) (:context-length cfg 30000))
        rag-instruction (await (vdb-extracts query :profile profile :max-length (/ context-length 2)))
        system-prompt (get-prompt profile prompt-name)
        system-msg {"role" "system" "content" system-prompt}
        rag-usr-msg {"role" "user" "content" rag-instruction}
        saved-usr-msg {"role" "user" "content" query "timestamp" (time) "tool" "vdb"}
        ws-msgs (workspace-messages profile)
        saved-messages (get-chat profile chat)
        [messages dropped] (truncate saved-messages
                                     :space (+ (:max-tokens cfg 600)
                                               (token-count system-prompt)
                                               (token-count ws-msgs)
                                               (token-count rag-instruction))
                                     :provider provider)
        sent-messages [system-msg #* ws-msgs #* messages rag-usr-msg]
        reply (await (stream-reply sid chat provider sent-messages #** kwargs))]
    (.append saved-messages saved-usr-msg)
    (.append saved-messages {"role" "assistant" "content" (extract-output reply) "timestamp" (time)})
    (set-chat saved-messages profile chat)))

(defn :async [rpc] smry 
  [*
   sid
   profile
   chat
   prompt-name
   provider
   [summary_type "summary"]
   [text ""]
   [arxiv False]
   [news False]
   [url False]
   [wikipedia False]
   [youtube False]
   #** kwargs]
  "Context-free summary of a source. See `ws` for usage.
  Note, `kwargs` are passed to summary template, not model."
  (let [system-prompt (get-prompt profile prompt-name)
        system-msg {"role" "system" "content" system-prompt}
        source (cond
                 text "[text removed for length]"
                 arxiv f"arXiv search: {arxiv}"
                 news f"news: {news}"
                 url f"url: {url}"
                 wikipedia f"wikipedia: {wikipedia}"
                 youtube f"YouTube: {youtube}\n{(retrieve.youtube-meta youtube)}")
        text (cond
               text text
               youtube (retrieve.youtube youtube :punctuate (:punctuate cfg False))
               url (retrieve.url url)
               arxiv (retrieve.arxiv arxiv)
               news (retrieve.ddg-news news)
               wikipedia (retrieve.wikipedia wikipedia))
        instruction {"role" "user" "content" (summary summary_type :text text #** kwargs)}
        saved-usr-msg {"role" "user" "content" f"Summarize: {summary_type}\n{source}" "timestamp" (time)}
        saved-messages (get-chat profile chat)
        sent-messages [system-msg instruction]]
    (await (client-rpc sid "echo" :result saved-usr-msg))
    (let [reply (await (stream-reply sid chat provider sent-messages))]
      (.append saved-messages saved-usr-msg)
      (.append saved-messages {"role" "assistant" "content" (.strip reply) "timestamp" (time)})
      (set-chat saved-messages profile chat))))

