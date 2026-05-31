That search was noisy, but I already know the canonical node names from the templates I mined (`n8n-nodes-base.httpRequest`, `n8n-nodes-base.formTrigger`, `n8n-nodes-base.executeWorkflowTrigger`, `@n8n/n8n-nodes-langchain.lmChatOllama`, etc.). I have all the grounding I need. Now writing the complete deliverable.

---

# Skills Audit + Expansion for the n8n Agency Stack

## Part 1 — Are the short forms "enough"? (research-grounded verdict)

**Short answer: yes for what they currently do, no for what the agency now needs.** The current 7 skills are all "thin orchestration" skills — procedures the *main agent* follows inline. Per Anthropic's own [skill-authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices), that is the *correct* default: "Concise is key… only add context Claude doesn't already have," and SKILL.md should stay well under 500 lines. A skill is not "too short" — it's too short only if Claude can't reliably do the task without re-deriving knowledge each time.

The hard rules that drive every decision below (all from the canonical docs):

- **Frontmatter contract**: only `name` (≤64 chars, lowercase/digits/hyphens, no "claude"/"anthropic") and `description` (≤1024 chars, third-person, "what + when") are required. Optional: `allowed-tools`, `disable-model-invocation`, `user-invocable`, `argument-hint`, `context: fork`, `model`.
- **Description is the discovery surface** — it's the only thing pre-loaded. Write it third-person with concrete trigger terms ("Use when…").
- **Progressive disclosure**: keep the body lean; push long-form material (style guides, HTML templates, prompt libraries, persona sheets) into *one-level-deep* reference files that load only when needed. Never nest references.
- **Degrees of freedom**: fragile/deterministic steps → low freedom (exact commands); open-ended drafting → high freedom (heuristics).
- **MCP tools must be fully qualified** in skill bodies (`mcp__n8n-mcp__create_workflow`), or Claude may not find them.
- **Fork to a subagent (`context: fork`)** only when the task is a self-contained job with an explicit prompt that benefits from its own context window (long research, multi-workflow audits). Forking a "background knowledge" skill returns nothing useful.
- **`user-invocable: false`** = background knowledge (like your `ollama-route`). **`disable-model-invocation: true`** = only fires when *you* type the slash command (good for destructive/expensive ops like `stack-up`, `n8n-backup`).

### Verdict per existing skill

| Skill | Verdict | Why |
|---|---|---|
| `n8n-build` | **Expand (supporting files)** | The single most-used skill. Body is good but should gain reference files (model-routing snippets, reusable node-chain recipes, Gotenberg/Claude-bridge/SearXNG call patterns) so it stops re-deriving them. |
| `n8n-audit` | **Expand → add `context: fork`** | Auditing *every* workflow + instance is a long, self-contained job that pollutes the main context. Ideal fork candidate. Add a structured report template. |
| `stack-up` | **Keep as-is** | Exemplary. `disable-model-invocation`, scoped `allowed-tools`, live-state `!`backtick injection. Textbook. Minor: add an LM-Studio RAM-guard note (already partial). |
| `n8n-backup` | **Keep as-is** | Correctly locked down. Good. |
| `n8n-export` | **Keep, tiny tighten** | Fine. Could add deterministic JSON key-sort guidance to a one-liner; not worth a file. |
| `client-proposal` (user) | **Expand** | Depends on the external `docx` skill. For this stack, route the *styling* through the Claude bridge and offer PDF via Gotenberg. Add a brand/style reference file. |
| `ollama-route` (user) | **Keep as-is** | Perfect background-knowledge skill (`user-invocable: false`). Model name is exact. |

**Net**: 3 keep, 1 tiny tighten, 3 expand. Then add 8 new skills below.

---

## Part 2 — Expansions (concrete)

### 2a. `n8n-build` → add a `reference/` folder (progressive disclosure)

