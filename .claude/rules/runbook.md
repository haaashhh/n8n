---
description: Operating the stack — Docker, Ollama service, backups, pgvector, SearXNG.
paths:
  - "**/*.sh"
  - "**/docker*"
  - "**/compose*"
  - "**/*.plist"
---

# Runbook

- **Start/stop:** `docker compose up -d` / `docker compose down` from `~/Desktop/Projects/n8nauto`. **Update:** bump the pinned image tag, then `docker compose pull && docker compose up -d`.
- **Services:** n8n (`127.0.0.1:5678`), postgres (`pgvector/pgvector:pg16`, internal-only), searxng (`127.0.0.1:8080`). **Ollama** = launchd `com.user.ollama-serve` (`127.0.0.1:11434`, models on the external SSD, waits for the mount). **Backups** = launchd `com.user.n8n-backup` (weekly → `~/Library/Application Support/n8n-local/backups`; `./backup.sh` also mirrors to the SSD).
- **Ollama restart:** `launchctl kickstart -k gui/$(id -u)/com.user.ollama-serve`. Health: `curl localhost:11434/api/tags`, `ollama ps`.
- **pgvector:** Postgres has pgvector 0.8.2; the vector store is the **`rag`** database. Connect from the n8n PGVector node using host `postgres`, database `rag`.
- **Disk:** internal is tight — keep models external; reclaim with `docker image prune` / `docker builder prune`; cap Docker Desktop memory (~8 GB) + disk image in Settings → Resources.
- Never put the Postgres volume on the USB SSD. Eject the SSD cleanly (it holds the Ollama models).
