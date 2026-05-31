---
name: stack-up
description: Bring the local n8n stack up and health-check it (Docker Compose + Ollama + n8n API). Use when asked to start, boot, or health-check the stack, or when n8n/Ollama seems down.
disable-model-invocation: true
allowed-tools: Bash(docker compose *) Bash(docker *) Bash(ollama *) Bash(curl *) Bash(launchctl *)
---

# Stack up + health check

## Live state (gathered before you read this)
- Docker containers: !`docker compose ps 2>/dev/null || echo "compose not running / wrong dir"`
- Ollama reachable: !`curl -s -m 3 localhost:11434/api/tags >/dev/null && echo "OK 11434" || echo "Ollama DOWN"`
- Ollama resident models: !`ollama ps 2>/dev/null || echo "ollama CLI unavailable"`
- n8n API: !`curl -s -m 3 -o /dev/null -w "%{http_code}" http://localhost:5678/healthz || echo "no response"`
- SearXNG: !`curl -s -m 3 -o /dev/null -w "%{http_code}" "http://localhost:8080/search?q=test&format=json" || echo "no response"`

## Bring-up sequence
1. If Ollama is DOWN: `launchctl kickstart -k gui/$(id -u)/com.user.ollama-serve` and confirm the external SSD (OLLAMA_MODELS) is mounted — Ollama waits for it.
2. If containers are not up: `docker compose up -d` (must be run from ~/Desktop/Projects/n8nauto). Postgres has a healthcheck; n8n + searxng wait on it.
3. Re-check: `docker compose ps`, then n8n /healthz and the editor at http://localhost:5678.
4. If LM Studio (:1234) is running the big model and you intend to use qwen3.6:35b-a3b, tell me to unload it first — RAM will swap otherwise.

Report final status of all services (Docker, Ollama, n8n, SearXNG) and the URL to open. Do not run `docker compose down` here.
