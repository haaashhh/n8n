---
name: n8n-backup
description: Run the n8n backup that mirrors the latest set to the external SSD. Use when asked to back up n8n or mirror backups to the SSD.
disable-model-invocation: true
allowed-tools: Bash(./backup.sh) Bash(ls *) Bash(df *)
---

# Run n8n backup (SSD mirror)

Context: a weekly launchd job (`com.user.n8n-backup`) already writes internal backups to
`~/Library/Application Support/n8n-local/backups` (background agents can't write the SSD — macOS TCC).
`./backup.sh` is a thin wrapper that execs the real script there and ALSO mirrors the latest set to the external SSD.

## Steps
1. Confirm the external SSD is mounted (the script targets it). If not, tell me — do not silently skip the mirror.
2. Run `./backup.sh` from ~/Desktop/Projects/n8nauto.
3. List the newest backup set and confirm it includes the n8n_data volume tar (it holds the N8N_ENCRYPTION_KEY + binary data) and a valid PostgreSQL dump.
4. Remind me: keep an encrypted OFFSITE copy, and never change N8N_ENCRYPTION_KEY or saved credentials become undecryptable.

Report what was written and where. Never print the encryption key or .env contents.
