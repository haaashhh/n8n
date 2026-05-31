---
name: n8n-export
description: Export all n8n workflows to JSON files for version control. Use when asked to export, snapshot, or git-track n8n workflows.
allowed-tools: mcp__n8n-mcp__* Write Bash(mkdir *) Bash(git *)
---

# Export workflows to JSON (for git)

## Steps
1. `n8n_list_workflows` to get all IDs + names.
2. For each: `n8n_get_workflow` (full JSON).
3. Write each to `workflows/<slugified-name>--<id>.json` (create the dir if missing). One file per workflow, pretty-printed, stable key order so git diffs are clean.
4. Strip/never write credential secrets — n8n workflow JSON references credentials by ID, not value; confirm no inline secrets slipped in.
5. Summarize: count exported, list filenames, and show `git status` so I can commit.

Do not commit automatically. This is the safe, diffable mirror of the live instance.
