# What I Built — Autonomous Build Session

Welcome back. Here's everything I built, tested, and set up while you were away — and the short list of what still needs you.

## 0) First: check your Telegram 📱
Your bot **@beru_myagent_bot ("Beru")** should have several new messages — proof the stack works end-to-end:
- a "connected" test message
- a **Financial News digest** (text)
- a **Research Brief PDF** on gold/markets
- an **Industry Radar** digest (text)
- a **Research Brief PDF** on "AI agents for small businesses"
- a **Client Onboarding packet PDF** (sample: Maria Gomez / Website Relaunch)

All generated 100% locally ($0): SearXNG search → local LLM → (Gotenberg PDF) → Telegram.

## 1) The workflow suite (9 workflows in n8n)

| Workflow | Status | What it does | Trigger | Model · Persona | Tested |
|---|---|---|---|---|---|
| **Industry Radar → Telegram** | 🟢 ON | Weekday digest of AI/n8n/LLM/freelance news | Schedule Mon–Fri 08:00 + webhook `/radar` | qwen3:8b · Mira | ✅ live |
| **Daily Brief → Telegram** | 🟢 ON | Morning brief (headlines now; + Motion tasks/calendar when you add keys) | Schedule 07:30 + webhook `/brief` | qwen3:8b · Cosmo | pattern ✅ |
| **Research Brief → PDF → Telegram** | 🟢 ON | Topic → SearXNG → cited brief → PDF | On-demand `/research?topic=…` | qwen3:8b · Mira | ✅ live |
| **Client Proposal → PDF → Telegram** | 🟢 ON | Scope → drafted proposal → branded PDF | Execute-workflow / `/proposal` (POST) | qwen3:8b · Vera | pattern ✅ |
| **Client Onboarding → PDF → Telegram** | 🟢 ON | New client → welcome packet PDF | `/onboarding?clientName=…&projectName=…` | qwen3:8b · Vera | ✅ live |
| **Invoice → PDF → Telegram** | 🟢 ON | Line items → branded invoice PDF (DE conventions) | Execute-workflow / `/invoice` (POST) | qwen3:8b · Klaus | pattern ✅ |
| **Financial News Digest → Telegram** | ⚪ off | Daily CNBC finance digest (built earlier) | Schedule 08:00 | qwen3:8b | ✅ (earlier) |
| **Telegram Command Center** | ⚪ off | Interactive router: your message → intent → runs the right workflow → replies | Telegram Trigger | qwen3:8b · Cosmo | needs receive ⛔ |
| **RAG — Ingest & Query** | ⚪ off | Ask questions over *your own* docs (pgvector) | webhook `/ask?q=…` | qwen3-embedding + qwen3:8b · Ada | needs setup ⛔ |

"pattern ✅" = built + validated and shares a pattern I tested live (text→Telegram via Radar; template→PDF via Onboarding). To run any of them now: open http://localhost:5678 → the workflow → **Execute Workflow**, or curl its webhook (paths above, e.g. `curl 'http://localhost:5678/webhook/radar'`).

**Model note (important):** I defaulted every workflow to **qwen3:8b** (thinking off). I tested `gpt-oss:20b` and it **cold-loads too slowly on this box (>300 s → times out)**. qwen3:8b is the reliable workhorse (~1–2.5 min cold, fast when warm). Upgrade any single step to `gpt-oss:20b` for higher quality once it's warm/RAM is free — just change the `model` field in that workflow's "Build Prompt" node.

## 2) Your agents have personalities 🎭
Six personas, defined in `docs/personas.md` (with ready-to-paste system prompts + an optional Postgres `personas` table) **and** as Claude Code subagents in `.claude/agents/`:
- **Vera** — client concierge (onboarding, proposals, warm client comms)
- **Klaus** — finance (invoices, dunning; precise, firm)
- **Mira** — research analyst (rigorous, cites sources)
- **Cosmo** — chief-of-staff (daily brief + the Telegram router)
- **Pixel** — content/marketing voice
- **Ada** — ops/engineer (RAG, error triage; terse, technical)

Each workflow's LLM step uses its persona's voice. In Claude Code you can also invoke them as subagents (`@mira-research-analyst`, etc.).

