---
name: style-doc
description: Turn drafted content (invoice data, proposal text, onboarding info, report, or email copy) into a polished, on-brand, self-contained HTML document ready for Gotenberg HTML-to-PDF rendering — or polish text to client-facing quality. Use when asked to style, brand, format, finalize, or "make a PDF-ready" invoice, proposal, onboarding packet, report, or client email. Default to gpt-oss:20b; upgrade to the Claude bridge when it is on.
argument-hint: [paste/point to the draft + doc type + audience]
---

# Style a document to client-facing quality

Local Ollama writes the cheap DRAFT; this skill makes the FINAL pass premium and renders it. Brand HTML/CSS skeletons live in `/Users/achrafrachek/Desktop/Projects/n8nauto/templates/` (invoice.html, proposal.html, onboarding.html) and in `reference/templates.html`.

## Model routing for the polish
- Claude bridge ON (host service at http://host.docker.internal:8787, Bearer token)? -> route the polish/styling there for highest quality.
- Bridge OFF/unreachable (the default)? -> polish with **gpt-oss:20b** and say the bridge was unavailable.
- Never use this for raw drafting (that is the local LLM's job) or for `.docx` deliverables (use the `client-proposal` skill / docx skill).

## HTML output contract (non-negotiable for the PDF path)
- Return ONE complete `<!DOCTYPE html>` document and nothing else. No markdown, no ``` fences, no "Here is your document".
- Inline ALL CSS in a single `<style>` tag in `<head>`. No external stylesheets, no CDN, no remote fonts/JS — Gotenberg renders offline.
- Assets by **filename only** or as **base64 data URIs** (logo: `src="data:image/png;base64,..."`). Never absolute paths, subdirs, or URLs.
- Print-ready: include `@page { size: A4; margin: 18mm 16mm; }` and `* { -webkit-print-color-adjust: exact; print-color-adjust: exact; }` so background colors/bars survive headless Chromium.

## Brand tokens (default — override if the caller supplies others)
Primary `#1F3A5F`, Accent `#3E7CB1`, Ink `#1A1A1A`, Muted `#6B7280`, Soft-bg `#F7F9FC`. Font 'Helvetica Neue', Arial, sans-serif; body 11pt / line-height 1.5. Always render a 6px gradient brand bar at the top: `linear-gradient(90deg, primary, accent)`.

## Procedure
1. Read `doc_type` (invoice | proposal | onboarding | report | email) and the `data` JSON.
2. Pick the matching template (templates/ folder) and fill every `{{placeholder}}`. Compute derived fields (line subtotals, VAT, totals) but never invent numbers not implied by the data.
3. Polish copy: confident, warm, professional agency tone (see the agency voice in docs/personas.md — Vera for client comms, Klaus for invoices). Tighten; never pad. EUR currency, DD.MM.YYYY or "31 May 2026" dates (Europe/Berlin).
4. Validate before returning: exactly one `<html>`, balanced tags, all placeholders replaced, money columns right-aligned, no remote assets, no `<script>` unless required.
5. Output the HTML only.

## Per-type rules
- **invoice**: Rechnungsnummer, issue+due dates, bill-to, itemized table, subtotal/VAT/total, IBAN/BIC + payment ref. If `data.kleinunternehmer` is true, omit VAT and add the §19 UStG exemption note instead.
- **proposal**: cover section + page break, then Overview, Scope, Timeline table, Investment table, Terms.
- **onboarding**: warm welcome header, "what happens next" steps, project-at-a-glance table, "what we need from you" checklist, comms policy.
- **email**: single-column, max-width:600px, inline-styled, email-client-safe (table-based, no flexbox) — different rules from print docs.

## Rendering to PDF (in n8n)
1. Put the final HTML in a field named `html`.
2. Convert it to a binary file named `index.html` (Code/Set, base64).
3. HTTP Request -> POST `http://gotenberg:3000/forms/chromium/convert/html`, multipart/form-data, field `files` = the index.html binary, `printBackground=true`, `paperWidth=8.27` / `paperHeight=11.7` (A4); Response = Receive File (the PDF binary).
4. Email/Telegram-send the PDF (sending works on localhost).

## What NOT to do
Don't return markdown or fenced code. Don't fabricate client data, prices, or legal text. Don't produce `.docx`. Don't link external CSS/JS/fonts.
