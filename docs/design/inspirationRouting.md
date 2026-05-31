I now have grounded, current, build-ready material. Here is the complete deliverable.

---

# n8n Automation Blueprint — Inspiration, Model-Routing, Build Order

**Verified live:** n8n 2.56.0, n8n-MCP connected, `vectorStorePGVector` node confirmed present (your Postgres `rag` DB is directly usable — **do not add Qdrant**; most gallery RAG templates use Qdrant but PGVector is a drop-in swap). Telegram `telegramTrigger` exists natively but needs a public URL; the long-poll alternative `n8n-nodes-telegram-bot-gridasov` (MTProto, ~10k npm downloads) is the localhost-friendly receive path.

---

## (1) INSPIRATION SWEEP — 15 concrete, high-leverage automations

Each: what it does, real nodes, model routing, localhost-vs-tunnel, source. Sorted roughly by leverage for a solo agency.

**1. Telegram "Command Center" — interactive AI dispatcher with personalities**
A single bot that routes free-text/voice commands to sub-workflows ("draft proposal for X", "log this receipt", "what did I decide about Y"). Trigger: `telegramTrigger` (tunnel) OR `telegram-bot-gridasov` long-poll (localhost). Chain: Telegram Trigger → `textClassifier` (qwen3:8b intent routing) → `switch` → Execute Sub-workflow per command → `telegram` reply. Personalities = different system prompts per route (terse "Ops", warm "Assistant", sharp "Strategist"). Routing: classify=qwen3:8b, execution varies. **localhost OK with the polling node; native trigger needs the tunnel.** Inspired by [Private & local Ollama self-hosted assistant](https://n8n.io/workflows/2729-private-and-local-ollama-self-hosted-ai-assistant/) and the [dynamic LLM router](https://n8n.io/workflows/3139-private-and-local-ollama-self-hosted-dynamic-llm-router/).

**2. Voice note → structured task (Telegram + Whisper + Motion)**
Send a voice memo; it transcribes, extracts action items, creates Motion tasks with deadlines. Chain: Telegram Trigger (voice) → Telegram `getFile` → local Whisper via `httpRequest` (or `faster-whisper` container) → `informationExtractor` (qwen3:8b → JSON {title, due, priority}) → `httpRequest` POST to Motion `/v1/tasks` → Telegram confirmation. Routing: transcription=local Whisper, extraction=qwen3:8b. **localhost OK (polling node + local Whisper)**; Motion needs your API key. Direct match to [privacy-focused Telegram+Ollama+Whisper assistant](https://n8n.io/workflows/6012-create-a-privacy-focused-ai-assistant-with-telegram-ollama-and-whisper/).

**3. RAG over YOUR own docs (proposals, SOWs, past client work, notes)**
Ask "what did I quote for similar projects?" and get answers grounded in your archive. Two flows: (a) **ingest** — `localFileTrigger`/`googleDriveTrigger` → `extractFromFile` → `textSplitterRecursiveCharacterTextSplitter` → `documentDefaultDataLoader` → `embeddingsOllama` (qwen3-embedding:0.6b) → `vectorStorePGVector` (insert, your `rag` DB); (b) **query** — `chatTrigger`/Telegram → `agent` + `toolVectorStore` → `lmChatOllama` (gpt-oss:20b) → answer. Routing: embed=qwen3-embedding:0.6b, answer=gpt-oss:20b. **100% localhost.** Based on [Local Chatbot with RAG (28.7k views)](https://n8n.io/workflows/5148-local-chatbot-with-retrieval-augmented-generation-rag/) and [Private Document Q&A with Llama3 + Postgres + Qdrant](https://n8n.io/workflows/5508-create-a-private-document-q-a-system-with-llama3-postgres-qdrant-and-google-drive/) (swap Qdrant→PGVector).

**4. Email triage + AI auto-draft replies (with Telegram approval gate)**
Poll inbox, classify (lead / client / invoice / spam), draft a reply, push to Telegram for one-tap approve/edit before sending. Chain: `gmailTrigger`/`emailReadImap` → `textClassifier` (qwen3:8b) → `switch` → for client/lead: `agent` draft (gpt-oss:20b, or **Claude bridge** for client-facing tone) → Telegram inline-keyboard approval → on approve `gmail`/`emailSend`. Routing: classify=qwen3:8b, draft=gpt-oss:20b, premium client tone=Claude bridge. **Email/Ollama localhost; Telegram approval needs polling node or tunnel.** Based on [Monitor emails & AI auto-replies with Ollama + Telegram](https://n8n.io/workflows/10084-monitor-emails-and-send-ai-generated-auto-replies-with-ollama-and-telegram-alerts/) and [Gmail support auto-responder with Ollama + RAG](https://n8n.io/workflows/4760).

**5. Receipt/expense capture (photo → structured ledger)**
Snap a receipt into Telegram; OCR + AI extracts vendor/date/total/category to a sheet or Postgres for tax/bookkeeping. Chain: Telegram Trigger (photo) → `getFile` → local OCR (Tesseract container or `extractFromFile` for PDFs) → `informationExtractor` (qwen3:8b → JSON) → `googleSheets`/`postgres` append → Telegram confirmation. Routing: extraction=qwen3:8b (vision: a small local VLM via Ollama if image-native is wanted). **localhost OK** with local OCR. Based on [AI receipt & expense tracker with Telegram + Sheets](https://n8n.io/workflows/4950-ai-powered-receipt-and-expense-tracker-with-telegram-google-sheets-and-openai/) and [Extract & categorize receipts with OCR + Telegram](https://n8n.io/workflows/4020).

**6. Meeting notes → summary + action items + Motion tasks**
Drop a recording/transcript; get a clean summary, decisions, and auto-created tasks. Chain: `localFileTrigger`/`googleDriveTrigger` → Whisper transcribe (if audio) → `agent` summarize+extract (gpt-oss:20b) → split action items → `httpRequest` to Motion + email summary to attendees. Routing: transcribe=local Whisper, summarize=gpt-oss:20b. **localhost** except Motion API + outbound email. Based on [Actioning meeting next steps from transcripts](https://n8n.io/workflows/2328) and [Meeting recording + AI summaries with Llama 3.2](https://n8n.io/workflows/5197).

**7. Client onboarding doc generator (Motion + Claude styling)**
New client trigger → generate onboarding packet (welcome, scope, next steps), Claude styles it, render to PDF, deliver. Chain: Form/Telegram/Motion trigger → `set` (client vars) → **Claude bridge** `httpRequest` for nuanced client-facing copy+styling → Gotenberg `httpRequest` (HTML→PDF) → email/Drive. Routing: drafting+styling=**Claude bridge** (this is exactly the high-value case the routing rule reserves Claude for); fallback=gpt-oss:20b. **Localhost** for Gotenberg/Ollama; Claude bridge is your host service; Motion needs key. Pairs with your existing `/client-proposal` skill.

**8. Invoice generator + overdue chaser**
Generate invoices from a tracker and auto-send personalized payment reminders on overdue. Chain: `scheduleTrigger` → `postgres`/`googleSheets` (read open invoices) → `if` overdue → `agent` personalized reminder (gpt-oss:20b, tone-up via Claude bridge for important clients) → `emailSend` → log. Gotenberg renders the invoice PDF. Routing: reminder copy=gpt-oss:20b; VIP tone=Claude bridge. **localhost** + outbound email. (Invoice-reminder personalization pattern from the [invoice-processing category](https://n8n.io/workflows/categories/invoice-processing/).)

**9. Competitor / market monitor (SearXNG + digest)**
Daily scan of competitor sites, pricing, hiring, and keywords; AI diff vs. yesterday; Telegram digest of what changed. Chain: `scheduleTrigger` → `httpRequest` to SearXNG (`http://searxng:8080/search?...&format=json`) + competitor URLs → `compareDatasets` (vs. stored snapshot in `postgres`) → `chainLlm` summarize deltas (gpt-oss:20b) → Telegram/email digest. Routing: summarize=gpt-oss:20b; tag relevance=qwen3:8b. **100% localhost** (SearXNG is local). Pattern from the RSS+Postgres+compareDatasets+Ollama [competitor/news monitor template (5400)](https://n8n.io/workflows/5400) — deterministic SearXNG fetch per your GUIDE, not the flaky tools-agent.

**10. SEO / content engine (research → draft → publish)**
Keyword/topic in → SearXNG research → outline → draft → image → schedule social. Chain: `chatTrigger`/`scheduleTrigger` → SearXNG `httpRequest` research → `agent` outline+draft (gpt-oss:20b; final polish via Claude bridge) → `editImage`/image gen → `googleDrive` or social node. Routing: research-synthesis=gpt-oss:20b, headline/CTA polish=Claude bridge. **localhost** for research/draft; publishing needs platform keys. Based on [SEO blog posts from web searches](https://n8n.io/workflows/8192) and [LinkedIn posts with Ollama (5k views)](https://n8n.io/workflows/4674).

**11. Auto-changelog / release notes from git**
On a new tag, summarize commits into customer-facing release notes; post to Telegram/email. Chain: `githubTrigger` (or `scheduleTrigger` + `httpRequest` GitHub API) → fetch commits/PRs → `chainLlm` categorize Features/Fixes (gpt-oss:20b; final wording via Claude bridge for public notes) → write to repo/Telegram. Routing: categorize=qwen3:8b, prose=gpt-oss:20b/Claude. **Needs tunnel** if using `githubTrigger` webhook; **localhost OK** if you poll. Based on [Generate changelogs from Git commits with GPT-4](https://n8n.io/workflows/8137) and [GitHub release notes with AI comparison](https://n8n.io/workflows/11569).

**12. Cold-outreach personalization at scale**
List of leads → SearXNG/site enrichment → personalized first-line + angle per lead → draft for approval. Chain: `googleSheets`/`postgres` leads → `httpRequest` SearXNG enrich → `informationExtractor` (qwen3:8b pull facts) → `agent` personalized opener (gpt-oss:20b; best-fit messaging via Claude bridge) → draft to `gmail` (manual approve). Routing: enrich/extract=qwen3:8b, personalization=gpt-oss:20b→Claude. **localhost** for research; sending needs email. (Personalization pattern adapted from invoice-reminder personalization + SEO research templates above.)

**13. NotebookLM-style "chat with my knowledge base" + daily brief**
RAG (#3) plus a scheduled morning brief: top of inbox, today's Motion tasks, calendar, competitor deltas, in one Telegram message. Chain: `scheduleTrigger` 07:30 Europe/Berlin → gather (Gmail + Motion `httpRequest` + Calendar + monitor snapshot) → `agent` compose brief (gpt-oss:20b, "Strategist" personality) → Telegram. Routing: compose=gpt-oss:20b. **localhost** + the external APIs you wire in. The fully-local NotebookLM pattern is a noted 2026 highlight — see [The AI Automators: fully-local RAG frontend (n8n+Ollama)](https://www.theaiautomators.com/fully-local-rag-frontend/).

**14. Document/spreadsheet/image summarizer (drop-folder)**
Drop any file in a watched folder; get a summary + extracted entities filed back. Chain: `localFileTrigger` → `switch` by type → `extractFromFile` → `agent` summarize (gpt-oss:20b; images via local VLM) → write summary file / index into RAG. Routing: summarize=gpt-oss:20b. **100% localhost.** Based on [Summarize Documents, Images & Spreadsheets with Gemma 3 on Ollama](https://n8n.io/workflows/5858) and [Process Legal Documents with Ollama, 100% local (4869)](https://n8n.io/workflows/4869).

**15. Local MCP server exposing your RAG to Claude/agents**
Turn your `rag` DB into an MCP tool any agent (including Claude) can query. Chain: `mcpTrigger` → `vectorStorePGVector` retrieve → `embeddingsOllama`. Routing: embed=qwen3-embedding:0.6b. **localhost.** Based on [Build an MCP Server that answers with RAG (5403)](https://n8n.io/workflows/5403).

**High-value picks the other agents are likely to miss:** #3/#13 (RAG over *your own* agency archive — compounding, $0, fully local), #7 (Claude-bridge as a styling microservice rather than a chat toy), #9 (SearXNG-deterministic competitor monitor — local web intel at $0), and #1's "agent personalities" implemented as per-route system prompts behind one classifier (cheap, qwen3:8b).

---

## (2) FINAL MODEL-ROUTING POLICY

| Task type | Model | Why / RAM / cost | Escalate when |
|---|---|---|---|
| Intent classification, routing, tagging | **qwen3:8b** | ~6.5 GB, fast, deterministic enough; $0 | Never — wrong route is cheap to retry |
| Field/entity extraction → JSON (receipts, leads, tasks) | **qwen3:8b** | Small, reliable with `informationExtractor`/structured output | If schema is large/ambiguous → gpt-oss:20b |
| Voice/audio transcription | **local Whisper** (faster-whisper) | Not an Ollama LLM; runs on CPU/Metal, $0, private | n/a |
| Embeddings (RAG ingest + query) | **qwen3-embedding:0.6b** | Tiny, built for this; matches your PGVector dim | Keep consistent — never mix embedders in one index |
| Summaries, multi-step reasoning, internal drafts | **gpt-oss:20b** | ~16 GB, safe on 38 GB; the agency default workhorse | Max quality + RAM free → qwen3.6:35b-a3b |
| Competitor/news synthesis, ad/report summaries | **gpt-oss:20b** | Good reasoning, runs alongside Docker | Premium reasoning → qwen3.6:35b-a3b |
| Client-facing copy, nuanced documents, STYLING | **Claude bridge** (host `claude -p`, Bearer @ `host.docker.internal:8787`) | Highest quality tone/format; on your Max sub = $0 marginal; no local RAM cost (offloads the M3) | Default to gpt-oss:20b if bridge is off/down |
| Code generation / refactoring inside workflows | **Claude bridge** | Best at code; keeps local RAM free | Fallback gpt-oss:20b |
| Premium reasoning when quality > everything | **qwen3.6:35b-a3b** | ~26–30 GB; **only** when LM Studio closed + Docker light, else it swaps | If RAM tight → gpt-oss:20b, don't risk the swap |

**RAM discipline (M3 Pro 38 GB, swaps):** never two big models at once. gpt-oss:20b is the safe default. Use qwen3.6:35b-a3b *only* with LM Studio unloaded and Docker quiet. Prefer the Claude bridge for the highest-quality jobs precisely *because* it runs on the host subscription and consumes **zero local RAM** — it's both the quality ceiling and a RAM-relief valve. Keep qwen3:8b resident for the constant classify/extract traffic; let big models idle-unload (Ollama's keep-alive timer).

**Escalation ladder:** qwen3:8b → gpt-oss:20b → (Claude bridge for client-facing/code | qwen3.6:35b-a3b for premium reasoning). Escalate to Claude the moment output is seen by a client or is code.

---

## (3) PRIORITIZED BUILD ORDER (first 8)

Keys you likely have/can get fast: Telegram bot token, email (IMAP/SMTP or Gmail), Motion API key, local stack (Ollama/SearXNG/Postgres). Gotenberg + Claude bridge + tunnel are setup items flagged below.

| # | Workflow | Why first | Localhost vs tunnel | External setup needed |
|---|---|---|---|---|
| **1** | **RAG over your own docs (#3)** | Highest compounding value, 100% local, $0, unlocks #13 & #15. No external keys. | Localhost | None (Postgres `rag` ready) |
| **2** | **Telegram Command Center skeleton (#1)** | The hub everything else plugs into; build the classifier+switch+personalities once. | Polling node = localhost; native trigger = tunnel | Telegram bot token; install `n8n-nodes-telegram-bot-gridasov` **or** set up Cloudflare Tunnel |
| **3** | **Voice note → Motion task (#2)** | Daily personal+pro win; proves Whisper + Motion + Telegram path. | Localhost (polling + local Whisper) | Motion API key (12 req/min individual limit — batch politely); local Whisper container |
| **4** | **Email triage + AI draft + approval (#4)** | Biggest time-saver for client comms; reuses #2's approval pattern. | Ollama localhost; approval via #2's Telegram path | Email creds (IMAP/SMTP or Gmail OAuth) |
| **5** | **Receipt/expense capture (#5)** | Quick, high-satisfaction, tax-relevant; reuses Telegram+extract. | Localhost | Local OCR (Tesseract container); sheet/DB target |
| **6** | **Client onboarding/doc generator + Claude styling (#7)** | First real Claude-bridge payoff; ties into `/client-proposal`. | Localhost (Ollama/Gotenberg); bridge is host service | Stand up Gotenberg container + Claude bridge (Bearer token) |
| **7** | **Competitor monitor (#9)** | Pure local web intel, $0, deterministic SearXNG; runs unattended. | 100% localhost | None (SearXNG + Postgres ready) |
| **8** | **Daily brief (#13)** | Capstone: aggregates #3/#4/#7 + Motion/Calendar into one morning Telegram message. | Localhost + wired APIs | Reuses keys from #2–#7; optional Calendar |

**Sequencing logic:** #1 builds the knowledge substrate; #2 builds the interaction hub; #3–#5 are fast daily wins reusing the hub; #6 introduces the Claude bridge + PDF stack; #7 is unattended local intel; #8 is the capstone that makes everything feel like one assistant. Defer #10/#11/#12/#14/#15 to a second wave (need publishing keys, GitHub webhooks/tunnel, or build on the RAG already shipped in #1).

**Two setup decisions to make early:** (a) **Telegram receive** — install the `telegram-bot-gridasov` long-poll community node to stay fully localhost, or run a Cloudflare Tunnel to use the native `telegramTrigger`. The polling node keeps your localhost-only posture (recommended) but is unverified/community; the tunnel is more "standard n8n" but exposes a webhook. (b) **Whisper** — run a local `faster-whisper` container for #2/#6's audio; it keeps voice 100% private and $0.

**Sources:** [n8n.io/workflows 5148](https://n8n.io/workflows/5148-local-chatbot-with-retrieval-augmented-generation-rag/), [5508](https://n8n.io/workflows/5508-create-a-private-document-q-a-system-with-llama3-postgres-qdrant-and-google-drive/), [2729](https://n8n.io/workflows/2729-private-and-local-ollama-self-hosted-ai-assistant/), [3139](https://n8n.io/workflows/3139-private-and-local-ollama-self-hosted-dynamic-llm-router/), [6012](https://n8n.io/workflows/6012-create-a-privacy-focused-ai-assistant-with-telegram-ollama-and-whisper/), [10084](https://n8n.io/workflows/10084-monitor-emails-and-send-ai-generated-auto-replies-with-ollama-and-telegram-alerts/), [4760](https://n8n.io/workflows/4760), [4950](https://n8n.io/workflows/4950-ai-powered-receipt-and-expense-tracker-with-telegram-google-sheets-and-openai/), [4020](https://n8n.io/workflows/4020), [2328](https://n8n.io/workflows/2328), [5197](https://n8n.io/workflows/5197), [5400](https://n8n.io/workflows/5400), [5858](https://n8n.io/workflows/5858), [4869](https://n8n.io/workflows/4869), [8192](https://n8n.io/workflows/8192), [4674](https://n8n.io/workflows/4674), [8137](https://n8n.io/workflows/8137), [11569](https://n8n.io/workflows/11569), [5403](https://n8n.io/workflows/5403), [Motion API rate limits](https://docs.usemotion.com/cookbooks/rate-limits/), [Motion create task](https://docs.usemotion.com/api-reference/tasks/post/), [The AI Automators — fully-local RAG](https://www.theaiautomators.com/fully-local-rag-frontend/), [n8n AI agent + Ollama 2026 guide](https://www.iloveblogs.blog/guides/n8n-ai-agent-workflows-ollama).

**MCP-verified node facts:** `@n8n/n8n-nodes-langchain.vectorStorePGVector` present (use your `rag` DB, skip Qdrant); native `n8n-nodes-base.telegramTrigger` exists but is webhook-based (tunnel); community `n8n-nodes-telegram-bot-gridasov` (~10k downloads) provides long-poll receive for localhost; `embeddingsOllama`, `lmChatOllama`, `agent`, `textClassifier`, `informationExtractor`, `toolVectorStore`, `documentDefaultDataLoader`, `textSplitterRecursiveCharacterTextSplitter`, `extractFromFile`, `compareDatasets`, `httpRequest`, `scheduleTrigger`, `localFileTrigger` all confirmed available on this 2.56.0 instance.
