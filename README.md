# chatthy

An asynchronous terminal server/multiple-client setup for conducting and managing chats with LLMs.


### network architecture

- [x] client/server RPC-type architecture
- [x] message signing


### chat management

- [x] basic chat persistence and management
- [x] set, switch to saved system prompts (personalities)
- [ ] profiles? (username x personalities -> sets of chats)
- [x] chat truncation to token length
- [ ] rename chat


### functionality

- [ ] summaries (see llama-farm, unslop templates)
- [ ] inject from sources (see llama-farm)
- [ ] templates for standard instruction requests (hyjinx? llm-utils?)
- [ ] integrate with other things like RAG / vdb
- [ ] tools (merge from llama-farm)
- [ ] iterative workflows (refer to llama-farm)


### client interface

- [x] can switch between Anthropic, OpenAI, tabbyAPI providers and models
- [x] streaming
- [x] syntax highlighting
- [x] decent REPL
- [x] REPL command mode
- [.] inject from file
- [ ] cut/copy from output (clipman)
- [ ] image sending
- [ ] client-side chat/message editing
- [ ] latex rendering (this is tricky in the context of prompt-toolkit, but see flatlatex)


### misc

- [ ] use proper config dir (group?)
- [ ] dump default conf if missing



## intended functionality by package


### unallocated

audio streaming ?


### LLM-utils (all depend on LLM)

summaries and text reduction (llama-farm.summaries) 
workflows (tree of instruction templates)
instruction templates (chasm_engine.instructions)
RAG templates
tasks
tools


### hyjinx

streaming APIs (hyjinx.llm)
zmq client/server abstraction (hyjinx.wire)
sources (textfiles, url, arxiv, wikipedia, youtube) (llama-farm.sources, unslop.web) !


### vdb (no llm required)

vdb
split
embeddings


### chatthy (rubber-duckhy?)

REPL interface
chat persistence, management

