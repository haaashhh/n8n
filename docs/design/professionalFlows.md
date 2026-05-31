All node types confirmed available. I have everything needed: real templates cited, exact node names verified, and the stack's constraints. Let me compose the build-ready design.

---

# 6-8 BUILD-READY WORKFLOWS — Solo Software Agency (local n8n 2.23.1 + Ollama, $0 runtime)

**Conventions used below.** Ollama LLM nodes = `@n8n/n8n-nodes-langchain.lmChatOllama` with the credential pointing at `http://host.docker.internal:11434`, model set per the routing rule. "Claude-bridge" = `n8n-nodes-base.httpRequest` POST to `http://host.docker.internal:8787` with `Authorization: Bearer <token>` — used only for client-facing styling/code. Web search = `n8n-nodes-base.httpRequest` GET `http://searxng:8080/search?q=...&format=json` (deterministic, per CLAUDE.md — do not use the Ollama tools-agent). PDF = `n8n-nodes-base.httpRequest` POST to Gotenberg Chromium route `http://gotenberg:3000/forms/chromium/convert/html` (add `gotenberg/gotenberg:8` to compose.yaml on the internal Docker network). Everything runs on localhost EXCEPT inbound webhooks/Telegram receive, which need the Cloudflare Tunnel — flagged per workflow.

**Shared infra you should provision once (used by several flows):**
- A Postgres table in the existing `rag` DB for client/lead/invoice state (acts as your free CRM — avoids Airtable/Google Sheets dependency). Tables: `leads`, `clients`, `projects`, `invoices`. Use `n8n-nodes-base.postgres`.
- Telegram bot token (you have it — sending works). Receiving needs the tunnel OR `n8n-nodes-telegram-polling` community node.
- A "Notify me" sub-pattern: `n8n-nodes-base.telegram` send to your chat ID (works on localhost).

---

## Priority tier (by leverage)

| # | Workflow | Leverage | Localhost? |
|---|---|---|---|
| 1 | Inbound Lead Capture + AI Qualification | Highest — fills the funnel, never drop a lead | Capture needs tunnel; rest local |
| 2 | Telegram Command Center (agent personalities) | Highest — the control plane for everything else | Send local; **receive needs tunnel/polling** |
| 3 | Proposal / SOW Generator | High — converts leads to revenue | Fully local |
| 4 | Invoice Generation + Payment Follow-ups | High — protects cash flow | Fully local (Stripe webhook needs tunnel) |
| 5 | Client Onboarding | Medium-high — first impression, kills manual setup | Fully local |
| 6 | Inbox Triage + Reply Drafting | Medium-high — daily time sink | Fully local (IMAP poll) |
| 7 | Weekly Client Report (project/analytics) | Medium | Fully local |
| 8 | Daily Standup / Project Digest (self) | Medium — personal ops | Fully local |

---

## WORKFLOW 1 — Inbound Lead Capture + AI Qualification (BANT scoring + routing)
**Trigger:** `n8n-nodes-base.formTrigger` (hosted n8n form — public lead form) **OR** `n8n-nodes-base.webhook` (embed on your site / accept Typeform/Tally posts).

**Node-by-node chain:**
1. `formTrigger` / `webhook` — captures name, email, company, budget, timeline, message.
2. `n8n-nodes-base.httpRequest` → SearXNG `http://searxng:8080/search?q={{company}}&format=json` — free enrichment (company web presence, size signals). Localhost.
3. `@n8n/n8n-nodes-langchain.informationExtractor` (LLM: **qwen3:8b**) — extract structured fields from the free-text message: `{intent, budget_band, timeline, tech_stack, urgency}`.
4. `@n8n/n8n-nodes-langchain.textClassifier` (LLM: **qwen3:8b**) — BANT tier classification → `hot | warm | cold`.
5. `n8n-nodes-base.if` / `n8n-nodes-base.switch` — route by tier.
6. `n8n-nodes-base.postgres` (insert into `leads`) — persist lead + score + reasoning. Localhost CRM.
7. **Hot path:** `@n8n/n8n-nodes-langchain.chainLlm` styling via **Claude-bridge** (`httpRequest` to :8787) — draft a personalized first-touch reply → `n8n-nodes-base.gmail` (send) + `n8n-nodes-base.telegram` instant alert to you ("HOT: Director @ Acme, 30k budget, 2-wk timeline").
8. **Warm/cold path:** **gpt-oss:20b** drafts a templated nurture reply → Gmail; Telegram digest only.

