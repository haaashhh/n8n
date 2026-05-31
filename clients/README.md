# Clients

Per-client context Claude loads when doing client work. **Real client folders are git-ignored** (this repo is public; client data is confidential). Only `_TEMPLATE/`, this README, and `_registry.example.json` are committed.

- `_TEMPLATE/` — copy to `clients/<slug>/` for a new client (or run `/client-setup <name>`).
- `<slug>/CLAUDE.md` — the client brief (loaded on demand when Claude reads the folder).
- `<slug>/client.json` — structured facts the bridge reads without an LLM.
- `<slug>/brand/` — logo, colors, voice. `history/` — past docs/decisions. `output/` — new drafts.

The Claude bridge runs `claude -p` with **cwd = project root** (loads skills + personas + root CLAUDE.md) **+ `--add-dir clients/<slug>`** (Claude can read everything about the client).
