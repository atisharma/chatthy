"
Manage the client's shared state.
"

(import hyjinx [config])

(import asyncio [Queue])
(import pathlib [Path])
(import platformdirs [user-config-dir])


;; * Global config options
;; -----------------------------------------------------------------------------

;; look for ~/.config/chatthy/client.toml
;; or default to $pwd/client.toml
(let [p (Path (user-config-dir "chatthy") "client.toml")]
  (if (.exists p)
    (setv config-file (str p))
    (setv config-file "client.toml")))

(setv cfg (config config-file))
(setv chat (:chat cfg "default"))
(setv profile (:profile cfg "Anon"))
(setv provider (:provider cfg None))
(setv prompt-name (:prompt cfg "default"))

(setv server-status {"result" "Connecting ☇"})


;; * Global vars
;; -----------------------------------------------------------------------------

(setv token-count 0)
(setv workspace-count 0)


;; * Queues
;; -----------------------------------------------------------------------------

(setv input-queue (Queue))

