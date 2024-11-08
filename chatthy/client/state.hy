"
Manage the client's shared state.
"

(import hyjinx [config])

(import asyncio [Queue])
(import platformdirs [user-config-dir])


;; TODO
;; use config dir
;; (file-exists (Path (user-config-dir "chatthy") "client.toml"))

;; Global config options
;; -----------------------------------------------------------------------------

(setv cfg (config "client.toml"))
(setv chat (:chat cfg "default"))
(setv profile (:profile cfg "Anon"))
(setv provider (:provider cfg None))
(setv prompt-name (:prompt cfg "default"))

;; Global vars
;; -----------------------------------------------------------------------------

(setv token-count 0)
(setv workspace-count 0)

;; Queues
;; -----------------------------------------------------------------------------

(setv input-queue (Queue))

