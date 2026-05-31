---
name: onboard-client
description: Build or run the agency client-onboarding pipeline in n8n — intake form to welcome email, onboarding packet PDF, CRM record, and kickoff hold. Use when asked to onboard a new client, set up an intake-to-welcome flow, or create onboarding automation.
argument-hint: [client name or "build the onboarding workflow"]
allowed-tools: mcp__n8n-mcp__* Read
---

# Client onboarding pipeline — personas: Vera (welcome) + Klaus (any pricing)

Builds/edits ONE n8n workflow via the n8n-build validate-first loop (search_nodes -> get_node -> validate_node -> validate_workflow -> create). Do NOT auto-activate.

## Node chain (real node types)
1. Trigger: `n8n-nodes-base.formTrigger` (n8n native intake form).
   - LOCALHOST/TUNNEL: a client-facing form needs a Cloudflare Tunnel to be reachable externally; the editor form URL is fine for internal use.
2. `n8n-nodes-base.set` — normalize: name, email, company, services, budget, scope notes.
3. Classify tier/urgency: `@n8n/n8n-nodes-langchain.chainLlm` + `@n8n/n8n-nodes-langchain.lmChatOllama` (qwen3:8b). Output tier (S/M/L), service tags.
4. Generate checklist + welcome copy: `chainLlm` + `lmChatOllama` (gpt-oss:20b), Vera systemMessage (warm, professional; never invent prices/dates — use [PLACEHOLDER]).
   - OPTIONAL premium: route final client-facing polish to the Claude bridge (HTTP Request POST `http://host.docker.internal:8787`, Bearer) — fallback gpt-oss:20b.
5. Onboarding packet PDF (optional): fill `templates/onboarding.html` -> Gotenberg `http://gotenberg:3000/forms/chromium/convert/html` (see the style-doc skill render steps).
6. Persist CRM record: `n8n-nodes-base.postgres` insert into a `clients` table in the `rag` DB.
7. Send welcome email: `n8n-nodes-base.gmail` OR `n8n-nodes-base.emailSend` (SMTP). Subject "Welcome to <Agency>, <name>".
8. Owner ping: `n8n-nodes-base.telegram` (credential id `DBYRKqKOi8hDiJvp`; sending works on localhost) with tier + score.
9. Optional kickoff hold: `n8n-nodes-base.googleCalendar` (30-min "Intro Hold", now+48h).
10. Error path: `n8n-nodes-base.errorTrigger` -> Telegram/email owner alert.

## Model routing
classify (step 3) -> qwen3:8b | drafting (step 4) -> gpt-oss:20b | client-facing polish -> Claude bridge if ON. Embeddings (if RAG context) -> qwen3-embedding:0.6b. Ollama URL `http://host.docker.internal:11434`.

## Keys/setup the user must provide
- Gmail OAuth or SMTP creds (email send).
- Telegram bot credential + owner chat ID (sending only — no tunnel).
- Google Calendar OAuth (only if kickoff hold enabled).
- Cloudflare Tunnel ONLY if the intake form must be public.
- Postgres `clients` table; Gotenberg already in compose (reachable at `gotenberg:3000`).

After build: report the workflow ID, confirm it is INACTIVE, list which creds are still unset.
