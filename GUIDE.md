# Using Your Local Automation Stack — Complete Guide

A practical, re-readable manual for the stack at `~/Desktop/Projects/n8nauto`: **Ollama** (local LLMs) + **n8n** (workflow automation) + **Claude Code** (builds/operates it) + **SearXNG** (web search) + **pgvector** (RAG). Everything runs locally; runtime cost is **$0**.

> Quick orientation: `CLAUDE.md` is the short always-loaded brief for Claude. **This file is for you, the human.**

---

## 1. The mental model

Three layers, each with a job:

| Layer | What it is | Role |
|---|---|---|
| **Claude Code** (this tool, your Max subscription) | An agent in your terminal/IDE | **Builds & operates** — writes workflows, edits configs, runs ops, debugs. You talk to it. |
| **Ollama** (local models) | gpt-oss:20b, qwen3.6:35b-a3b, qwen3:8b, embeddings | **The runtime brain** — the cheap, private, $0 inference inside your workflows. |
| **n8n** (Docker) | Visual workflow engine + Postgres | **The execution engine** — runs automations on triggers/schedules, talks to 400+ apps. |

Supporting cast: **SearXNG** (private web search), **Postgres+pgvector** (the `rag` database for embeddings), **backups** (launchd, weekly), and an optional **bridge** so n8n can call Claude Code.

**Golden rule of routing:** cheap/bulk work → Ollama ($0). Only the few genuinely hard reasoning steps → Claude (your subscription, via Claude Code or the optional bridge).

---

## 2. Daily operations

```bash
cd ~/Desktop/Projects/n8nauto

docker compose up -d        # start n8n + Postgres + SearXNG
docker compose ps           # status (all should be Up; postgres healthy)
docker compose logs -f n8n  # follow logs (Ctrl+C to stop)
docker compose down         # stop everything (data persists in volumes)
```

- **Ollama** runs automatically (launchd, starts at login, waits for the external SSD). Restart it with `launchctl kickstart -k gui/$(id -u)/com.user.ollama-serve`.
- **Open n8n:** http://localhost:5678 (log in with your owner account).
- **The external SSD must be plugged in** — it holds the models. Eject it cleanly before unplugging.
- Or just tell Claude Code: **“/stack-up”** — it checks and boots everything.

**Endpoints**

| Thing | URL |
|---|---|
| n8n editor | http://localhost:5678 |
| Ollama (host) | http://localhost:11434 |
| Ollama (from inside n8n) | http://host.docker.internal:11434 |
| SearXNG (from inside n8n) | http://searxng:8080 |
| Postgres `rag` DB | host `postgres`, db `rag` (Docker network) |

---

## 3. How to use Claude Code

**Sessions & MCP.** Claude Code loads MCP servers (like `n8n-mcp`) and first-time skill directories **at session start**. So: after adding an MCP server or creating `.claude/skills/` for the first time, **start a new session** to pick them up. Editing an existing skill/rule is live (no restart).

**The n8n-mcp tools** (available after restart) let Claude build/inspect workflows: `search_nodes`, `get_node`, `validate_node`, `validate_workflow`, `n8n_create_workflow`, `n8n_update_partial_workflow`, `n8n_list_workflows`, `n8n_get_workflow`, `n8n_autofix_workflow`, `n8n_test_workflow`, `n8n_executions`, `n8n_audit_instance`. You rarely call these directly — you describe what you want and Claude uses them.

**Skills** (`/name`) — reusable, parameterized prompts. Yours:
- Project (this repo): `/n8n-build <desc>`, `/n8n-audit`, `/stack-up`, `/n8n-backup`, `/n8n-export`
- User (everywhere): `/client-proposal <client/scope>`, plus `ollama-route` (background reference Claude applies automatically)
- Manage: add = make `.claude/skills/<name>/SKILL.md`; change = edit it (live); remove = delete the folder. See §6.

