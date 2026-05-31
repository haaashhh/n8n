---
name: research-brief
description: Produce a cited research brief on a topic using local SearXNG search plus local Ollama synthesis, or build the equivalent n8n research workflow. Use when asked to research a topic, compile a briefing, do competitor/market research, fact-check, or build a research automation.
argument-hint: [research question or topic, or "build the research workflow"]
allowed-tools: mcp__n8n-mcp__* Read WebSearch WebFetch
---

# Research brief (local-first, cited) — persona: Mira

Mira's rules apply: rigorous, neutral, every factual claim carries a `[source: URL or title]`; separate Facts / Inference / Unknown; state confidence; never invent a source. Two modes — detect from the request.

## Mode A: do the research now
1. Decompose the question into 3-6 sub-queries.
2. Search: prefer SearXNG `http://searxng:8080/search?q=...&format=json` ($0, local, private). Use WebSearch/WebFetch only when broader/live coverage is needed.
3. For top sources: fetch, extract claims, record the URL + publication date.
4. Synthesize: structure = 2-line summary / Key findings (each cited) / Risks & unknowns / Recommendation + confidence.
5. ADVERSARIALLY verify: re-check each load-bearing claim against its source before asserting; mark anything unverified as Unknown.
6. Return the brief with an inline Sources list.

## Mode B: build the n8n research workflow
Follow the n8n-build validate-first loop (search_nodes -> get_node -> validate_node -> validate_workflow -> create). Do NOT auto-activate.

Chain (real node types):
1. Trigger: `@n8n/n8n-nodes-langchain.chatTrigger` or `n8n-nodes-base.formTrigger` (or `executeWorkflowTrigger` when called by the command center).
2. `n8n-nodes-base.set` — derive 3-6 sub-queries.
3. `n8n-nodes-base.httpRequest` GET SearXNG (`http://searxng:8080/search?q={{query}}&format=json`), one per sub-query.
4. `n8n-nodes-base.splitInBatches` -> per-source fetch/extract.
5. `@n8n/n8n-nodes-langchain.chainLlm` + `@n8n/n8n-nodes-langchain.lmChatOllama` (qwen3:8b) — per-source summarize.
6. `n8n-nodes-base.aggregate` -> `chainLlm` generator (gpt-oss:20b) cited synthesis -> `chainLlm`/`agent` evaluator citation check.
7. Deliver: `n8n-nodes-base.telegram` (send OK on localhost) / `gmail` / Gotenberg PDF via the style-doc render step.

## Model routing
per-source extract/summarize -> qwen3:8b | final synthesis -> gpt-oss:20b (qwen3.6:35b-a3b for deep reasoning when RAM allows) | premium client-facing version -> Claude bridge if ON.

## Setup
SearXNG already runs locally (no key). No external key needed for Mode A unless WebSearch is used. Ollama credential URL `http://host.docker.internal:11434`. After a Mode-B build: report the workflow ID, confirm it is INACTIVE.
