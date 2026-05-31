---
name: client-setup
description: Create a new per-client workspace under clients/<slug>/ from the template (CLAUDE.md brief, client.json, brand, history) and register it, so Claude + the bridge can load everything about that client. Use when adding/onboarding a new client to the agency stack.
argument-hint: "[client name]"
allowed-tools: Bash(cp *) Bash(ls *) Read Write Edit
---

# Set up a new client workspace

Create the per-client context folder so Claude (and the n8n Claude bridge) can load everything about: $ARGUMENTS

Steps:
1. **Slug** = the client name lowercased, spaces→dashes (e.g. "Acme GmbH" → `acme-gmbh`).
2. **Copy the template**: `cp -R clients/_TEMPLATE clients/<slug>` — abort if `clients/<slug>` already exists (don't overwrite).
3. **Gather facts** (ask me, or take from $ARGUMENTS / what I provide): industry + size; primary contact + email + decision style; language + formality; active project + budget cap + deadline; day rate + currency + invoice prefix; brand primary/accent colors; voice do's & don'ts. Drop any logo into `clients/<slug>/brand/`.
4. **Fill** `clients/<slug>/CLAUDE.md` (the prose brief) and `clients/<slug>/client.json` (structured facts) with those values, replacing every `{{PLACEHOLDER}}`. Pick the `default_persona` (usually `vera` for client-facing).
5. **Register**: add `{ "slug", "name", "status", "default_persona" }` to `clients/_registry.json`.
6. Leave anything still unknown as `{{PLACEHOLDER}}` and **report** the created paths + what I still need to fill.

Notes:
- The client folder is **git-ignored** (confidential; the repo is public) — never commit real client data.
- The bridge loads it via `--add-dir clients/<slug>` with cwd = project root, so the project skills, the 6 personas, and `templates/` all compose with the client's brief automatically.
- Don't invent prices/dates — leave `[PLACEHOLDER]` for human confirmation (Klaus persona rule).