**Rules** (`.claude/rules/*.md`) — domain knowledge that loads **only when you touch matching files** (keeps context lean). Yours: `workflows.md`, `integrations.md`, `runbook.md`.

**Memory.** Claude auto-saves learnings to `~/.claude/projects/<project>/memory/MEMORY.md` (run `/memory` to view). Your stack facts and preferences are already there, so new sessions have context.

**Useful built-in commands:** `/code-review`, `/security-review`, `/simplify`, `/verify`, `/run`, `/init`, `/debug`, `deep-research`, `/context` (see token usage), `/doctor` (health), `/plugin` (marketplaces). Don't recreate these as skills.

**Permissions.** Claude asks before risky actions. To reduce prompts for trusted commands, add allow-rules in `.claude/settings.json` (or run `/fewer-permission-prompts`). The safety classifier can hard-block genuinely dangerous things (it blocked the auto-install of the Claude bridge — see §8).

**Plan first for big tasks.** Ask Claude to research + plan before executing anything substantial; have it verify results. (That's how this stack was built.)

---

## 4. How to use “Claude” (which front-end, and the rules)

| Surface | Use it for | Billing |
|---|---|---|
| **Claude Code** (CLI/IDE) | Building & operating this project, coding, ops | Your **Max subscription** ✓ |
| **claude.ai** (web/app) | General chat, research, brainstorming | Max subscription ✓ |
| **Anthropic API key** | Third-party apps / raw API calls | **Billed per token** — avoid in the runtime |

**The line that matters:** using your **Max subscription** through Claude Code (or the bridge in §8) for **your own** automation is fine. Putting an **API key into n8n’s AI nodes** would bill you per token — so all *runtime* inference stays on **Ollama** ($0). Don’t route third-party traffic through your subscription credentials.

---

## 5. How to use n8n

### Build a workflow (two ways)
1. **With Claude Code (recommended):** `/n8n-build send a weekly ad report email`. Claude runs the validate-first loop and creates it **inactive** for your review.
2. **Manually in the UI:** drag nodes at http://localhost:5678. Use Claude Code to debug/validate (`/n8n-audit`).

**Validate-first loop** (what `/n8n-build` does): search nodes → read docs → validate each node → validate the whole workflow → create → server-validate → autofix → leave inactive → you review/activate.

### AI nodes & model routing
- Add an **Ollama** credential with base URL `http://host.docker.internal:11434` (already created: “Ollama (local)”).
- Route by job: **fast** = `qwen3:8b`; **quality** = `gpt-oss:20b` (default); **max** = `qwen3.6:35b-a3b` (only with LM Studio closed); **embeddings** = `qwen3-embedding:0.6b`.

### Web search in a workflow
Use the **deterministic** pattern (the Ollama tools-agent is flaky in n8n):
`HTTP Request → http://searxng:8080/search?q={{query}}&format=json → keep top 5 results → Ollama node ("answer using only these results, cite URLs")`.

### RAG (grounded drafting over your own docs)
The `rag` Postgres database has **pgvector 0.8.2**. Pattern: embed your docs with `qwen3-embedding:0.6b` → store in `rag` via n8n’s **Postgres PGVector** node (host `postgres`, db `rag`) → on a query, embed it, retrieve top matches, feed to `gpt-oss:20b`. Great for proposal/email drafting grounded in your real past work.

### Credentials & the OAuth-on-localhost catch ⚠️
- ~400+ native nodes; anything else via the **HTTP Request** node; community nodes installable (self-hosted).
- **OAuth nodes** (Gmail, Google*, HubSpot-OAuth, Salesforce, Dropbox, QuickBooks) need a **public HTTPS callback** — `localhost` is rejected. Either:
  - **Prefer token/API-key/Service-Account auth** (Notion token, Airtable PAT, Google **Service Account**, Slack/Telegram/Discord bot tokens, SendGrid/Stripe keys, GitHub/GitLab PAT, Jira/Linear tokens, SMTP/IMAP) — no callback needed, fully local. ✅
  - **Or** stand up a Cloudflare Tunnel + your domain for the one-time OAuth grant, then go back to `localhost` (refresh token persists).
- **Meta/Facebook Ads:** no turnkey node → HTTP Request to the Marketing API with a long-lived token.
- **Inbound triggers** (Stripe/Telegram/GitHub webhooks) need a reachable URL — use the tunnel, or polling triggers.

### n8n as an MCP server (advanced)
The **MCP Server Trigger** node exposes a finished workflow **as a tool** Claude can invoke (e.g. “pull-ad-report”). Different from `n8n-mcp` (which lets Claude *build* workflows). Protect with a Bearer token; needs a reachable `/mcp/<uuid>` URL.

---

## 6. The folder system to adopt

```
~/Desktop/Projects/n8nauto/
├── compose.yaml              # the stack definition (pinned images, localhost-only)
├── .env                      # secrets (chmod 600, GIT-IGNORED — never commit)
├── .env.example              # safe template (committable)
├── .gitignore                # ignores .env, backups, dumps
├── backup.sh                 # wrapper → runs the real backup + SSD mirror
├── CLAUDE.md                 # short brief Claude reads every session
├── GUIDE.md                  # this file (for you)
├── searxng/settings.yml      # SearXNG config
├── workflows/                # exported workflow JSON (create via /n8n-export) — git-tracked
└── .claude/
    ├── skills/               # project skills (/n8n-build, /n8n-audit, /stack-up, /n8n-backup, /n8n-export)
    ├── rules/                # path-scoped docs (workflows / integrations / runbook) — load lazily
    └── settings.json         # (optional) permission allow-rules, hooks
```
Outside the repo:
```
~/.claude/skills/             # your personal skills (/client-proposal, ollama-route)
~/Library/Application Support/n8n-local/
    ├── backups/              # weekly internal backups
    └── claude-bridge/        # the optional n8n→Claude bridge (server.js, token.txt)
~/Library/LaunchAgents/       # com.user.ollama-serve, com.user.n8n-backup (+ claude-bridge if enabled)
/Volumes/G-DRIVE…/ollama/models   # the LLM weights (external SSD)
/Volumes/G-DRIVE…/n8n-backups/    # SSD backup mirror
```

**Principles:** root `CLAUDE.md` stays short (always loaded); deep knowledge goes in `.claude/rules/` (lazy); repeatable actions become **skills**; secrets live only in `.env` (600) and your password manager; everything else is git-trackable.

### Put it under git (recommended)
```bash
cd ~/Desktop/Projects/n8nauto && git init && git add -A && git commit -m "Local n8n + Ollama automation stack"
```
`.env` is already git-ignored. Use `/n8n-export` to snapshot workflows into `workflows/` so they’re versioned too.

---

## 7. Best practices (the short list)

- **Secrets:** never commit `.env`; keep `N8N_ENCRYPTION_KEY` in your password manager; if you ever migrate, carry the *same* key or all credentials break.
- **RAM discipline (38 GB):** default to `gpt-oss:20b`. Before using `qwen3.6:35b-a3b`, **unload LM Studio’s model** and keep Docker light, or it swaps.
- **Disk:** internal is tight — models stay external; run `docker image prune` / `docker builder prune` occasionally; cap Docker Desktop memory (~8 GB) + disk in Settings → Resources.
- **Backups:** automatic weekly (internal). Run `/n8n-backup` (or `./backup.sh`) before big changes to also mirror to the SSD; add one **encrypted offsite** copy; test a restore occasionally.
- **Network:** keep n8n (5678), Ollama (11434), SearXNG (8080) **bound to 127.0.0.1**. Optionally turn on the macOS firewall. Only expose via Cloudflare Tunnel when you deliberately need webhooks/OAuth.
- **Workflows:** always validate before activating; leave new ones inactive until reviewed; add error handling on HTTP/DB nodes; export to git.
- **Updating n8n:** bump the pinned tag in `compose.yaml`, then `docker compose pull && docker compose up -d`. Don’t use `:latest`. Never bump the Postgres *major* in place.
- **Lean tooling:** resist installing mega skill/plugin packs — they bloat context. Add a skill only when you repeat a task.

---

## 8. The optional Claude-Code → n8n bridge

**What it is:** a tiny host service (`~/Library/Application Support/n8n-local/claude-bridge/server.js`) that runs **headless `claude -p`** (your Max subscription) and that n8n can call via `http://host.docker.internal:8787`. This lets a workflow escalate a hard step (draft a nuanced proposal, review client code, debug) to Claude while everything else stays on Ollama.

**Why it’s NOT auto-installed:** an always-on endpoint that runs an agent with tools is a powerful local RCE surface — the safety classifier (correctly) blocked auto-installing it. Enable it **deliberately**, with these guardrails (already in `server.js`):
- binds **127.0.0.1** only; requires a **Bearer token**; runs claude in a **scoped, empty workspace**;
- **default tools are read-only** (`Read Glob Grep WebSearch WebFetch`); never `--dangerously-skip-permissions`; never `--bare` (so it uses your subscription, not an API key).

**To turn it on** (your call — pick one):
- **Read-only (safest):** keep the default tool list; the bridge can research/summarize/draft but can’t run Bash or write files. Recommended starting point.
- **Full-power:** allow callers to request `Bash`/`Write`/`Edit` for code tasks — only if you understand it’s effectively local code execution on demand.

Then load it as a launchd service (the command is ready in our chat / I can re-run it once you approve), test with `curl http://127.0.0.1:8787/health`, and in n8n use an **HTTP Request** node → `POST http://host.docker.internal:8787/query` with header `Authorization: Bearer <token from token.txt>` and body `{"prompt":"…","allowedTools":"Read WebSearch"}`. Watch the **billing/quota** for headless usage — review your subscription’s agent/headless limits before high volume.

---

## 9. Ambitious next steps (when you’re ready)

1. **Build the 6 core workflows** — lead qualification → client onboarding → invoice follow-ups → ad reporting → proposal generation → content. (Start: `/n8n-build`.)
2. **RAG over your past proposals/projects** (pgvector is ready) → grounded drafting.
3. **n8n-as-MCP-server** → trigger finished pipelines by chatting with Claude.
4. **Hybrid escalation** via the bridge → cheap on Ollama, hard steps on Claude.
5. **Self-healing** → nightly `/n8n-audit` + `n8n_autofix_workflow` on failures.

---

## 10. Cheat sheet

```bash
# Stack
cd ~/Desktop/Projects/n8nauto && docker compose up -d        # start
docker compose ps                                            # status
docker compose down                                          # stop
docker compose pull && docker compose up -d                  # update (after bumping tag)

# Ollama
ollama list ; ollama ps                                      # models / resident
launchctl kickstart -k gui/$(id -u)/com.user.ollama-serve    # restart Ollama

# Search / RAG checks
curl 'http://localhost:8080/search?q=test&format=json'       # SearXNG
docker exec n8n-local-postgres-1 psql -U n8n -d rag -c '\dx' # pgvector present

# Backup
./backup.sh                                                  # internal + SSD mirror

# Claude Code
/stack-up  /n8n-build <desc>  /n8n-audit  /n8n-export  /n8n-backup  /client-proposal <scope>
/context   /doctor   /memory   /code-review   /security-review
```

| Service | Port (localhost) | Managed by |
|---|---|---|
| n8n | 5678 | docker compose |
| Ollama | 11434 | launchd `com.user.ollama-serve` |
| SearXNG | 8080 | docker compose |
| Postgres | (internal) | docker compose |
| Claude bridge (opt-in) | 8787 | launchd `com.user.claude-bridge` |
| Backups (weekly) | — | launchd `com.user.n8n-backup` |
