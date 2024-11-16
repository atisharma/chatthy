# chatthy

An asynchronous terminal server/multiple-client setup for conducting and managing chats with LLMs.


### network architecture

- [x] client/server RPC-type architecture
- [x] message signing
- [ ] ensure chunk ordering


### chat management

- [x] basic chat persistence and management
- [x] set, switch to saved system prompts (personalities)
- [x] chat truncation to token length
- [x] rename chat
- [x] profiles (profile x personalities -> sets of chats)


### context workspace

- [x] context workspace (load/drop files)
- [x] client inject from file
- [x] client inject from other sources, e.g. youtube (trag)
- [x] templates for standard instruction requests (trag)
- [x] context workspace - bench/suspend files (hidden by filename)


### tool / agentic use

- [ ] (auto) tools (evolve from llama-farm -> trag)
- [ ] server use vdb context at LLM will (tool)
- [ ] iterative workflows (refer to llama-farm)
- [ ] tool chains


### RAG

- [x] summaries and standard client instructions (trag)
- [x] server use vdb context on request
- [ ] consider best method of pdf conversion / ingestion
- [ ] full arxiv paper ingestion (fvdb)
- [ ] vdb result reranking with context, and winnowing


### client interface

- [x] can switch between Anthropic, OpenAI, tabbyAPI providers and models
- [x] streaming
- [x] syntax highlighting
- [x] decent REPL
- [x] REPL command mode
- [x] cut/copy from output
- [x] client-side prompt editing
- [ ] client-side chat/message editing (how? temporarily set the input field history?)
- [ ] latex rendering (this is tricky in the context of prompt-toolkit, but see flatlatex, pylatexenc).
- [ ] generation cancellation


### miscellaneous / extensions

- [ ] design with multimodal models in mind
- [ ] image sending and use
- [x] use proper config dir (group?)
- [ ] dump default conf if missing


## intended functionality by package


### unallocated

audio streaming ?
workflows (tree of instruction templates)
tasks

arXiv paper -> latex / md
pdf paper -> latex / md

