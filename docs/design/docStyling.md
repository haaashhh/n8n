I have everything needed. The Postgres node supports `Execute Query` (for atomic `UPDATE...RETURNING`) and `Insert or Update`. The Cybertec article confirms the key gotcha: sequences don't roll back, so for gap-free invoice numbers a dedicated counter table with an atomic `UPDATE...RETURNING` is the right pattern.

Here is the complete, build-ready design.

---

# Document Generation + Claude-Styling Pipeline — Build-Ready Spec

## Verdict on the approach (read this first)

**Recommended pipeline:** content draft (local LLM, NOT Motion) → **Claude bridge styles into branded HTML** → **Gotenberg renders HTML→PDF** → deliver. This is the right architecture and every piece is confirmed available on your stack.

Two corrections to your assumptions, grounded in what I found:

1. **Motion is the wrong tool for document drafting.** Motion's API ([docs.usemotion.com](https://docs.usemotion.com/)) is a **task/project/calendar** API — create/update/list tasks and projects, AI auto-fills tasks from notes. It has **no document-templating or document-export endpoint**. Its "AI Docs" feature is a UI feature, not an API you can pull styled content out of. Keep Motion for what it's good at (scheduling the *work* of onboarding/invoicing as tasks) and let your **local LLM + Claude bridge** own the document content+styling. Don't put Motion in the document pipeline.

2. **A `claude -p` cost change lands June 15, 2026** (3 weeks out): on subscription plans, `claude -p` / Agent SDK usage starts drawing from a **separate monthly "Agent SDK credit"** distinct from interactive limits ([code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless), and [support.claude.com article 15036540](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan)). Your bridge still works, but budget bridge calls for *client-facing* documents only (styling, nuanced copy) — route bulk/internal drafting to `gpt-oss:20b` to stay within the credit. This reshaped my routing recommendations below.

---

## 1) The pipeline, node-by-node (build-ready)

