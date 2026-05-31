---
description: How to build n8n workflows on this stack — node patterns, validation, model routing, web search.
paths:
  - "workflows/**"
  - "**/*.workflow.json"
---

# Building n8n workflows

- **Validate-first** via n8n-mcp: `search_nodes` → `get_node` → `validate_node` → `validate_workflow` → `n8n_create_workflow` → `n8n_validate_workflow` → `n8n_autofix_workflow`. Leave new workflows **inactive** for review.
- **AI nodes:** Ollama credential = `http://host.docker.internal:11434`. Routing: fast = `qwen3:8b`, quality = `gpt-oss:20b` (default), max = `qwen3.6:35b-a3b` (only when LM Studio is closed). Embeddings = `qwen3-embedding:0.6b` into the Postgres `rag` database (pgvector 0.8.2).
- **Web search (reliable pattern):** HTTP Request → `http://searxng:8080/search?q=...&format=json` → trim top N results → Ollama node. Avoid the Ollama Tools-Agent (tool-calling is flaky in n8n).
- **Inbound triggers** (Stripe/Telegram/GitHub/MCP Server Trigger…) need a public URL (Cloudflare Tunnel). Polling triggers + API/token nodes work fine on localhost.
- Add error handling on HTTP/DB nodes. Never hardcode `localhost` inside container nodes — use `host.docker.internal` (host services) or the compose service name (e.g. `searxng`, `postgres`).
