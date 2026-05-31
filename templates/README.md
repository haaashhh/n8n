# Document Templates — fill + render via Gotenberg

Branded, print-tuned HTML/CSS templates the document workflows fill with data and render to PDF using the local **Gotenberg** service (already in `compose.yaml`, reachable from the n8n container at `http://gotenberg:3000`). Everything here runs **localhost, $0** — no external API.

## Files
| File | Used by | Key placeholders |
|---|---|---|
| `invoice.html` | `/client-invoice` workflow (Klaus) | `{{INVOICE_NUMBER}}` `{{ISSUE_DATE}}` `{{DUE_DATE}}` `{{PAYMENT_TERMS}}` `{{CLIENT_NAME}}` `{{LINE_ITEMS_ROWS}}` `{{SUBTOTAL}}` `{{VAT_RATE}}` `{{VAT_AMOUNT}}` `{{TOTAL}}` `{{IBAN}}` `{{BIC}}` `{{LEGAL_FOOTER}}` `{{AGENCY_*}}` `{{LOGO_B64}}` |
| `proposal.html` | `/client-proposal`, `/onboard-client` (Vera + Klaus) | `{{PROPOSAL_TITLE}}` `{{CLIENT_NAME}}` `{{DATE}}` `{{OVERVIEW}}` `{{SCOPE_LIST}}` `{{TIMELINE_ROWS}}` `{{PRICING_ROWS}}` `{{TERMS}}` `{{AGENCY_*}}` `{{LOGO_B64}}` |
| `onboarding.html` | `/onboard-client` (Vera) | `{{CLIENT_FIRST_NAME}}` `{{STEPS_LIST}}` `{{PROJECT_NAME}}` `{{CONTACT_NAME}}` `{{CONTACT_EMAIL}}` `{{KICKOFF_DATE}}` `{{TOOLS}}` `{{CHECKLIST}}` `{{COMMS_POLICY}}` `{{AGENCY_*}}` `{{LOGO_B64}}` |

`{{LINE_ITEMS_ROWS}}`, `{{SCOPE_LIST}}`, `{{TIMELINE_ROWS}}`, `{{PRICING_ROWS}}`, `{{STEPS_LIST}}`, `{{CHECKLIST}}` are repeated HTML fragments — build them in a Set/Code node and inject the string. Example row for the invoice:
`<tr><td>Backend integration</td><td class="right">1</td><td class="right">800.00</td><td class="right">800.00</td></tr>`

## How a workflow fills + renders them
1. **Assemble data** — a Set/Code node builds the field values (and the repeated-row fragments above). Compute money fields deterministically; never let the LLM do invoice arithmetic.
2. **Fill the template** — either:
   - simple: read the `.html` file, string-replace each `{{PLACEHOLDER}}`; or
   - premium: hand the template + data JSON to the `style-doc` skill / Claude bridge to fill *and* polish the prose (returns final HTML). Default styling model is `gpt-oss:20b`; the Claude bridge is an optional upgrade when it is on.
3. **Make `index.html`** — Gotenberg's Chromium route requires the main file be named `index.html`. Convert the HTML string to a binary file named `index.html` (Code/Set node, base64).
4. **Render** — `n8n-nodes-base.httpRequest`:
   - `POST http://gotenberg:3000/forms/chromium/convert/html`
   - `multipart/form-data`; body param `files` = the `index.html` binary (field name MUST be `files`)
   - `printBackground=true` (REQUIRED — otherwise the brand bar / table headers lose their color)
   - `paperWidth=8.27`, `paperHeight=11.7` (A4), margins as desired
   - Response: **Receive File** so n8n captures the returned PDF as binary.
5. **Deliver** — attach the PDF to a Gmail/SMTP send, or `telegram` sendDocument (sending works on localhost).

## Asset rules (Gotenberg / headless Chromium)
- Reference assets by **filename only** or as **base64 data URIs**. The logo uses `src="data:image/png;base64,{{LOGO_B64}}"` — store the base64 string once (n8n variable, env, or a Postgres `agency` row) to keep the HTML fully self-contained.
- No external CSS/JS/fonts/CDN — Gotenberg renders offline. All CSS is inlined in each template's `<head>`.
- Backgrounds survive print because every template sets `* { print-color-adjust: exact; }` and the render sets `printBackground=true`.

## Brand tokens (edit once, in each template's `:root`)
Primary `#1F3A5F`, Accent `#3E7CB1`, Ink `#1A1A1A`, Muted `#6B7280`, Soft-bg `#F7F9FC`, font 'Helvetica Neue'/Arial. A 6px gradient brand bar tops every document.

## Invoice specifics
German invoicing: `{{INVOICE_NUMBER}}` must be gapless/sequential (§14 UStG) — take it only after the PDF renders (see `.claude/skills/client-invoice/reference/invoice-template.md` for the atomic counter SQL and the legal footer). If you are a §19 Kleinunternehmer, drop the VAT row and use the exemption statement instead.

## When NOT to use these (use `.docx` instead)
Fixed, branded, send-as-is PDFs (invoices, proposals, onboarding packets, reports) -> these templates + Gotenberg. Documents the client will redline/edit (negotiated SOWs/contracts) -> the `/client-proposal` skill's `.docx` path.