### 1a. Add Gotenberg to the stack
Add to `compose.yaml` (confirmed by the official n8n template #5149 setup notes and [gotenberg/gotenberg GitHub](https://github.com/gotenberg/gotenberg)):

```yaml
  gotenberg:
    image: gotenberg/gotenberg:8
    restart: always
    # no ports: published — n8n reaches it on the internal Docker network
    # (matches your localhost-only ethos; Gotenberg is never exposed to host/LAN)
    command:
      - "gotenberg"
      - "--chromium-disable-javascript=false"   # keep JS so charts/templating render
      - "--api-timeout=60s"
```
From the n8n container, Gotenberg is reachable at `http://gotenberg:3000`. Memory note for your 38 GB box: Gotenberg spins headless Chromium per request (~150–300 MB transient). It is *not* a resident LLM — negligible against your RAM budget, fine to run alongside `gpt-oss:20b`.

### 1b. Reusable "HTML→PDF" sub-workflow (the core utility)
This is lifted almost verbatim from the **verified** template **"Create PDF from HTML with Gotenberg" by Lucas Peyrin** ([n8n.io/workflows/5149](https://n8n.io/workflows/5149), 1977 views) — the canonical pattern. Build it once, call it from every document workflow.

| # | Node | Type | Config |
|---|------|------|--------|
| 1 | **Create PDF from HTML** | `n8n-nodes-base.executeWorkflowTrigger` (typeVersion 1.1) | `inputSource: jsonExample`, example `{ "html": "<h1>Hi</h1>", "file_name": "invoice-2026-0042" }` |
| 2 | **Create index.html** | `n8n-nodes-base.convertToFile` (1.1) | `operation: toText`, `sourceProperty: html`, `options: { encoding: utf8, fileName: index.html }` — produces binary field `data` |
| 3 | **Convert to PDF (Gotenberg)** | `n8n-nodes-base.httpRequest` (4.2) | see below |

**HTTP Request node (the exact, confirmed-working config):**
- `method: POST`, `url: http://gotenberg:3000/forms/chromium/convert/html`
- `sendBody: true`, `contentType: multipart-form-data`
- Body parameters:
  - `{ name: "files", parameterType: "formBinaryData", inputDataFieldName: "data" }` — sends the `index.html` binary. (The template literally names it "form file"; the form field key Gotenberg requires is `files`.)
  - `{ name: "paperWidth", value: "8.27" }`, `{ name: "paperHeight", value: "11.7" }` (A4 — you're Europe/Berlin)
  - `{ name: "marginTop", value: "0.6" }` + bottom/left/right as desired
  - `{ name: "printBackground", value: "true" }` (REQUIRED or your CSS background colors/bars vanish)
  - `{ name: "scale", value: "1" }`
- Header parameters: `{ name: "Gotenberg-Output-Filename", value: "={{ $('Create PDF from HTML').last().json.file_name }}.pdf" }`
- **Critical option:** set `options.response.response.responseFormat: "file"` (Response → Response Format = "File") so n8n captures the returned PDF as binary, not as a UTF-8 string. The template omits this because older defaults differed; on 2.23.1 set it explicitly.

Gotenberg HTML/CSS rules (confirmed from [gotenberg.dev convert-html-to-pdf](https://gotenberg.dev/docs/convert-with-chromium/convert-html-to-pdf)):
- The main file **must** be named `index.html`.
- All assets live in one flat dir: reference by **filename only** — `<img src="logo.png">`, never `/images/logo.png` or a URL path. To bundle a logo, add a second `formBinaryData` body param pointing at the logo's binary field.
- **Simplest logo approach (recommended): embed the logo as a base64 data URI** directly in the HTML (`<img src="data:image/png;base64,...">`). Avoids multi-file form juggling entirely. Store the base64 string once as an n8n variable or in Postgres.
- Headers/footers: upload `header.html`/`footer.html` as extra files; they render in a **separate Chromium context** (your page CSS does NOT apply to them — style them inline). Use Gotenberg's `{{page}}`/`{{topage}}` tokens for page numbers.

**Output:** binary PDF on field `data`, ready to email or Telegram-send.

### 1c. How a document workflow chains together
Example — **Invoice**:
1. Trigger (Telegram command `/invoice`, or webhook, or schedule)
2. **Postgres** `Execute Query` → atomic next invoice number (see §6)
3. **Postgres** `Select` → client + line-item data
4. **Code/Set** → assemble a content JSON (client, items, totals, dates, VAT)
5. **Claude bridge** (HTTP Request, see §4) → returns final styled HTML string (your template + data, polished)
6. **Execute Sub-Workflow** → the 1b utility → PDF binary
7. **Gmail/SMTP send** (attach PDF) and/or **Telegram sendDocument**
8. **Postgres** `Insert` → log the issued invoice (number, client, amount, date, pdf path)

This works **100% on localhost** — Gotenberg, Postgres, Ollama, and the Claude bridge are all host/Docker-internal. The Telegram *send* works on localhost too. Only **inbound** Telegram (`/invoice` command *receiving*) needs the polling node or a Cloudflare Tunnel (per your stack notes).

---

## 2) Reusable HTML/CSS template skeletons

Drop these into a `templates/` folder (or store in Postgres). They use `{{placeholders}}` you fill in n8n (Set/Code node) **before** sending to Claude, or you hand Claude the raw data + the skeleton and let it fill+polish. All are print-tuned: A4, `@page` margins, `print-color-adjust: exact` so backgrounds survive Gotenberg.

### Shared brand CSS (inline in `<head>` of every template)
```html
<style>
  :root{
    --brand:#1F3A5F; --accent:#3E7CB1; --ink:#1A1A1A; --muted:#6B7280;
    --line:#E5E7EB; --bg-soft:#F7F9FC; --font:'Helvetica Neue',Arial,sans-serif;
  }
  @page{ size:A4; margin:18mm 16mm; }
  *{ box-sizing:border-box; -webkit-print-color-adjust:exact; print-color-adjust:exact; }
  body{ font-family:var(--font); color:var(--ink); font-size:11pt; line-height:1.5; margin:0; }
  h1{ color:var(--brand); font-size:22pt; margin:0 0 4px; }
  h2{ color:var(--brand); font-size:13pt; border-bottom:2px solid var(--accent);
      padding-bottom:4px; margin:24px 0 10px; }
  .muted{ color:var(--muted); } .right{ text-align:right; } .small{ font-size:9pt; }
  .brandbar{ height:6px; background:linear-gradient(90deg,var(--brand),var(--accent)); }
  table{ width:100%; border-collapse:collapse; margin:8px 0; }
  th{ background:var(--brand); color:#fff; text-align:left; padding:8px 10px; font-size:9.5pt;
      text-transform:uppercase; letter-spacing:.04em; }
  td{ padding:8px 10px; border-bottom:1px solid var(--line); vertical-align:top; }
  tr:nth-child(even) td{ background:var(--bg-soft); }
  .totals td{ border:none; padding:4px 10px; }
  .totals .grand{ font-size:13pt; font-weight:700; color:var(--brand);
      border-top:2px solid var(--brand); }
  .badge{ display:inline-block; background:var(--bg-soft); border:1px solid var(--line);
      border-radius:6px; padding:2px 8px; font-size:9pt; color:var(--muted); }
  .header-flex{ display:flex; justify-content:space-between; align-items:flex-start; }
  .logo{ height:40px; }
</style>
```

### INVOICE skeleton
```html
<!DOCTYPE html><html><head><meta charset="utf-8">{{SHARED_CSS}}</head><body>
<div class="brandbar"></div>
<div class="header-flex" style="margin-top:20px">
  <div>
    <img class="logo" src="data:image/png;base64,{{LOGO_B64}}" alt="{{AGENCY_NAME}}">
    <h1>Invoice</h1>
    <div class="muted small">{{AGENCY_NAME}} · {{AGENCY_ADDRESS}}<br>
      USt-IdNr: {{AGENCY_VAT_ID}} · {{AGENCY_EMAIL}}</div>
  </div>
  <div class="right small">
    <div class="badge">No. {{INVOICE_NUMBER}}</div><br><br>
    <strong>Issued:</strong> {{ISSUE_DATE}}<br>
    <strong>Due:</strong> {{DUE_DATE}} ({{PAYMENT_TERMS}})
  </div>
</div>
<h2>Bill To</h2>
<div>{{CLIENT_NAME}}<br><span class="muted">{{CLIENT_ADDRESS}}<br>{{CLIENT_VAT_ID}}</span></div>
<h2>Services</h2>
<table><thead><tr><th>Description</th><th class="right">Qty</th>
  <th class="right">Unit (€)</th><th class="right">Amount (€)</th></tr></thead>
<tbody>{{LINE_ITEMS_ROWS}}</tbody></table>
<table class="totals" style="width:45%;margin-left:auto">
  <tr><td>Subtotal</td><td class="right">€{{SUBTOTAL}}</td></tr>
  <tr><td>VAT ({{VAT_RATE}}%)</td><td class="right">€{{VAT_AMOUNT}}</td></tr>
  <tr><td class="grand">Total Due</td><td class="right grand">€{{TOTAL}}</td></tr>
</table>
<h2>Payment</h2>
<div class="small">IBAN {{IBAN}} · BIC {{BIC}} · Ref: {{INVOICE_NUMBER}}<br>{{NOTES}}</div>
<div class="small muted" style="margin-top:24px">{{LEGAL_FOOTER}}</div>
</body></html>
```
`{{LINE_ITEMS_ROWS}}` = repeated `<tr><td>desc</td><td class="right">1</td><td class="right">800.00</td><td class="right">800.00</td></tr>`. (Germany note: if you use Kleinunternehmer §19 UStG, swap the VAT row for the exemption statement — Claude can branch on a flag.)

### PROPOSAL skeleton
```html
<!DOCTYPE html><html><head><meta charset="utf-8">{{SHARED_CSS}}</head><body>
<div class="brandbar"></div>
<div style="margin-top:60px;text-align:center">
  <img class="logo" style="height:56px" src="data:image/png;base64,{{LOGO_B64}}">
  <h1 style="font-size:30pt;margin-top:30px">{{PROPOSAL_TITLE}}</h1>
  <p class="muted">Prepared for {{CLIENT_NAME}} · {{DATE}}</p>
</div>
<div style="page-break-after:always"></div>
<h2>1. Overview</h2><p>{{OVERVIEW}}</p>
<h2>2. Scope of Work</h2>{{SCOPE_LIST}}
<h2>3. Timeline & Milestones</h2>
<table><thead><tr><th>Phase</th><th>Deliverable</th><th class="right">Timeline</th></tr></thead>
<tbody>{{TIMELINE_ROWS}}</tbody></table>
<h2>4. Investment</h2>
<table><thead><tr><th>Item</th><th class="right">Price (€)</th></tr></thead>
<tbody>{{PRICING_ROWS}}</tbody></table>
<h2>5. Terms & Next Steps</h2><p>{{TERMS}}</p>
<div class="small muted" style="margin-top:40px">{{AGENCY_NAME}} · {{AGENCY_EMAIL}} · {{AGENCY_WEB}}</div>
</body></html>
```
(Mined from the structure of public proposal/quote templates on [n8n.io/workflows](https://n8n.io/workflows) — the Jotform→PDF invoice automation #9447 by verified author Jitesh Dugar confirms the same "generate branded HTML → HTML-to-PDF → email + Drive" pattern this whole design follows.)

### ONBOARDING PACKET skeleton
```html
<!DOCTYPE html><html><head><meta charset="utf-8">{{SHARED_CSS}}</head><body>
<div class="brandbar"></div>
<div style="margin-top:50px">
  <img class="logo" src="data:image/png;base64,{{LOGO_B64}}">
  <h1>Welcome aboard, {{CLIENT_FIRST_NAME}} 👋</h1>
  <p class="muted">Your onboarding guide with {{AGENCY_NAME}}</p>
</div>
<h2>What happens next</h2>{{STEPS_LIST}}
<h2>Your project at a glance</h2>
<table><tbody>
  <tr><td><strong>Project</strong></td><td>{{PROJECT_NAME}}</td></tr>
  <tr><td><strong>Main contact</strong></td><td>{{CONTACT_NAME}} — {{CONTACT_EMAIL}}</td></tr>
  <tr><td><strong>Kickoff</strong></td><td>{{KICKOFF_DATE}}</td></tr>
  <tr><td><strong>Tools we'll use</strong></td><td>{{TOOLS}}</td></tr>
</tbody></table>
<h2>What we need from you</h2>{{CHECKLIST}}
<h2>How we communicate</h2><p>{{COMMS_POLICY}}</p>
<div class="small muted" style="margin-top:30px">Questions? {{AGENCY_EMAIL}}</div>
</body></html>
```

---

## 3) docx skill vs HTML→PDF — when to use which

The official **`docx` skill IS installed** on this machine (`SKILL.md` at `/Users/achrafrachek/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/.../skills/docx/SKILL.md`). It uses `docx-js` + LibreOffice/pandoc and handles TOC, tracked changes, comments, headers/footers. Decision rule:

| Use **HTML→PDF (Gotenberg)** when… | Use the **`docx` skill** when… |
|---|---|
| Final artifact is a **fixed, branded PDF**: invoices, proposals, onboarding packets, ad reports | Client must **edit/redline** the file (contracts, SOWs that get negotiated) |
| You want pixel-perfect CSS branding, gradients, color bars | You need **tracked changes / comments / a TOC** Word-natively |
| It runs **inside n8n** automatically, no human in loop | Deliverable is explicitly "a Word doc" / `.docx` |
| High volume, fully unattended | One-off, high-touch, generated **interactively** in Claude Code |

In practice for your agency: **invoices, proposals, onboarding, email-to-PDF, ad-report summaries → HTML→PDF** (automated in n8n). **SOWs/contracts the client redlines → `docx` skill** (your existing `/client-proposal` skill already produces `.docx` for exactly this). The two coexist: Gotenberg is the n8n-automated path; docx is the interactive Claude Code path.

---

## 4) How n8n calls the Claude bridge (exact)

Your bridge runs `claude -p` headless on the host at `http://host.docker.internal:8787`, Bearer token. n8n node config:

**HTTP Request node** (`n8n-nodes-base.httpRequest`, 4.2):
- `method: POST`, `url: http://host.docker.internal:8787/query`
- Auth: header `Authorization: Bearer {{ $env.CLAUDE_BRIDGE_TOKEN }}` (use a **Header Auth credential** in n8n, not a literal token in the node)
- `sendBody: true`, `contentType: json`
- Body (JSON):
```json
{
  "prompt": "={{ $json.styling_prompt }}",
  "allowedTools": [],
  "options": ["--bare", "--output-format", "json", "--max-turns", "1"]
}
```
- `options.timeout: 120000` (Claude styling takes 15–60s; don't let n8n time out at 30s)
- Response: parse `{{ $json.result }}` — that's the text Claude returned. With `--output-format json` the payload has `result`, `session_id`, `total_cost_usd`, `duration_ms` ([headless docs](https://code.claude.com/docs/en/headless)).

**Bridge-side flags that matter (set these in your bridge script):**
- `--bare` — skips loading hooks/skills/MCP/CLAUDE.md → **faster startup, deterministic output**, and avoids your project context bleeding into client docs. Recommended for the bridge. (Note: bare mode needs `ANTHROPIC_API_KEY` or an apiKeyHelper — if your bridge runs on the Max subscription via OAuth, do NOT use `--bare`; instead pass `--system-prompt` to fully replace the default and keep the OAuth session. Pick one.)
- `--allowedTools ""` (empty) — pure text generation, Claude cannot touch the filesystem. Critical for a network-callable bridge.
- `--max-turns 1` — one shot, no agentic looping → predictable latency/cost.
- Optional: `--output-format json --json-schema '{"type":"object","properties":{"html":{"type":"string"}},"required":["html"]}'` → forces a structured `{ "html": "..." }` in `structured_output`, so n8n never has to strip prose. This is the cleanest contract.

**Prompting Claude to return ONLY styled HTML** (put this in the `prompt` field):
```
You are a document-styling engine for {{AGENCY_NAME}}. 
Return ONLY a complete, self-contained HTML document. No markdown, no code fences, 
no commentary before or after. Inline all CSS in a <style> tag. Use these brand tokens: 
primary #1F3A5F, accent #3E7CB1. Page size A4, print-color-adjust:exact. 
Reference the logo as src="data:image/png;base64,{{LOGO_B64}}". 
Fill this template with the data below and polish the copy for a professional client tone.

TEMPLATE:
<the skeleton from §2>

DATA (JSON):
<the content JSON>
```
The "no code fences / ONLY HTML" instruction + `--json-schema` (if used) guarantees clean output that flows straight into the Gotenberg sub-workflow's `html` field.

**Routing reminder for the bridge:** only client-facing styling/nuance goes here (and watch the **June 15, 2026** Agent SDK credit). Internal drafts, classification, extraction → `qwen3:8b`/`gpt-oss:20b` locally at $0.

---

## 5) Reusable Claude Code SKILL — `style-document`

Save as `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/style-document/SKILL.md`. This is what the **bridge** invokes (or you invoke interactively) to turn content+data into branded HTML.

```markdown
---
name: style-document
description: "Turn raw document content (invoice data, proposal text, onboarding info, email copy) into a polished, on-brand, self-contained HTML document ready for Gotenberg HTML-to-PDF rendering. Use when asked to style, brand, format, or 'make a PDF-ready' invoice, proposal, onboarding packet, report, or client email. Output is ONLY HTML — no prose, no code fences. Do NOT use for .docx deliverables (use the docx skill) or for raw content drafting (that is the local LLM's job)."
---

# Style Document → branded HTML

## Output contract (non-negotiable)
- Return **one complete `<!DOCTYPE html>` document and nothing else**. No markdown, no ``` fences, no explanation.
- Inline ALL CSS in a single `<style>` tag in `<head>`. No external stylesheets, no CDN links.
- Self-contained for Gotenberg: assets referenced by **filename only** or as **base64 data URIs**. Never use absolute paths, subdirectories, or remote URLs for assets.
- Print-ready: include `@page { size: A4; margin: 18mm 16mm; }` and `* { -webkit-print-color-adjust: exact; print-color-adjust: exact; }` so background colors/bars survive headless-Chromium rendering.

## Brand tokens (default — override if the caller supplies others)
- Primary `#1F3A5F`, Accent `#3E7CB1`, Ink `#1A1A1A`, Muted `#6B7280`, Soft-bg `#F7F9FC`
- Font: 'Helvetica Neue', Arial, sans-serif. Body 11pt / line-height 1.5.
- Always render a 6px gradient brand bar at the top: `linear-gradient(90deg, primary, accent)`.

## Inputs the caller provides
1. `doc_type`: invoice | proposal | onboarding | report | email
2. `data`: a JSON object with the content fields
3. (optional) `template`: an HTML skeleton to fill. If absent, build an appropriate layout from the skeletons in `references/templates.html`.
4. (optional) `logo_b64`: base64 PNG for the logo data URI.

## Procedure
1. Pick/structure the layout for `doc_type` (see references/templates.html for invoice, proposal, onboarding skeletons).
2. Fill every placeholder from `data`. Compute derived fields if needed (e.g., line-item subtotals, VAT, totals) — but never invent numbers not implied by the data.
3. Polish copy to a confident, warm, professional agency tone. Tighten; never pad. British/EU spelling, Euro currency, DD.MM.YYYY or "31 May 2026" dates (caller is Europe/Berlin).
4. Validate before returning:
   - exactly one `<html>`, balanced tags, all `{{placeholders}}` replaced
   - tables use `border-collapse:collapse`; money columns right-aligned
   - no `<script>` unless explicitly required; no remote asset URLs
5. Output the HTML. Nothing else.

## Per-type rules
- **invoice**: show invoice number, issue+due dates, bill-to, itemized table, subtotal/VAT/total, IBAN/BIC + payment ref. If `data.kleinunternehmer` is true, omit VAT and add the §19 UStG exemption note instead.
- **proposal**: cover section + page break, then Overview, Scope, Timeline table, Investment table, Terms.
- **onboarding**: warm welcome header, "what happens next" steps, project-at-a-glance table, "what we need from you" checklist, comms policy.
- **email**: a single-column, max-width:600px, inline-styled, email-client-safe HTML (table-based layout, no flexbox) — different rules from print docs.

## What NOT to do
- Don't return markdown or fenced code. Don't add "Here is your document:".
- Don't fabricate client data, prices, or legal text.
- Don't produce a .docx (that's the `docx` skill).
- Don't link external CSS/JS/fonts (Gotenberg renders offline).
```

Add `references/templates.html` next to the SKILL.md containing the three skeletons from §2 — the skill loads them lazily.

---

## 6) Invoice numbering + data (Postgres — recommended over Sheets)

**Use Postgres** (your `rag`-adjacent stack already has `pgvector/pgvector:pg16` running). Reasons: it's already local/$0, transactional, and Google Sheets adds an external dependency + OAuth + rate limits + race conditions for a counter you want to be atomic and gap-free.

**Key gotcha (confirmed):** a plain Postgres `SEQUENCE` **does not roll back** — a failed run still burns the number, leaving gaps ([Cybertec: Sequences vs Invoice numbers](https://www.cybertec-postgresql.com/en/postgresql-sequences-vs-invoice-numbers/)). German invoicing (§14 UStG) wants **gapless, sequential** numbers. So use a **counter table with an atomic `UPDATE ... RETURNING`**, and only commit the number once the PDF actually generates.

**Schema** (run once via Postgres node `Execute Query` or psql):
```sql
CREATE TABLE IF NOT EXISTS invoice_counter (
  year       int PRIMARY KEY,
  last_seq   int NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS invoices (
  invoice_number text PRIMARY KEY,      -- e.g. '2026-0042'
  client_name    text NOT NULL,
  amount_total   numeric(12,2) NOT NULL,
  vat_amount     numeric(12,2),
  currency       text DEFAULT 'EUR',
  issue_date     date NOT NULL,
  due_date       date,
  status         text DEFAULT 'issued',  -- issued | paid | void
  pdf_path       text,
  created_at     timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS clients (
  id serial PRIMARY KEY, name text, address text, email text,
  vat_id text, iban text, bic text, default_terms text
);
```

**Atomic "get next number" — n8n Postgres node, operation `Execute Query`:**
```sql
INSERT INTO invoice_counter (year, last_seq)
VALUES (EXTRACT(YEAR FROM now())::int, 1)
ON CONFLICT (year)
DO UPDATE SET last_seq = invoice_counter.last_seq + 1
RETURNING year || '-' || LPAD(last_seq::text, 4, '0') AS invoice_number;
```
Single atomic statement → concurrency-safe, per-year reset, zero-padded (`2026-0042`). Read it as `{{ $json.invoice_number }}`.

**Gap-free discipline:** call this `INSERT...RETURNING` **only after** the Gotenberg PDF succeeds, OR wrap number-issue + invoice-insert so that if PDF generation fails you `void` rather than skip. Simplest robust order: generate content → generate PDF → *then* take the number → insert the `invoices` row → send. If anything before the number-grab fails, no number is consumed.

**When to prefer Google Sheets instead:** only if *you* want to eyeball/edit the invoice ledger by hand in a spreadsheet UI and never expect concurrent runs. Then use the `Google Sheets` node (`Append` for new rows, a `Lookup`+`Update` for the counter). It's fine for a true solo, low-volume case, but you lose atomicity. My recommendation stays **Postgres**.

---

## What you must provide / set up to BUILD this

1. **Add the `gotenberg` service** to `compose.yaml` (§1a) and `docker compose up -d`. *(localhost-only; no host port.)*
2. **Logo as base64 PNG** — store once (env var, n8n variable, or a `clients`/`agency` row). Keeps the HTML self-contained.
3. **Claude bridge running** at `host.docker.internal:8787` with Bearer token; decide `--bare`+API-key **or** OAuth+`--system-prompt` (not both). Budget bridge calls for client-facing docs given the **June 15 2026** Agent SDK credit change.
4. **n8n credentials:** Postgres (to the `rag` instance or a new `billing` DB — your call), Header-Auth credential for the bridge token, Gmail/SMTP for sending, Telegram bot token (send works on localhost).
5. **Run the schema SQL** (§6) once.
6. **German invoicing fields:** your USt-IdNr (or §19 Kleinunternehmer status), IBAN/BIC, legal footer text — needed to make invoices compliant.
7. **Tunnel decision:** if you want `/invoice`, `/proposal` Telegram *commands* to trigger these (inbound), install `n8n-nodes-telegram-polling` or stand up the Cloudflare Tunnel. Outbound delivery needs neither.

## localhost vs tunnel summary
- **All localhost (no tunnel):** Gotenberg render, Postgres numbering/data, Ollama drafting, Claude bridge styling, Gmail/SMTP send, Telegram *send* (sendDocument). The entire generate→deliver pipeline runs offline-ish at $0 except bridge calls.
- **Needs tunnel/polling node:** only *inbound* Telegram triggers (receiving a command from your phone to start a doc job).

## Files referenced (absolute paths)
- Build the HTML→PDF utility from template structure at `mcp` template id **5149** (`https://n8n.io/workflows/5149`).
- docx skill: `/Users/achrafrachek/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/e57fb14d-df51-4a2a-a6aa-832bd296feae/ff003e9d-53b6-45ad-b959-98172cbfaa07/skills/docx/SKILL.md`
- New skill to create: `/Users/achrafrachek/Desktop/Projects/n8nauto/.claude/skills/style-document/SKILL.md` (+ `references/templates.html`)
- Templates to save: `/Users/achrafrachek/Desktop/Projects/n8nauto/templates/{invoice,proposal,onboarding}.html`
- Compose to edit: `/Users/achrafrachek/Desktop/Projects/n8nauto/compose.yaml`

Sources: [n8n.io/workflows/5149](https://n8n.io/workflows/5149) · [gotenberg.dev convert-html-to-pdf](https://gotenberg.dev/docs/convert-with-chromium/convert-html-to-pdf) · [github.com/gotenberg/gotenberg](https://github.com/gotenberg/gotenberg) · [code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless) · [docs.usemotion.com](https://docs.usemotion.com/) · [cybertec-postgresql.com sequences-vs-invoice-numbers](https://www.cybertec-postgresql.com/en/postgresql-sequences-vs-invoice-numbers/) · n8n template #9447 (Jitesh Dugar, verified) · official `docx` SKILL.md (installed locally).