**Model routing:** extract + classify → **qwen3:8b**; nurture drafts → **gpt-oss:20b**; hot-lead client-facing reply → **Claude-bridge**.
**Keys/setup you provide:** Gmail OAuth2 (or SMTP) credential; Telegram bot token + your chat ID; Postgres `leads` table DDL. SearXNG already up.
**Localhost vs tunnel:** the public form/webhook **needs the Cloudflare Tunnel** to receive external submissions; everything downstream is local. (If you only ever paste leads in yourself, you can skip the tunnel and trigger manually.)
**Doc outputs:** no PDF. Replies = Claude-styled (hot) / gpt-oss (warm).
**Inspired by:** [BANT lead qualification + multi-channel follow-up](https://n8n.io/workflows/8773-automate-lead-qualification-and-multi-channel-follow-up-with-ai-bant/), [AI Lead Qualification & Routing w/ Slack & Airtable](https://n8n.io/workflows/9349-ai-powered-lead-qualification-and-routing-with-openai-slack-and-airtable/), [Qualify & enrich leads with GPT-4 + intelligent routing](https://n8n.io/workflows/11493-qualify-and-enrich-leads-with-gpt-4-and-linkedin-data-for-intelligent-routing/).

---

## WORKFLOW 2 — Telegram Command Center with Agent Personalities
**Trigger:** `n8n-nodes-base.telegramTrigger` (verified available). **Receiving needs the Cloudflare Tunnel** (webhook) **or** the `n8n-nodes-telegram-polling` community node — flag this clearly, it's the one hard dependency. Sending already works.

**Node-by-node chain:**
1. `telegramTrigger` — on message.
2. `@n8n/n8n-nodes-langchain.textClassifier` (LLM: **qwen3:8b**) — intent routing: `new_lead | draft_proposal | invoice_status | project_digest | inbox_triage | general_chat`. This is the "router" personality.
3. `n8n-nodes-base.switch` — dispatch to a sub-workflow per intent via `n8n-nodes-base.executeWorkflow` (calls Workflows 1/3/4/7/8 as tools).
4. **Personalities** = distinct system prompts on `@n8n/n8n-nodes-langchain.agent` nodes, each with its own LLM binding:
   - "Ops" (terse, factual, status/numbers) → **qwen3:8b**.
   - "Strategist" (reasoning, planning, multi-point) → **gpt-oss:20b**.
   - "Writer" (client-facing tone/polish) → **Claude-bridge**.
5. `@n8n/n8n-nodes-langchain.memoryPostgresChat` (table in `rag`) — per-chat conversation memory so it's stateful.
6. `n8n-nodes-base.telegram` — reply.

**Model routing:** router/Ops → **qwen3:8b**; Strategist → **gpt-oss:20b**; Writer → **Claude-bridge**. Never load two big models at once — the router (qwen3:8b) stays resident; gpt-oss loads on demand.
**Keys/setup you provide:** Telegram bot token + your chat ID (whitelist it in an early `if` so only you can command it); Postgres chat-memory table; the Claude-bridge token. **Decide: tunnel vs polling node** for receive.
**Localhost vs tunnel:** **receive = tunnel or polling node**; all processing + send = local.
**Doc outputs:** delegates to other workflows; styling via Claude when a personality calls for it.
**Inspired by:** [Telegram bot starter + AI agent chatbot](https://n8n.io/workflows/2402-telegram-bot-starter-template-setup-and-ai-agent-chatbot/), [N8N Multi-Agent Telegram Bot (hierarchical router + sub-agents)](https://github.com/AkilLabs/N8N-Multi-Agent-Telegram-Bot), [Conversational Telegram bot w/ swappable model + personality](https://n8n.io/workflows/4696-conversational-telegram-bot-with-gpt-5gpt-4o-for-text-and-voice-messages/).

---

## WORKFLOW 3 — Proposal / SOW Generator
**Trigger:** `n8n-nodes-base.executeWorkflowTrigger` (called from Telegram or from Workflow 1's hot path) **or** `formTrigger` ("New proposal" intake form: client, scope bullets, deliverables, rate, timeline).

**Node-by-node chain:**
1. Trigger collects scope inputs.
2. `n8n-nodes-base.postgres` — pull client record + any prior project notes from `clients`/`projects` (context).
3. `@n8n/n8n-nodes-langchain.vectorStorePGVector` (retrieve, embeddings = **qwen3-embedding:0.6b**) — RAG over your past proposals/case studies in the `rag` DB so the SOW reuses proven language.
4. `@n8n/n8n-nodes-langchain.chainLlm` (LLM: **gpt-oss:20b**) — draft the SOW *content/structure*: scope, deliverables, milestones, assumptions, pricing table, T&Cs.
5. **Claude-bridge** (`httpRequest` :8787) — restyle into polished, on-brand client-facing prose + clean HTML (this is the styling step you specifically want Claude for).
6. `n8n-nodes-base.httpRequest` → **Gotenberg** `/forms/chromium/convert/html` — render branded HTML → PDF.
7. `n8n-nodes-base.postgres` — log proposal + status `sent`; `n8n-nodes-base.gmail` — email PDF to client; `n8n-nodes-base.telegram` — notify you with the draft for approval *before* send (add a `n8n-nodes-base.wait`/approval gate if you want human-in-loop).

**Model routing:** retrieval embeddings → **qwen3-embedding:0.6b**; structure/reasoning → **gpt-oss:20b** (or **qwen3.6:35b-a3b** for a flagship proposal when RAM allows); styling → **Claude-bridge**.
**Keys/setup you provide:** Gmail/SMTP; Gotenberg service in compose; seed the `rag` vector store with 3-5 past proposals; brand HTML/CSS template. Claude-bridge token.
**Localhost vs tunnel:** fully local.
**Doc outputs:** **Claude styles** the prose/HTML → **Gotenberg renders the PDF**. (Motion: see note below — not needed here; Gotenberg+Claude is the better local-first path.)
**Inspired by:** [AI proposal generator](https://n8n.io/workflows/6534-ai-proposal-generator/), [AI premium proposal generator (OpenAI + Slides + PandaDoc)](https://n8n.io/workflows/4804-ai-premium-proposal-generator-with-openai-google-slides-and-pandadoc/), [AI-powered post-sales-call proposal generator](https://n8n.io/workflows/4359-ai-powered-post-sales-call-automated-proposal-generator/).

---

## WORKFLOW 4 — Invoice Generation + Payment Follow-ups
**Two triggers (one workflow or two):**
- **Generate:** `n8n-nodes-base.executeWorkflowTrigger` (from Telegram "invoice ClientX 2000 EUR") or a `formTrigger`.
- **Chase:** `n8n-nodes-base.scheduleTrigger` daily at 09:00 Europe/Berlin.

**Generate chain:**
1. Trigger → `n8n-nodes-base.set`/`code` — build line items, unique invoice ID, due date.
2. `n8n-nodes-base.postgres` — insert into `invoices` (status `unpaid`).
3. `n8n-nodes-base.httpRequest` → **Gotenberg** — render branded HTML invoice → PDF. (Pure-data invoice = no LLM needed; keeps it deterministic and $0.)
4. `n8n-nodes-base.gmail` — email PDF + (optional) Stripe payment link; `telegram` confirm.

**Chase chain (scheduled):**
5. `scheduleTrigger` → `n8n-nodes-base.postgres` (select `unpaid` invoices) → `n8n-nodes-base.filter` (due-soon vs overdue).
6. `@n8n/n8n-nodes-langchain.chainLlm` (LLM: **gpt-oss:20b**) — draft a polite pre-due nudge / firmer overdue reminder, tone scaled by days-overdue.
7. **Claude-bridge** — light styling pass for the most sensitive (60+ days) reminders only, to keep the relationship warm.
8. `n8n-nodes-base.gmail` send; `n8n-nodes-base.postgres` update `last_reminded_at`; `telegram` daily AR summary to you.
9. **Stripe reconcile (optional):** `n8n-nodes-base.stripeTrigger` (webhook on `payment_intent.succeeded`) → `postgres` mark `paid` → stop reminders. **Stripe webhook needs the tunnel.** Alternative without tunnel: scheduled `httpRequest` polling Stripe's API.

**Model routing:** reminder drafts → **gpt-oss:20b**; high-stakes styling → **Claude-bridge**; no model on the invoice render itself.
**Keys/setup you provide:** Stripe API key + (if using webhook) tunnel + webhook secret; Gmail/SMTP; Gotenberg; `invoices` table DDL.
**Localhost vs tunnel:** generation + chasing = local; **Stripe inbound webhook = tunnel** (or poll instead).
**Doc outputs:** **Gotenberg** PDF invoice (deterministic, no Motion needed); reminder emails gpt-oss-drafted, Claude-styled for sensitive cases.
**Inspired by:** [Automated invoice workflow w/ smart reminders (GPT-4 + Stripe)](https://n8n.io/workflows/6515-automated-invoice-workflow-with-smart-reminders-using-gpt-4-stripe-and-google-workspace/), [AI-powered invoice reminder & payment tracker (daily 9AM)](https://n8n.io/workflows/10111-ai-powered-invoice-reminder-and-payment-tracker-for-finance-and-accounting/), [Generate & deliver PDF invoices (HTML→PDF)](https://n8n.io/workflows/9447-generate-and-deliver-pdf-invoices-from-jotform-to-google-drive-and-email/).

---

## WORKFLOW 5 — Client Onboarding
**Trigger:** `n8n-nodes-base.executeWorkflowTrigger` fired when Workflow 3 logs a proposal as `accepted` (or a manual Telegram command / `formTrigger` onboarding questionnaire).

**Node-by-node chain:**
1. Trigger with signed-client details.
2. `n8n-nodes-base.postgres` — promote `lead` → `client`, create `project` row, generate project ID.
3. `@n8n/n8n-nodes-langchain.informationExtractor` (LLM: **qwen3:8b**) — parse onboarding questionnaire into structured project params (stack, access needed, milestones, comms cadence).
4. `n8n-nodes-base.googleDrive` (optional) — create a client folder from template; OR keep it fully local with a Postgres-backed checklist.
5. `@n8n/n8n-nodes-langchain.chainLlm` (LLM: **gpt-oss:20b**) — generate an onboarding checklist + kickoff agenda from the parsed params.
6. **Claude-bridge** — write the warm, branded welcome email + a styled "what happens next" one-pager (HTML).
7. `n8n-nodes-base.httpRequest` → **Gotenberg** — one-pager → PDF (optional).
8. `n8n-nodes-base.gmail` — send welcome + one-pager; `n8n-nodes-base.telegram` — notify you, post the internal checklist.

**Model routing:** questionnaire extraction → **qwen3:8b**; checklist/agenda → **gpt-oss:20b**; welcome email + one-pager styling → **Claude-bridge**.
**Keys/setup you provide:** Gmail/SMTP; Telegram; (optional) Google Drive OAuth2; Gotenberg; `clients`/`projects` tables.
**Localhost vs tunnel:** fully local.
**Doc outputs:** welcome email + one-pager → **Claude-styled**, **Gotenberg** PDF.
**Inspired by:** [AI-powered client onboarding (Jotform/Asana/Slack/HubSpot)](https://n8n.io/workflows/9628-ai-powered-client-onboarding-with-jotform-asana-slack-and-hubspot/), [AI client onboarding agent: auto welcome email](https://n8n.io/workflows/4448-ai-client-onboarding-agent-auto-welcome-email-generator/), [Client onboarding with form](https://n8n.io/workflows/8977-client-onboarding-with-form/).

---

## WORKFLOW 6 — Inbox Triage + AI Reply Drafting
**Trigger:** `n8n-nodes-base.emailReadImap` (Email Trigger IMAP — verified) **or** `n8n-nodes-base.gmailTrigger`. IMAP polling works fully on localhost (no tunnel).

**Node-by-node chain:**
1. `emailReadImap` / `gmailTrigger` — new email.
2. `@n8n/n8n-nodes-langchain.textClassifier` (LLM: **qwen3:8b**) — classify: `client_question | new_lead | invoice/payment | vendor/spam | scheduling`.
3. `n8n-nodes-base.postgres` — match sender to a known `client`/`lead` for context.
4. `n8n-nodes-base.switch`:
   - `new_lead` → hand to Workflow 1.
   - `invoice/payment` → hand to Workflow 4.
   - `client_question` → continue to draft.
5. `@n8n/n8n-nodes-langchain.vectorStorePGVector` (embeddings **qwen3-embedding:0.6b**) — pull prior thread context / project facts from `rag`.
6. **Claude-bridge** — draft a high-quality, on-tone reply (client-facing = Claude). For internal/low-stakes, route to **gpt-oss:20b** instead via an `if` on classification.
7. `n8n-nodes-base.gmail` — **create draft** (not auto-send) so you review; `n8n-nodes-base.telegram` — ping you with a summary + the draft for one-tap approval.

**Model routing:** classify → **qwen3:8b**; internal/simple replies → **gpt-oss:20b**; client-facing replies → **Claude-bridge**.
**Keys/setup you provide:** IMAP creds or Gmail OAuth2; Telegram; vector store seeded with client context.
**Localhost vs tunnel:** fully local (IMAP poll). Telegram approval reply needs receive (tunnel/polling) — but the draft-in-Gmail path works without it.
**Doc outputs:** email drafts → **Claude-styled** (client) / gpt-oss (internal). No PDF.
**Inspired by:** [Multi-channel customer support (Gmail + Telegram + AI)](https://n8n.io/workflows/4474-automate-multi-channel-customer-support-with-gmail-telegram-and-gpt-ai/), [Daily email digest w/ AI summarization (LangChain)](https://n8n.io/workflows/5003), [AI Telegram assistant & summarizer](https://n8n.io/workflows/4457-ai-telegram-bot-agent-smart-assistant-and-content-summarizer/).

---

## WORKFLOW 7 — Weekly Client Report (project + analytics)
**Trigger:** `n8n-nodes-base.scheduleTrigger` — Fridays 16:00 Europe/Berlin.

**Node-by-node chain:**
1. `scheduleTrigger`.
2. Per-client data pulls (parallel `httpRequest`/native nodes):
   - Project status from `n8n-nodes-base.postgres` (`projects` table) — or `n8n-nodes-base.jira` if you track in Jira.
   - Analytics: `n8n-nodes-base.httpRequest` to GA4 / Plausible / ad platform APIs (whatever the client uses).
3. `n8n-nodes-base.code` / `n8n-nodes-base.aggregate` — compute KPIs deterministically (don't let the LLM do math): tickets done vs total, hours, spend, conversions.
4. `@n8n/n8n-nodes-langchain.chainLlm` (LLM: **gpt-oss:20b**) — write the narrative: what shipped, insights, recommendations, next week's plan.
5. **Claude-bridge** — restyle into a polished, branded client report (HTML).
6. `n8n-nodes-base.httpRequest` → **Gotenberg** — HTML → PDF.
7. `n8n-nodes-base.gmail` — email PDF per client; `n8n-nodes-base.telegram` — send you the batch summary.

**Model routing:** KPI math = code (no LLM); narrative/insights → **gpt-oss:20b**; report styling → **Claude-bridge**.
**Keys/setup you provide:** API keys per analytics/ad source (GA4 service account, Plausible token, Meta/Google Ads tokens — only what clients use); Gotenberg; brand template.
**Localhost vs tunnel:** fully local (all outbound API calls).
**Doc outputs:** weekly report → **Claude-styled** narrative + **Gotenberg** PDF.
**Inspired by:** [Automated Sprint Reports Jira → Gmail (HTML report)](https://n8n.io/workflows/8932), [Automated weekly tech-stack reports (GPT-4o + Gmail)](https://n8n.io/workflows/4788), [Daily stock digest (aggregate → AI HTML → Gmail)](https://n8n.io/workflows/8724).

---

## WORKFLOW 8 — Daily Standup / Project Digest (personal ops)
**Trigger:** `n8n-nodes-base.scheduleTrigger` — daily 08:00 Europe/Berlin (morning) + 18:00 (wrap-up).

**Node-by-node chain:**
1. `scheduleTrigger`.
2. Gather signals (parallel): `n8n-nodes-base.postgres` (open projects/tasks, overdue invoices), `n8n-nodes-base.gmail`/`emailReadImap` (unreplied client mail in last 24h), optional `n8n-nodes-base.githubTrigger`/`github` (open PRs/issues), optional calendar via `httpRequest`.
3. `n8n-nodes-base.aggregate` — consolidate into one payload.
4. `@n8n/n8n-nodes-langchain.chainLlm` (LLM: **qwen3:8b** for the morning terse digest; **gpt-oss:20b** for the evening reflective "what mattered / what's at risk").
5. `n8n-nodes-base.telegram` — send the digest to your chat (works on localhost — send-only).

**Model routing:** morning quick digest → **qwen3:8b**; evening reasoning digest → **gpt-oss:20b**. No Claude needed (internal-only).
**Keys/setup you provide:** Telegram; (optional) GitHub token, calendar API.
**Localhost vs tunnel:** fully local (send-only Telegram).
**Doc outputs:** Telegram messages only — no PDF, no Claude.
**Inspired by:** [Automate daily standups (Slack/Notion/Redis)](https://n8n.io/workflows/13505), [Daily email digest w/ AI summarization](https://n8n.io/workflows/5003), [Cybersecurity daily digest (RSS → LLM → email)](https://n8n.io/workflows/7608).

---

## Cross-cutting decisions you asked about

**Motion (usemotion.com) — recommendation: do NOT put it in the document-drafting loop.** Motion in 2026 is an AI calendar/task-scheduling and project-management product; it is not a document-templating/merge engine, and it has no first-party n8n node (you'd be hitting its REST API by hand via `httpRequest`). For your stated goal — drafting onboarding docs, invoices, proposals with Claude doing the styling — the better local-first path is **Claude-bridge (content/styling) → Gotenberg (HTML→PDF)**: $0, fully local, no external dependency, full brand control. **Where Motion earns its place:** as the *scheduling/PM layer*, not the doc layer — e.g., Workflow 5 (onboarding) and 8 (standup) can `httpRequest` Motion to auto-create the project + tasks + calendar blocks once a client signs. I'd wire Motion there, behind a flag, and keep documents on Claude+Gotenberg.

**Stripe vs alternatives for invoicing:** Stripe is the path of least resistance (native `stripeTrigger` + API). If you want zero external SaaS, you can generate the PDF + a manual bank-transfer (SEPA, since you're in Berlin) reference number entirely locally via Gotenberg and skip Stripe — at the cost of manual reconciliation in Workflow 4's chase loop.

**The one true external dependency to decide first: Telegram receive + inbound webhooks.** Workflows 1 (public form), 2 (Telegram receive), and 4 (Stripe webhook) need either the **Cloudflare Tunnel** or, for Telegram specifically, the `n8n-nodes-telegram-polling` community node. Everything else (3, 5, 6, 7, 8 and all processing/sending) runs fully on localhost. Recommendation: stand up the Cloudflare Tunnel once — it unblocks all three and is the cleaner long-term answer than the polling node.

**RAM discipline (M3 Pro 38GB):** the design keeps **qwen3:8b** as the always-resident classifier/router and loads **gpt-oss:20b** on demand; **qwen3.6:35b-a3b** is opt-in only for flagship proposals (Workflow 3) when LM Studio is closed and Docker is light. No workflow ever needs two big local models simultaneously. Heavy client-facing styling is offloaded to Claude-bridge (runs on your Max subscription, not local RAM).

**Build order I'd recommend:** provision Postgres CRM tables + Gotenberg + (decide) tunnel → **W4 invoices** (immediate cash impact, mostly deterministic, low risk) → **W1 leads** → **W3 proposals** → **W6 inbox** → **W2 Telegram command center** (ties them together) → **W5 onboarding** → **W7/W8 reporting**.

Each is ready for the `/n8n-build` validate-first loop (search_nodes already confirmed every node type above exists on this 2.23.1 instance).
