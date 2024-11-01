"
Manage the client's shared state.
"

(import hyjinx [config])

(import asyncio [Queue])
(import platformdirs [user-config-dir])


;; TODO
;; use config dir
;; (file-exists (Path (user-config-dir "chatthy") "client.toml"))

(setv cfg (config "client.toml"))
(setv chat-id (:chat-id cfg "default"))
(setv username (:username cfg "Anon"))
(setv provider (:provider cfg None))

;; Queues
;; -----------------------------------------------------------------------------

(setv input-queue (Queue))

