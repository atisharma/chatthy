"
Manage the client's shared state.
"

(import hyjinx [config])

(import asyncio [Queue])


;; TODO
;; - better chat-id location
;; - better app location

(setv cfg (config "client.toml"))
(setv chat-id (:chat-id cfg "default"))
(setv username (:username cfg "Anon"))
(setv provider (:provider cfg None))

;; Queues
;; -----------------------------------------------------------------------------

(setv input-queue (Queue))

