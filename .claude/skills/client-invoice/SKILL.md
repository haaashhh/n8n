---
name: client-invoice
description: Build or run the agency invoice workflow in n8n — line items to branded HTML to PDF (local Gotenberg) to email and archive, with German invoicing conventions and gap-free numbering. Use when asked to create an invoice, set up invoicing automation, dunning/payment reminders, or generate a billing PDF.
argument-hint: [client + line items, or "build the invoice workflow"]
allowed-tools: mcp__n8n-mcp__* Read
---

# Invoice -> PDF -> send (local, $0) — persona: Klaus

Klaus's rules apply: precise, firm, German conventions (Rechnungsnummer, net-14, VAT/USt or §19 Kleinunternehmer), amounts always with currency + exact dates, never fabricate numbers. Build/edit ONE n8n workflow via the n8n-build validate-first loop. Do NOT auto-activate. Branded invoice template: `templates/invoice.html` (+ `reference/invoice-template.md` for the legal/tax footer + numbering notes).

## Issue chain (real node types)
1. Trigger: `n8n-nodes-base.formTrigger` (or `executeWorkflowTrigger` when called by onboard-client or the command center).
2. `n8n-nodes-base.set` / `n8n-nodes-base.code` — assemble dates, line items[], subtotal, VAT (Germany), total. Invoices are deterministic — NO LLM for the numbers.
3. `n8n-nodes-base.html` (or fill `templates/invoice.html`) — render branded invoice HTML; inject line-item rows.
4. Convert HTML -> binary `index.html` (Code/Set, base64).
5. HTML -> PDF via Gotenberg (`n8n-nodes-base.httpRequest`): POST `http://gotenberg:3000/forms/chromium/convert/html`, multipart/form-data field `files` = the index.html binary, `printBackground=true`, A4; Response = Receive File (PDF binary).
6. Take the invoice number ONLY now (after the PDF renders) via the atomic counter (see reference/invoice-template.md) and `n8n-nodes-base.postgres` insert into `invoices` (status `sent`, due_date). Gap-free per §14 UStG.
7. Email to client: `n8n-nodes-base.gmail` / `emailSend`, PDF attached, Klaus voice; CC self.
8. Owner ping: `n8n-nodes-base.telegram` (credential id `DBYRKqKOi8hDiJvp`).
9. Optional Motion follow-up task: `httpRequest` POST `https://api.usemotion.com/v1/tasks` (header `X-API-Key`).

## Dunning chain (scheduled)
1. `n8n-nodes-base.scheduleTrigger` daily 09:00 Europe/Berlin.
2. `n8n-nodes-base.postgres` SELECT overdue invoices -> compute stage by days overdue.
3. `n8n-nodes-base.switch` stage 1/2/3 -> `@n8n/n8n-nodes-langchain.chainLlm` (Klaus systemMessage, gpt-oss:20b) drafts the matching reminder; stage-3 sensitive -> Claude bridge if ON.
4. `gmail` send; update `reminder_stage`; `telegram` ping you on stage 3.

## Model routing
Numbers/render -> no LLM. Reminder copy -> gpt-oss:20b. Sensitive client-facing dunning -> Claude bridge if ON, else gpt-oss:20b. Ollama URL `http://host.docker.internal:11434`.

## Keys/setup the user must provide
- Gotenberg already in compose (reachable at `gotenberg:3000`). [local, $0]
- Gmail/SMTP creds. Optional Google Drive OAuth for archiving.
- Motion API key `MOTION_API_KEY` (optional follow-up task).
- VAT % + agency tax/legal footer + IBAN/BIC in reference/invoice-template.md.
- Postgres tables `invoices`, `invoice_counter`, `clients` (DDL in reference/invoice-template.md).

LOCALHOST: entire flow is local/$0 except the email send. No tunnel unless the trigger is a public form. After build: report the workflow ID, confirm INACTIVE, list unset creds.
