# n8n Automation Stack — local, $0 runtime

Self-hosted automation for a solo software agency, running entirely on a Mac:
**Ollama** (local LLMs) + **n8n** (Docker Compose + Postgres/pgvector) + **SearXNG** (private web search),
built and operated with **Claude Code** through the [n8n-MCP](https://github.com/czlonkowski/n8n-mcp) server.
No cloud, no per-token API cost — all inference is local.

- 📖 **Full guide:** [GUIDE.md](GUIDE.md) — using Claude Code, n8n, the folder system, and best practices.
- 🤖 **Agent brief:** [CLAUDE.md](CLAUDE.md) — the short context Claude Code loads each session.

## Quick start

```bash
cp .env.example .env                                    # fill in secrets (openssl rand -hex 32)
cp searxng/settings.yml.example searxng/settings.yml    # set a unique secret_key
docker compose up -d                                    # n8n -> http://localhost:5678
```

Ollama runs as a launchd service with model weights on an external SSD (kept out of the repo). See **GUIDE.md** for the full setup, including the model-routing rule and the optional Claude-Code bridge.

## Layout

| Path | What |
|---|---|
| `compose.yaml` | the stack (n8n + Postgres/pgvector + SearXNG), pinned & localhost-only |
| `.env.example` · `searxng/settings.yml.example` | templates (the real files are git-ignored) |
| `backup.sh` | backup wrapper (DB dump + n8n volume + key → internal, mirrors to SSD) |
| `.claude/skills/` | Claude Code project skills (`/n8n-build`, `/n8n-audit`, `/stack-up`, …) |
| `.claude/rules/` | path-scoped domain docs (workflows / integrations / runbook) |
| `GUIDE.md` · `CLAUDE.md` | documentation |

## Security

Every service binds to `127.0.0.1`. **Never commit `.env`** (it holds `N8N_ENCRYPTION_KEY` + the Postgres password) — it is git-ignored. The n8n encryption key is **irrecoverable if lost**; keep a copy in a password manager.

---
🤖 Built with [Claude Code](https://claude.com/claude-code).
