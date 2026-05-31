# n8n Automation Stack — Operator Guide

Local, cost-free automation for a solo software agency. All LLM inference runs **locally via Ollama** (no Anthropic/OpenAI API key in the runtime — $0 per execution). Claude Code (this tool) builds/edits the n8n workflows via the **n8n-MCP** server.

## Topology
| Service | URL | Notes |
|---|---|---|
| n8n editor | http://localhost:5678 | bound to 127.0.0.1 only (never LAN) |
| n8n API | http://localhost:5678/api/v1 | used by n8n-MCP |
| Ollama (host) | http://localhost:11434 | launchd service, binds 127.0.0.1 (loopback only — not on the LAN) |
| Ollama (from n8n container) | http://host.docker.internal:11434 | use this in the n8n Ollama credential |
| Postgres | internal Docker network only | `pgvector/pgvector:pg16`, not published to host. Vector store = **`rag`** database (pgvector 0.8.2) |
| SearXNG | localhost:8080 (host) / http://searxng:8080 (container) | local private web search; JSON API for workflows |
| Claude bridge (opt-in) | http://host.docker.internal:8787 | host service to run headless `claude -p`; off by default (see GUIDE.md) |
| LM Studio (if running) | http://localhost:1234/v1 | separate; **unload its model before running the big Ollama model** |

## Models (stored on the external SSD via `OLLAMA_MODELS`)
- **`gpt-oss:20b`** — DEFAULT main (~16 GB RAM): drafting, reasoning, tool-calling. Safe on 38 GB.
- **`qwen3.6:35b-a3b`** — PREMIUM main (~26–30 GB RAM): highest quality. Use only when LM Studio is closed and Docker is light, or it will swap.
- **`qwen3:8b`** — FAST (~6.5 GB): classification, field extraction, routing.
- **`qwen3-embedding:0.6b`** — embeddings for RAG (vector store ready: Postgres `rag` DB + pgvector).

### Model-routing rule (apply in every AI workflow)
Fast/cheap (classify, extract, route, tag) → **qwen3:8b**.
Quality (client emails, proposals, ad-report summaries, multi-point reasoning) → **gpt-oss:20b** by default; **qwen3.6:35b-a3b** when max quality is worth the RAM.

## Secrets
- Live in `./.env` (chmod 600, git-ignored). Never commit. `.env.example` is the committable template.
- `N8N_ENCRYPTION_KEY` is the master secret — also stored in the password manager. **Never change it** after first run or all saved n8n credentials become undecryptable. Carry the *same* key to any new host/restore.

## Working rules for Claude Code
- **Always validate node configs and the full workflow with n8n-mcp tools BEFORE creating/activating** a workflow (use the validate tools, then create/update).
- Prefer the Ollama credential `http://host.docker.internal:11434` in AI nodes.
- Don't expose port 5678 or Ollama to the LAN; this is a localhost-only box for now.
- When pulling new models, they download to the external SSD automatically (server-side `OLLAMA_MODELS`).

## Common commands
```bash
# Stack
docker compose up -d            # start n8n + Postgres
docker compose ps               # status
docker compose logs -f n8n      # follow n8n logs
docker compose down             # stop (data persists in volumes)
docker compose pull && docker compose up -d   # update n8n (after bumping the pinned tag)

# Ollama (launchd service: com.user.ollama-serve)
ollama list                     # installed models
ollama ps                       # resident models + unload timer
curl localhost:11434/api/tags   # server reachable?
launchctl kickstart -k gui/$(id -u)/com.user.ollama-serve   # restart Ollama

# Backup
#   Weekly launchd job (com.user.n8n-backup) writes to internal:
#     ~/Library/Application Support/n8n-local/backups   (background agents can't write the SSD: macOS TCC)
#   Run ./backup.sh yourself to ALSO mirror the latest set to the external SSD. Keep an encrypted OFFSITE copy.
./backup.sh
```

## Gotchas baked into this setup
- Ollama binds `127.0.0.1` (loopback only). The n8n container still reaches it via `host.docker.internal:11434` because Docker Desktop forwards that to the host loopback (verified). Do NOT switch to `0.0.0.0` — that exposes an unauthenticated model API to the whole LAN.
- n8n basic-auth env vars are dead in 2.x → auth is the owner account at first run.
- `N8N_SECURE_COOKIE=false` is required to log in over http://localhost.
- Models live on the external "G-DRIVE mobile SSD R-Series"; Ollama waits for it to mount. Postgres stays on an internal Docker volume (never the USB drive).
- Internal disk is tight (~10–14 GiB free; Docker's VM image lives here). Keep models external, prune Docker periodically, and consider capping the Docker Desktop disk image (Settings → Resources).
- Web search inside workflows: hit SearXNG (`http://searxng:8080/search?q=...&format=json`) deterministically, then feed results to the LLM — don't rely on the Ollama tools-agent (flaky in n8n).

## Project layout
- `compose.yaml` · `.env` (chmod 600, git-ignored) · `.env.example` · `backup.sh` (wrapper) · `searxng/settings.yml`
- `.claude/skills/` — project skills: `/n8n-build`, `/n8n-audit`, `/stack-up`, `/n8n-backup`, `/n8n-export`
- `.claude/rules/` — path-scoped domain docs (`workflows.md`, `integrations.md`, `runbook.md`) that load lazily when relevant files are touched
- User-scope skills (`~/.claude/skills/`): `/client-proposal`, `ollama-route` (background reference)
- **`GUIDE.md`** — full how-to (Claude, Claude Code, n8n, folder system, best practices)
