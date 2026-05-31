---
name: n8n-build
description: Build or modify an n8n workflow on the local stack using the n8n-MCP validate-first loop. Use when asked to create, design, or edit an n8n workflow, automation, or AI pipeline.
argument-hint: [what the workflow should do]
allowed-tools: mcp__n8n-mcp__* Read
---

# Build an n8n workflow (validate-first)

Target: local n8n at http://localhost:5678 (Postgres-backed, v2.23.1). Never expose to LAN.

## Loop — do NOT skip validation
1. `search_nodes` to find the right nodes for: $ARGUMENTS
2. `get_node` for each chosen node to read its exact operations/params.
3. `validate_node` on every node config BEFORE assembling.
4. Assemble the workflow JSON, then `validate_workflow` (this also checks connections + expressions).
5. Only when validation is clean: `n8n_create_workflow` (new) or `n8n_update_partial_workflow` (edit).
6. `n8n_validate_workflow` against the live instance; if errors, `n8n_autofix_workflow`, then re-validate.
7. Do NOT auto-activate. Leave inactive; tell me to review in the UI first. Use `n8n_test_workflow` for a dry run if a webhook/trigger exists.

## AI nodes — apply the model-routing rule
- Ollama credential URL is **http://host.docker.internal:11434** (the container reaches host Ollama via this; the host binds 127.0.0.1 only — never switch Ollama to 0.0.0.0).
- Fast / cheap (classify, extract, route, tag) -> **qwen3:8b**
- Quality (client emails, proposals, report summaries, multi-step reasoning) -> **gpt-oss:20b** (default); **qwen3.6:35b-a3b** only when LM Studio is closed and Docker is light.
- Embeddings -> **qwen3-embedding:0.6b** (vector store: Postgres `rag` database, pgvector).
- Web search inside a workflow: call SearXNG at **http://searxng:8080/search?q=...&format=json** (deterministic search-then-LLM beats the flaky Ollama tools-agent).

## Rules
- Never invent node params — always confirm via `get_node`.
- Never commit or echo secrets from `.env` (encryption key, Postgres creds).
- After creating, report the workflow ID and remind me it is inactive.
