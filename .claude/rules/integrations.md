---
description: Credentials & integrations for the local n8n instance — the OAuth-on-localhost constraint and auth choices.
paths:
  - "**/*cred*"
  - "**/*integration*"
  - "workflows/**"
---

# Integrations & credentials

- ~400+ native nodes; otherwise the **HTTP Request node** (any REST API); **community nodes** installable on self-hosted.
- **OAuth2 constraint:** OAuth nodes (Gmail, Google*, HubSpot-OAuth, Salesforce, Dropbox, QuickBooks) need a **public HTTPS callback** — `localhost` is rejected. Two paths:
  - **(preferred)** use token / API-key / Service-Account auth: Notion internal token, Airtable PAT, Google **Service Account** (Drive/Docs/Sheets/Calendar), Slack/Telegram/Discord bot tokens, SendGrid/Stripe keys, GitHub/GitLab PAT, Jira/Linear API tokens, SMTP/IMAP.
  - **(when OAuth is unavoidable)** bring up a Cloudflare Tunnel + owned domain, set `WEBHOOK_URL`/`N8N_HOST` to it, register `<domain>/rest/oauth2-credential/callback` in the provider, do the one-time grant, then return to working at `localhost` (refresh token persists).
- **Meta/Facebook Ads:** no turnkey node → Facebook Graph API node / HTTP Request to the Marketing API with a long-lived token. **Wave:** HTTP Request (GraphQL).
- **MCP:** *MCP Client Tool* node = n8n consumes external MCP tools; *MCP Server Trigger* node = expose a workflow **as** an MCP tool to Claude (Bearer-protected `/mcp/<uuid>`; needs a reachable URL).
- Never inline secrets in workflow JSON — credentials are referenced by ID.
