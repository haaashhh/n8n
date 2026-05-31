---
name: daily-brief
description: Build or run the morning daily-brief workflow in n8n — calendar, inbox, tasks due, overdue invoices, and news summarized into one concise Telegram/email message. Use when asked for a daily briefing, morning digest, chief-of-staff standup, or to build a scheduled summary automation.
argument-hint: ["build it" or "run today's brief"]
allowed-tools: mcp__n8n-mcp__* Read
---

# Daily brief (scheduled, local) — persona: Cosmo (with Klaus + Mira sections)

Cosmo's rules apply: extremely concise, mobile-readable, lead with what matters, no preamble, Europe/Berlin time. Build/edit ONE n8n workflow via the n8n-build validate-first loop. Do NOT auto-activate.

## Node chain (real node types)
1. Trigger: `n8n-nodes-base.scheduleTrigger` — daily 07:30 Europe/Berlin (cron).
2. Gather (parallel branches, then `n8n-nodes-base.merge`):
   - `n8n-nodes-base.googleCalendar` (getAll, today's events + attendees).
   - `n8n-nodes-base.gmail` (last 24h, key senders; getMany) — for inbox needs-reply.
   - Tasks due: `n8n-nodes-base.httpRequest` Motion `GET /v1/tasks` (header `X-API-Key`) OR a `n8n-nodes-base.postgres` tasks query.
   - Overdue invoices (Klaus section): `n8n-nodes-base.postgres` SELECT from `invoices` WHERE status unpaid AND due_date < today, with amounts.
   - News (Mira section): reuse the Financial News Digest via `n8n-nodes-base.executeWorkflow`, or `n8n-nodes-base.rssFeedRead`.
3. `n8n-nodes-base.aggregate` / `code` — assemble one context blob.
4. `@n8n/n8n-nodes-langchain.chainLlm` + `@n8n/n8n-nodes-langchain.lmChatOllama` (gpt-oss:20b), Cosmo systemMessage — compose: Schedule / Inbox needs-reply / Tasks due / Money (overdue €) / 3 suggested priorities. Markdown.
5. Deliver: `n8n-nodes-base.telegram` sendMessage (sending works on localhost) and/or `gmail`.
6. Error path: `n8n-nodes-base.errorTrigger` -> Telegram owner alert.

## Model routing
inbox/item triage -> qwen3:8b | the digest write-up -> gpt-oss:20b. No Claude bridge (internal-only).

## Keys/setup the user must provide
- Google Calendar + Gmail OAuth2 (only the parts you enable).
- Telegram bot credential (id `DBYRKqKOi8hDiJvp`) + your chat ID — sending only, NO tunnel.
- Motion API key `MOTION_API_KEY` (only if tasks pulled from Motion).
- Ollama credential URL `http://host.docker.internal:11434`.

LOCALHOST: fully scheduled/local; only external calls are Google + Telegram send. No tunnel. After build: report the workflow ID, confirm INACTIVE, note the cron time.
