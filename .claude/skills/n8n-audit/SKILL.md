---
name: n8n-audit
description: Validate and auto-fix every workflow on the local n8n instance, then run a security/config audit. Use when asked to check, lint, audit, or health-check all n8n workflows.
allowed-tools: mcp__n8n-mcp__*
---

# Audit all n8n workflows + instance

## Steps
1. `n8n_list_workflows` to enumerate everything.
2. For each workflow: `n8n_validate_workflow`. Collect every error/warning.
3. For workflows with fixable errors: propose `n8n_autofix_workflow`, show me the diff, apply only on my confirm, then re-validate.
4. `n8n_audit_instance` for instance-level security/credential/config findings.
5. Recent failures: `n8n_executions` filtered to errors — surface the top recurring failure.

## Report format
- Per-workflow: name + ID + status (clean / warnings / errors) + one-line fix suggestion.
- Instance audit: list findings by severity.
- End with the single highest-priority action.

Do not activate/deactivate or delete anything without explicit confirmation.