Keep the current body almost verbatim (it's good), but add a navigation block pointing to four reference files so recurring patterns aren't re-derived. Replace the bottom of the existing SKILL.md with:

```markdown
## Reference (load only when relevant)
- Reusable node-chain recipes (trigger→…→deliver): see reference/recipes.md
- AI-node wiring + model routing snippets (Ollama, bridge): see reference/ai-nodes.md
- External service call patterns (SearXNG, Gotenberg, Claude bridge, Motion): see reference/services.md
- Validation failure → fix cheatsheet: see reference/troubleshooting.md
```

`reference/services.md` (the highest-value file — these are the exact call patterns every agency workflow reuses):

```markdown
# External service call patterns (n8n HTTP Request node)

## SearXNG (local web search, deterministic)
GET http://searxng:8080/search?q={{query}}&format=json
Then feed `results[].title/url/content` to the LLM. Do NOT use the Ollama tools-agent for search.

## Gotenberg (HTML -> PDF, local, $0)  [NO dedicated node — use HTTP Request]
1. Build HTML in an HTML node or Set node (field: html).
2. Code/Set: convert to a binary file named index.html (data:text/html;base64 or moveBinaryData).
3. HTTP Request:
   - Method: POST
   - URL: http://gotenberg:3000/forms/chromium/convert/html
   - Body: multipart/form-data; field "files" = the index.html binary
   - Response: Receive File (binary) -> the PDF
4. Add gotenberg service to compose.yaml; it's reachable at gotenberg:3000 from the n8n container.

## Claude bridge (premium client-facing styling / code) [opt-in host service]
HTTP Request:
   - Method: POST
   - URL: http://host.docker.internal:8787
   - Auth: Header  Authorization: Bearer {{ $env.CLAUDE_BRIDGE_TOKEN }}
   - Body JSON: { "prompt": "...", "persona": "..." }
Use ONLY for final styling / nuanced client documents / code. Local Ollama drafts first; bridge polishes.

## Motion (usemotion.com REST API) — drafting client docs/tasks in the loop
Base: https://api.usemotion.com/v1   Header: X-API-Key: {{ $env.MOTION_API_KEY }}
- POST /tasks  -> create task (name, projectId, dueDate, description)
- GET  /tasks  -> list
Use Motion to create/track the doc task; Claude bridge does the styling of the doc body.
```

`reference/ai-nodes.md` (model routing as copy-paste, with the real node type):

```markdown
# AI node wiring (local Ollama)
Chat model node: @n8n/n8n-nodes-langchain.lmChatOllama
Credential URL: http://host.docker.internal:11434  (never 0.0.0.0)

Routing:
- classify / extract / route / tag  -> qwen3:8b
- quality drafting / summaries / reasoning -> gpt-oss:20b (default)
- max quality (LM Studio closed, Docker light) -> qwen3.6:35b-a3b
- embeddings (RAG, Postgres `rag` DB + pgvector) -> qwen3-embedding:0.6b

Pattern for a structured-output step: lmChatOllama + chainLlm + outputParserStructured.
Pattern for tool use: prefer deterministic nodes over the Ollama tools-agent (flaky in n8n).
```

This is the single most leveraged change: it makes every future build deterministic about Gotenberg/bridge/Motion/SearXNG wiring instead of re-discovering it.

### 2b. `n8n-audit` → fork to a subagent + report template

Change frontmatter to fork (it's a long, self-contained job — the canonical "use a subagent when you want it offloaded" case):

```markdown
---
name: n8n-audit
description: Validate and auto-fix every workflow on the local n8n instance, then run a security/config audit. Use when asked to check, lint, audit, or health-check all n8n workflows.
allowed-tools: mcp__n8n-mcp__n8n_list_workflows mcp__n8n-mcp__n8n_validate_workflow mcp__n8n-mcp__n8n_autofix_workflow mcp__n8n-mcp__n8n_audit_instance mcp__n8n-mcp__n8n_executions
context: fork
---
```
(Body stays as-is; tightening `allowed-tools` from the wildcard to the five tools it actually uses follows the least-privilege principle and prevents the forked agent from creating/deleting workflows. Note: keep autofix application gated on confirmation — when forked, default to *report-only* and never apply autofix without the parent relaying confirmation.)

### 2c. `client-proposal` → route styling through the bridge + Gotenberg PDF + brand file

New body (keeps it lean, adds the stack-native styling path and a one-level-deep brand reference):

```markdown
---
name: client-proposal
description: Draft a client proposal, SOW, or quote and produce a polished branded document (PDF via Gotenberg or .docx). Use when asked to write a proposal, SOW, quote, or client-facing offer for the agency.
argument-hint: [client name / project scope]
---

# Client proposal / SOW

Audience: prospective agency clients. Tone: concise, confident, no fluff. Brand voice + boilerplate: see reference/brand.md.

## Workflow
1. If scope is thin, ask 2-3 sharp scoping questions (deliverables, timeline, budget range, success criteria). Don't pad.
2. Draft locally with gpt-oss:20b-level reasoning: Overview - Scope & Deliverables - Approach - Timeline (phases) - Pricing table - Assumptions/Exclusions - Next steps. Keep to 1-2 pages.
3. STYLING (client-facing): send the draft to the Claude bridge (POST http://host.docker.internal:8787, Bearer token) with persona="agency-principal" for final polish + brand voice. If the bridge is off, polish inline.
4. Produce the file:
   - PDF (preferred, $0): render HTML from reference/brand.md template -> Gotenberg (http://gotenberg:3000/forms/chromium/convert/html).
   - .docx: use the official `docx` skill instead.
5. Save to the cwd and report the absolute path. Flag anything to confirm before sending.
```

`reference/brand.md` holds the agency name, colors, logo path, footer/legal boilerplate, and the HTML proposal template — so the voice is consistent and never re-invented.

---

## Part 3 — New skills (full, ready-to-use SKILL.md)

Each is build-ready against the real stack. Templates I mined are cited where they inspired the node chain. Project-scope skills go in `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/<name>/SKILL.md`; persona skills are user-scope.

> **Localhost vs tunnel flag (applies throughout):** Telegram *sending* works on localhost. Telegram *receiving* (`telegramTrigger`) needs a public webhook → use **Cloudflare Tunnel**, OR install the **`n8n-nodes-telegram-bot-gridasov`** community node (long-poll, ~10k npm downloads, MTProto-capable) which works fully on localhost. Any `formTrigger`/`webhook` that an outside client must POST to also needs the tunnel; internal/scheduled triggers do not.

---

### NEW 1 — `/onboard-client` (project scope)

Grounded in n8n templates [#7781 "Graceful Client Onboarding Concierge"](https://n8n.io/workflows/7781) and [#12739 "consulting client onboarding"](https://n8n.io/workflows/12739), adapted to local Ollama + Postgres.

```markdown
---
name: onboard-client
description: Build or run the agency client-onboarding pipeline in n8n - intake form to welcome email, checklist, CRM record, and kickoff hold. Use when asked to onboard a new client, set up an intake-to-welcome flow, or create onboarding automation.
argument-hint: [client name or "build the onboarding workflow"]
allowed-tools: mcp__n8n-mcp__* Read
---

# Client onboarding pipeline

Builds/edits one n8n workflow on the local stack. Follow the n8n-build validate-first loop (search_nodes -> get_node -> validate_node -> validate_workflow -> create). Do NOT auto-activate.

## Node chain (real node types)
1. Trigger: n8n-nodes-base.formTrigger  (n8n native intake form)
   - LOCALHOST/TUNNEL: client-facing form needs the Cloudflare Tunnel to be reachable. For internal use, the editor form URL is fine.
2. n8n-nodes-base.set — normalize fields: name, email, company, services, budget, notes.
3. Classify tier/urgency: @n8n/n8n-nodes-langchain.chainLlm + lmChatOllama -> qwen3:8b (fast). Output: tier (S/M/L), service tags.
4. Generate checklist + welcome email body: chainLlm + lmChatOllama -> gpt-oss:20b (quality). Persona = warm, professional.
   - OPTIONAL premium: route final styling to the Claude bridge (POST http://host.docker.internal:8787, Bearer) for nuanced client tone.
5. Persist CRM record: n8n-nodes-base.postgres (insert into a `clients` table in the `rag`/app DB) OR n8n-nodes-base.notion if Notion is used.
6. Send welcome email: n8n-nodes-base.gmail OR n8n-nodes-base.emailSend (SMTP). Subject "Welcome to <Agency>, <name>".
7. Owner ping: n8n-nodes-base.telegram (SENDING works on localhost) with tier + score.
8. Optional kickoff hold: n8n-nodes-base.googleCalendar (30-min "Intro Hold", now+48h).
9. Error path: n8n-nodes-base.errorTrigger -> Telegram/email owner alert.

## Model routing
classify (step 3) -> qwen3:8b | drafting (step 4) -> gpt-oss:20b | client-facing polish -> Claude bridge.

## Keys/setup the user must provide
- Gmail OAuth or SMTP creds (email send).
- Telegram bot token + owner chat ID (sending only — no tunnel needed).
- Google Calendar OAuth (only if kickoff hold enabled).
- Cloudflare Tunnel ONLY if the intake form must be public.
- Postgres table `clients` (or a Notion DB).

After build: report workflow ID, confirm it is INACTIVE, list which creds are still unset.
```

---

### NEW 2 — `/client-invoice` (project scope)

Grounded in [#9447 "Generate & Deliver PDF Invoices… HTML to PDF"](https://n8n.io/workflows/4448) but swaps the paid PDF API for **local Gotenberg** ($0). Cited Gotenberg pattern: [n8n template #5149](https://n8n.io/workflows/5149-create-pdf-from-html-with-gotenberg/) / [gotenberg.dev](https://gotenberg.dev/docs/convert-with-chromium/convert-html-to-pdf).

```markdown
---
name: client-invoice
description: Build or run the agency invoice workflow in n8n - line items to branded HTML to PDF (local Gotenberg) to email and archive. Use when asked to create an invoice, set up invoicing automation, or generate a billing PDF.
argument-hint: [client + line items, or "build the invoice workflow"]
allowed-tools: mcp__n8n-mcp__* Read
---

# Invoice -> PDF -> send (local, $0)

Build/edit one n8n workflow via the validate-first loop. Do NOT auto-activate. Branded HTML template + agency legal/tax footer: see reference/invoice-template.md.

## Node chain
1. Trigger: n8n-nodes-base.formTrigger (or executeWorkflowTrigger if called by /onboard-client or Telegram command center).
2. n8n-nodes-base.set / n8n-nodes-base.code — assemble invoice number, dates, line items[], subtotal, VAT (Germany), total.
3. n8n-nodes-base.html — render the branded invoice HTML (use reference/invoice-template.md; inject line-item rows).
4. Convert HTML -> binary index.html (Code or Set, base64) .
5. HTML -> PDF via Gotenberg (HTTP Request):
   - POST http://gotenberg:3000/forms/chromium/convert/html
   - Body: multipart/form-data, field "files" = index.html binary
   - Response: Receive File (PDF binary)
6. Archive: n8n-nodes-base.googleDrive (or postgres/local) — save PDF.
7. Email to client: gmail/emailSend with PDF attached. CC self.
8. Optional: Motion task "Invoice <num> sent — follow up if unpaid 14d" (HTTP Request, X-API-Key).
9. Error path: errorTrigger -> owner alert.

## Model routing
Invoices are deterministic — NO LLM needed for the numbers. Only use gpt-oss:20b if generating a custom cover note; route a client-facing cover note through the Claude bridge for tone.

## Keys/setup the user must provide
- Gotenberg service added to compose.yaml (reachable at gotenberg:3000). [REQUIRED, local]
- Gmail/SMTP creds. Google Drive OAuth (if archiving there).
- Motion API key (optional follow-up task).
- VAT % + agency tax/legal footer in reference/invoice-template.md.

LOCALHOST: entire flow is local/$0 except the email send. No tunnel unless the trigger is a public form.
After build: report ID, confirm INACTIVE, list unset creds.
```

---

### NEW 3 — `/style-doc` (user scope) — Claude-bridge styling

The bridge is the "highest-quality client-facing styling" lever. This skill makes that routing explicit and reusable.

```markdown
---
name: style-doc
description: Polish and brand a drafted document or message to final client-facing quality using the local Claude bridge (or inline if the bridge is off). Use when asked to style, polish, brand, or finalize an email, proposal, report, or any client-facing text.
argument-hint: [paste/point to the draft + intended audience]
---

# Style a document to client-facing quality

Local Ollama writes the DRAFT cheaply; this skill makes the FINAL pass premium. Brand voice + do/don't list: see reference/voice.md.

## Decision
- Bridge available (host service on :8787)? -> route the polish there (best quality, uses the Max subscription, $0 API).
- Bridge off / unreachable? -> polish inline with current model; tell the user the bridge was unavailable.

## Bridge call (when used inside n8n)
HTTP Request -> POST http://host.docker.internal:8787
Header: Authorization: Bearer {{ $env.CLAUDE_BRIDGE_TOKEN }}
Body JSON: { "prompt": "<draft + instructions>", "persona": "agency-principal" }

## Polishing rules (apply regardless of route)
1. Preserve all facts/numbers/links from the draft — never invent.
2. Tighten: cut filler, fix structure, enforce brand voice (reference/voice.md).
3. Match register to audience (prospect vs existing client vs vendor).
4. Output ONLY the finalized text (or HTML if the caller wants Gotenberg PDF next).
5. Flag any factual gaps you could not resolve rather than guessing.

Hand off to Gotenberg (HTML->PDF) or the docx skill only if a file is requested.
```

---

### NEW 4 — `/research-brief` (project scope, **forked**)

Grounded in [#5463 "Research Reports with search + generator + evaluator agents"](https://n8n.io/workflows/5463) and [#10504 "Automate Web Research"](https://n8n.io/workflows/10504), re-pointed to local SearXNG + Ollama. Long, self-contained → fork.

```markdown
---
name: research-brief
description: Produce a cited research brief on a topic using local SearXNG search plus local Ollama synthesis, or build the equivalent n8n research workflow. Use when asked to research a topic, compile a briefing, do competitor/market research, or build a research automation.
argument-hint: [research question or topic]
context: fork
allowed-tools: WebSearch WebFetch mcp__n8n-mcp__* Read
---

# Research brief (local-first, cited)

Two modes — detect from the request.

## Mode A: do the research now (forked, own context)
1. Decompose the question into 3-6 sub-queries.
2. Search: prefer SearXNG (http://searxng:8080/search?q=...&format=json) for $0 local; use WebSearch/WebFetch when broader/live coverage is needed.
3. For top sources: fetch, extract claims, note the URL.
4. Synthesize with local reasoning (gpt-oss:20b-level): structure = Executive summary / Key findings (each cited) / Risks & unknowns / Recommendation.
5. ADVERSARIALLY verify: re-check each load-bearing claim against its source before asserting. Mark anything unverified.
6. Return the brief with an inline Sources list. (Forked: this IS the return value.)

## Mode B: build the n8n research workflow
Chain: chatTrigger/formTrigger -> Set(sub-queries) -> HTTP Request to SearXNG (loop) -> splitInBatches fetch -> chainLlm summarizer (qwen3:8b per-source) -> aggregate -> chainLlm generator (gpt-oss:20b) -> chainLlm/agent evaluator (citation check) -> deliver (email/Telegram/Gotenberg PDF). Follow validate-first; do NOT auto-activate.

## Model routing
per-source extract/summarize -> qwen3:8b | final synthesis -> gpt-oss:20b | premium client-facing version -> Claude bridge.

## Setup
SearXNG running (local, no key). No external key needed for Mode A unless WebSearch is used.
```

---

### NEW 5 — `/daily-brief` (project scope)

Grounded in [#4385 "AI Calendar & Meeting Digest — Daily Brief"](https://n8n.io/workflows/4385) and [#5003 "Daily Email Digest"](https://n8n.io/workflows/5003), localized.

```markdown
---
name: daily-brief
description: Build or run the morning daily-brief workflow in n8n - calendar, inbox, tasks, and news summarized and delivered to Telegram/email. Use when asked for a daily briefing, morning digest, or to build a scheduled summary automation.
argument-hint: ["build it" or "run today's brief"]
allowed-tools: mcp__n8n-mcp__* Read
---

# Daily brief (scheduled, local)

Build/edit one n8n workflow via validate-first loop. Do NOT auto-activate.

## Node chain
1. Trigger: n8n-nodes-base.scheduleTrigger — daily 07:00 Europe/Berlin (cron).
2. Gather (parallel branches, merge):
   - n8n-nodes-base.googleCalendar (today's events + attendees)
   - n8n-nodes-base.gmail (last 24h, key senders; getMany)
   - Tasks: Motion GET /tasks (HTTP Request, X-API-Key) OR postgres tasks table
   - Optional news: HTTP Request to SearXNG, or rssFeedRead feeds
3. n8n-nodes-base.aggregate / code — assemble one context blob.
4. Summarize: chainLlm + lmChatOllama -> gpt-oss:20b. Output sections: Schedule / Inbox needs-reply / Tasks due / FYIs. Markdown.
5. n8n-nodes-base.markdown -> HTML (for email) OR keep markdown for Telegram.
6. Deliver: n8n-nodes-base.telegram (SENDING works on localhost) AND/OR gmail.
7. Error path: errorTrigger -> alert.

## Model routing
extraction/triage of inbox items -> qwen3:8b | the digest write-up -> gpt-oss:20b.

## Keys/setup
- Google Calendar + Gmail OAuth.
- Telegram bot token + your chat ID (sending only; NO tunnel).
- Motion API key (if tasks pulled from Motion).
LOCALHOST: fully local/scheduled; the only external calls are Google + Telegram send. No tunnel.
After build: report ID, confirm INACTIVE, note the cron time.
```

---

### NEW 6 — `/draft-email` (user scope)

Grounded in the inbox-triage pattern from [#5003](https://n8n.io/workflows/5003) and the Telegram-assistant pattern from [#4902](https://n8n.io/workflows/4902).

```markdown
---
name: draft-email
description: Draft a reply or outbound email in the agency voice - classify intent, draft locally, then optionally polish via the Claude bridge. Use when asked to write, reply to, or draft an email or outreach message.
argument-hint: [recipient + context, or the email to reply to]
---

# Draft an email (agency voice)

Voice + signature: see reference/voice.md (shared with /style-doc).

## Steps
1. Classify intent + urgency with qwen3:8b-level reasoning: reply / cold outreach / follow-up / scheduling / decline. Pick the right register.
2. Draft locally (gpt-oss:20b-level): subject + body. Keep it short, specific, one clear ask/CTA. Preserve any quoted facts.
3. CLIENT-FACING? Route the polish to the Claude bridge (POST :8787, Bearer, persona="agency-principal"). Internal/quick? skip.
4. Output subject + body ready to paste. If asked to send via n8n: hand to gmail/emailSend node (sending works on localhost).
5. Never invent commitments, prices, or dates — flag gaps for the user to fill.

## Routing
classify -> qwen3:8b | draft -> gpt-oss:20b | client polish -> Claude bridge.
```

---

### NEW 7 — `/command-center` (project scope) — interactive Telegram hub

Grounded in [#4525 multi-function Telegram bot](https://n8n.io/workflows/4525), [#4457 command bot](https://n8n.io/workflows/4457), [#4902 Telegram assistant](https://n8n.io/workflows/4902). This is the "interactive Telegram command center" the user explicitly wants, with the receiving caveat handled.

```markdown
---
name: command-center
description: Build the interactive Telegram command-center workflow in n8n - a bot that routes slash commands to the agency automations (onboarding, invoice, research, brief, email) and replies. Use when asked to build the Telegram command center, control panel, or interactive bot.
argument-hint: ["build it" or a new command to add]
allowed-tools: mcp__n8n-mcp__* Read
---

# Telegram command center (router)

Build/edit ONE router workflow that dispatches to the other agency workflows. Validate-first; do NOT auto-activate.

## RECEIVING decision (flag to the user before building)
Telegram SENDING works on localhost, but RECEIVING needs ONE of:
  (a) n8n-nodes-base.telegramTrigger + Cloudflare Tunnel (public webhook), OR
  (b) community node n8n-nodes-telegram-bot-gridasov (long-poll, works on pure localhost, ~10k npm dl).
Ask which the user wants; default to (b) for localhost-only.

## Node chain
1. Trigger: telegramTrigger (tunnel) or the gridasov polling trigger (localhost).
2. Auth gate: n8n-nodes-base.if — allow only the owner chat ID. Reject others.
3. n8n-nodes-base.switch — route on command text:
   /onboard, /invoice <client>, /research <topic>, /brief, /email <ctx>, /help, /status
4. Each branch: n8n-nodes-base.executeWorkflow -> the matching workflow (onboard-client, client-invoice, research-brief, daily-brief, draft-email). /status -> docker/health summary or n8n_executions recent.
5. Free-text (no slash): chainLlm + lmChatOllama qwen3:8b to interpret intent -> route, or ask for clarification.
6. Reply: n8n-nodes-base.telegram send result (sending = localhost OK). Use memoryBufferWindow if conversational.
7. Error path: errorTrigger -> owner alert.

## Routing
intent classification of free text -> qwen3:8b | any drafting inside a sub-workflow uses that workflow's own routing.

## Keys/setup
- Telegram bot token (@BotFather) + owner chat ID.
- EITHER Cloudflare Tunnel (option a) OR install n8n-nodes-telegram-bot-gridasov (option b).
- The 5 sub-workflows should exist first (build them, then wire this router by ID).
After build: report ID, confirm INACTIVE, state which receiving option was used.
```

---

### NEW 8 — Persona-bound skills (user scope)

Best-practice note: a persona is *background style*, not a task. So the persona itself is a `user-invocable: false` knowledge skill (like `ollama-route`), and task skills (`/draft-email`, `/style-doc`, `/client-proposal`) reference it. This avoids duplicating voice across every skill. I give one full persona-knowledge skill plus one invocable persona-task skill as the pattern.

**8a — `agency-voice` (background persona knowledge):**

```markdown
---
name: agency-voice
description: The agency's writing persona and brand voice. Background knowledge Claude applies when drafting or styling any client-facing text, email, proposal, or document.
user-invocable: false
---

# Agency voice (persona: principal)

Identity: a sharp, senior solo software-agency principal. Confident, concise, technically credible, warm but never salesy.

## Voice rules
- Lead with the client's outcome, not our process.
- Short sentences. No filler ("just", "simply", "very", "leverage" as verb).
- Concrete over vague: name the deliverable, the date, the number.
- One clear ask per message. End with a specific next step.
- German market: respect formality with new prospects (Sie-equivalent register in English: professional, not chummy) until they go casual.
- Never overpromise; flag assumptions explicitly.

## Do / Don't
DO: "I'll send the staging build Thursday; review and I'll ship Friday."
DON'T: "We will leverage our expertise to potentially deliver value soon."

Other skills (draft-email, style-doc, client-proposal) load this for tone. The Claude bridge call should pass persona="agency-principal" so the host model matches this voice.
```

**8b — `persona-analyst` (invocable persona-task skill, the pattern for "agent personalities"):**

```markdown
---
name: persona-analyst
description: Respond as the data/analyst persona - rigorous, numbers-first, skeptical - for analysis, metrics review, ad-report summaries, or technical assessments. Use when asked to analyze, evaluate numbers, review a report, or think critically as the analyst.
argument-hint: [data/report/question to analyze]
---

# Persona: Analyst

Mindset: skeptical, quantitative, shows the working. NOT the warm client voice — this persona is internal-facing and blunt.

## Behavior
1. State assumptions and data quality FIRST. Call out missing/dirty data.
2. Quantify: percentages, deltas, confidence. No hand-waving.
3. Separate observation from inference from recommendation.
4. Give the single highest-leverage action at the end.
5. If asked to produce a client-facing version, hand off to /style-doc (which applies agency-voice) — do not soften the numbers yourself.

## Routing (if invoked inside n8n)
metric extraction/tagging -> qwen3:8b | multi-point reasoning over the data -> gpt-oss:20b or qwen3.6:35b-a3b when RAM allows | client-facing rewrite -> Claude bridge via /style-doc.
```

This pattern scales: add `persona-pm` (planning/scoping voice), `persona-support` (patient, step-by-step) the same way — each a small invocable skill that defers client polish to `/style-doc` + `agency-voice`.

---

## Part 4 — Quick build order recommendation

1. `agency-voice` + `reference/voice.md` (everything else references it).
2. Expand `n8n-build` reference files (unblocks every workflow build).
3. Add **Gotenberg** to `compose.yaml` (unblocks `/client-invoice`, PDF proposals, research PDFs).
4. Build sub-workflows: `/onboard-client`, `/client-invoice`, `/daily-brief`, `/research-brief`, `/draft-email`.
5. Decide Telegram receiving (gridasov node vs tunnel), then `/command-center` to wire them.
6. `n8n-audit` fork conversion + `/style-doc` + persona skills last.

**Files to create (absolute paths):**
- `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/onboard-client/SKILL.md`
- `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/client-invoice/SKILL.md` (+ `reference/invoice-template.md`)
- `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/research-brief/SKILL.md`
- `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/daily-brief/SKILL.md`
- `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/command-center/SKILL.md`
- `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/n8n-build/reference/{recipes,ai-nodes,services,troubleshooting}.md`
- `/Users/achrafrachek/.claude/skills/style-doc/SKILL.md` (+ `reference/voice.md`)
- `/Users/achrafrachek/.claude/skills/draft-email/SKILL.md`
- `/Users/achrafrachek/.claude/skills/agency-voice/SKILL.md`
- `/Users/achrafrachek/.claude/skills/persona-analyst/SKILL.md`
- Edit: `n8n-audit/SKILL.md` (add `context: fork`, tighten tools), `client-proposal/SKILL.md` (bridge + Gotenberg), `n8n-build/SKILL.md` (append reference nav).

**Key external setup the user must supply:** Gotenberg service in compose (local, $0); Gmail/SMTP creds; Telegram bot token + owner chat ID; Motion API key (`MOTION_API_KEY`); Claude bridge token (`CLAUDE_BRIDGE_TOKEN`); Google Calendar OAuth (daily-brief/onboarding holds); and **Cloudflare Tunnel OR the `n8n-nodes-telegram-bot-gridasov` node** for Telegram receiving + any public-facing form trigger.

**Sources:**
- [Anthropic — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Anthropic — Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Claude Code — Extend Claude with skills](https://code.claude.com/docs/en/skills)
- [Claude Code Subagents vs Skills — AI Architects](https://theaiarchitects.com/blog/claude-code-subagents-vs-skills)
- [Claude Code Skills: A Practical 2026 Guide — Nimbalyst](https://nimbalyst.com/blog/claude-code-skills-guide/)
- n8n templates: [#7781 Onboarding Concierge](https://n8n.io/workflows/7781), [#12739 Consulting Onboarding](https://n8n.io/workflows/12739), [#4448 Onboarding Email](https://n8n.io/workflows/4448), [#9447 Invoice→PDF](https://n8n.io/workflows/9447), [#5149 Gotenberg HTML→PDF](https://n8n.io/workflows/5149-create-pdf-from-html-with-gotenberg/), [#5463 Research Reports](https://n8n.io/workflows/5463), [#10504 Web Research](https://n8n.io/workflows/10504), [#4385 Daily Brief](https://n8n.io/workflows/4385), [#5003 Email Digest](https://n8n.io/workflows/5003), [#4525 Multi-function Telegram bot](https://n8n.io/workflows/4525), [#4902 Telegram AI Assistant](https://n8n.io/workflows/4902)
- [Gotenberg — Convert HTML to PDF](https://gotenberg.dev/docs/convert-with-chromium/convert-html-to-pdf)
- [Motion REST API — Create Task](https://docs.usemotion.com/docs/motion-rest-api/0846d1205f9b3-create-task)
