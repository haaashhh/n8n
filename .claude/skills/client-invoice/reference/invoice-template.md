# Invoice reference — numbering, schema, legal footer

The branded HTML lives in `/Users/achrafrachek/Desktop/Projects/n8nauto/templates/invoice.html`. This file holds the data-layer details the workflow needs.

## Gap-free invoice numbering (German §14 UStG)
A plain Postgres `SEQUENCE` does NOT roll back — a failed run burns a number and leaves a gap, which German invoicing forbids. Use a **counter table with an atomic `UPDATE ... RETURNING`**, and take the number ONLY after the Gotenberg PDF has rendered successfully.

n8n Postgres node, operation `Execute Query` (DB = `rag`, host `postgres`):
```sql
INSERT INTO invoice_counter (year, last_seq)
VALUES (EXTRACT(YEAR FROM now())::int, 1)
ON CONFLICT (year)
DO UPDATE SET last_seq = invoice_counter.last_seq + 1
RETURNING year || '-' || LPAD(last_seq::text, 4, '0') AS invoice_number;
```
Single atomic statement -> concurrency-safe, per-year reset, zero-padded (`2026-0042`). Read as `{{ $json.invoice_number }}`.

## Schema (run once)
```sql
CREATE TABLE IF NOT EXISTS invoice_counter (
  year     int PRIMARY KEY,
  last_seq int NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS invoices (
  invoice_number text PRIMARY KEY,        -- e.g. '2026-0042'
  client_name    text NOT NULL,
  amount_total   numeric(12,2) NOT NULL,
  vat_amount     numeric(12,2),
  currency       text DEFAULT 'EUR',
  issue_date     date NOT NULL,
  due_date       date,
  status         text DEFAULT 'sent',     -- sent | paid | void
  reminder_stage int DEFAULT 0,           -- dunning stage 0..3
  pdf_path       text,
  created_at     timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS clients (
  id serial PRIMARY KEY, name text, address text, email text,
  vat_id text, iban text, bic text, default_terms text
);
```

## Fill values for templates/invoice.html
- `{{PAYMENT_TERMS}}` default "net 14 days".
- `{{VAT_RATE}}` typically `19` (Germany). `{{VAT_AMOUNT}} = round(SUBTOTAL * VAT_RATE/100, 2)`, `{{TOTAL}} = SUBTOTAL + VAT_AMOUNT`.
- `{{LINE_ITEMS_ROWS}}`: one `<tr><td>{desc}</td><td class="right">{qty}</td><td class="right">{unit}</td><td class="right">{amount}</td></tr>` per item.
- `{{LOGO_B64}}`: base64 PNG of the agency logo (store once).

## Legal footer + §19 Kleinunternehmer
- Standard `{{LEGAL_FOOTER}}` should carry the agency's legal name, address, USt-IdNr / tax number, and a payment-terms line.
- If the agency is a **Kleinunternehmer (§19 UStG)**: set `kleinunternehmer = true`, OMIT the VAT row from the invoice, and put this in the footer instead: "Gemäß § 19 UStG wird keine Umsatzsteuer berechnet." (No VAT charged per §19 UStG.)

## Discipline
Order: assemble content -> render PDF -> take the number (atomic SQL) -> insert the `invoices` row -> send. If anything before the number-grab fails, no number is consumed. The numbers themselves are deterministic — NO LLM does invoice math.