## 3) Skills (Claude Code) — expanded
The short forms were a starting point; I added 6 full skills (in `.claude/skills/`): **`/style-doc`** (content → branded PDF-ready HTML), **`/research-brief`**, **`/daily-brief`**, **`/onboard-client`**, **`/client-invoice`** (DE invoicing, gap-free numbering), **`/draft-email`** — on top of the existing `/n8n-build`, `/n8n-audit`, `/stack-up`, `/n8n-backup`, `/n8n-export`, `/client-proposal`.

## 4) Document engine 🧾
Added **Gotenberg** (local HTML→PDF, in `compose.yaml`) + branded **HTML templates** in `templates/` (invoice, proposal, onboarding). The doc pipeline (proven live): draft (local LLM) → fill template / style → Gotenberg PDF → Telegram/email. **Claude styling** is wired as an *optional* upgrade — see §6.

## 5) Motion — the honest verdict
You wanted Motion to draft documents. **Its API can't** — Motion's API is **tasks / projects / calendar only**; AI Docs/Notetaker are UI-only, with no document endpoint. So drafting is done by the local LLM (+ optional Claude) → Gotenberg PDF, which is better and controllable anyway. **Motion's right role = the task & auto-scheduling layer** (create follow-up tasks after sending an invoice/proposal; feed the Daily Brief your task list). It needs a **paid plan ($19/mo Pro AI)** for the API key. Integration = HTTP Request node with an `X-API-Key` header (no native node exists). Recipes are in `docs/design/motion.md`.

## 6) Claude bridge — a one-command opt-in
I built a hardened, **text-only** Claude bridge (host service that styles/drafts via your Max subscription, $0 local RAM). A safety guardrail blocks me from auto-installing an always-on service that runs Claude, so **you enable it** when you want premium Claude styling:
```bash
BR="$HOME/Library/Application Support/n8n-local/claude-bridge"
openssl rand -hex 24 > "$BR/token.txt" && chmod 600 "$BR/token.txt"
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.claude-bridge.plist
launchctl kickstart -k gui/$(id -u)/com.user.claude-bridge
sleep 2 && curl -s http://127.0.0.1:8787/health && echo "  token: $(cat "$BR/token.txt")"
```
Until then, styling uses `gpt-oss:20b`/`qwen3:8b` (works fine).

## 7) What still needs YOU
1. **Motion API key** (paid plan) → paste it; I'll wire the task/scheduling steps + Daily Brief task list.
2. **Email credential** (Gmail App Password or SendGrid) → unlocks emailing proposals/invoices/onboarding (currently they deliver via Telegram).
3. **Telegram receive** for the **Command Center**: install the `n8n-nodes-telegram-polling` community node (Settings → Community Nodes), *or* set up a Cloudflare Tunnel — then activate it. (Sending works today; receiving is the missing half.)
4. **RAG**: create a Postgres credential in n8n (host `postgres`, db `rag`, user/pass from `.env`), drop docs in a watched folder to ingest, then activate. Design in `docs/design/inspirationRouting.md` #3.
5. **RAM**: quit Chrome when running heavy jobs (it was crash-looping + eating ~7 GB) and cap Docker memory — see the earlier RAM notes. More free RAM = faster LLM steps (and makes `gpt-oss:20b` viable).

## 8) Designed but not yet built (next wave)
The full 15-idea blueprint is in **`docs/design/`** (professionalFlows, personalFlows, inspirationRouting, etc.): voice-note→Motion task, email triage + approval, receipt/expense capture, meeting-notes summarizer, competitor monitor, SEO/content engine, auto-changelog, cold-outreach personalization. Each has node-by-node specs ready to build — just say the word.

## 9) Where everything lives
- `workflows/` — all workflow JSON (git-versioned; re-import with `/n8n-export` reversed or the API)
- `.claude/agents/` — persona subagents · `.claude/skills/` — skills · `docs/personas.md` — persona prompts
- `templates/` — invoice/proposal/onboarding HTML · `docs/design/` — the full research blueprint
- `CLAUDE.md` — operator brief · `GUIDE.md` — how-to · this file — the build report
- n8n editor: http://localhost:5678 · bot: @beru_myagent_bot

Everything is committed to git. Welcome back — tell me which to wire up first. 🚀
