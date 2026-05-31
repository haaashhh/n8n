That resolves it: the official rate-limits doc explicitly grants individuals API access at the base tier (12 req/min); Enterprise is only for *higher* limits. The "Enterprise-only" claim from the marketing-roundup blog is wrong. I have everything needed. Compiling the final build-ready report.

---

# MOTION (usemotion.com) — 2026 Deep-Dive for the n8n Stack

## TL;DR verdict
Motion has a real, public REST API (`https://api.usemotion.com/v1`, `X-API-Key` header). It is a **task / project / calendar-scheduling API only**. There is **NO documents/notetaker/transcript endpoint** — Motion's AI Docs and AI Notetaker are UI-only features, not exposed via API. There is **no n8n node** (native or community) for Motion — you integrate via the **HTTP Request** node. **Recommendation: use Motion as the TASK + AUTO-SCHEDULING + CALENDAR layer, and do ALL client-facing drafting with Claude (bridge) / gpt-oss:20b, rendered to PDF/DOCX via Gotenberg.** Do not try to make Motion your document drafter — it can't via API, and even in-UI it's a notes/wiki tool, not a templated-deliverable engine.

---

## (1) The API — auth, capabilities, and the documents question

**Base URL:** `https://api.usemotion.com/v1`
**Auth:** header `X-API-Key: <key>` (not Bearer). Key is shown once at creation.
**Smoke test:** `GET https://api.usemotion.com/v1/workspaces` with the header.

**Documented resource groups (the COMPLETE set):**
| Resource | Ops | Endpoint |
|---|---|---|
| Tasks | full CRUD + move + unassign | `/v1/tasks` |
| Recurring tasks | create, delete | `/v1/recurring-tasks` |
| Projects | get, list, create | `/v1/projects` |
| Workspaces | list | `/v1/workspaces` |
| Users | list, me | `/v1/users`, `/v1/users/me` |
| Schedules | get | `/v1/schedules` |
| Statuses | get | `/v1/statuses` |
| Comments | get, create | `/v1/comments` |
| Custom fields | manage on projects/tasks | `/v1/custom-fields` (approx) |

**The documents answer (verified, important):** There is **NO** endpoint for Docs, Documents, AI Notetaker, transcripts, meeting notes, or summaries. I checked the full API nav — those resources do not exist. Motion's "AI Docs" (the `/tasks` `/project` inline-command wiki) and "AI Notetaker" (Meet/Zoom/Teams transcription → suggested tasks) are **product features inside the Motion app only**. You cannot CREATE or DRAFT a document through the Motion API, and you cannot pull notetaker transcripts out via API. So the premise "Motion drafts documents via API" is **false for 2026** — drafting must live elsewhere.

**Key request schemas (build-ready):**

Create task — `POST /v1/tasks`:
- Required: `name` (string), `workspaceId` (string)
- Optional: `projectId`, `description` (GitHub-flavored Markdown), `dueDate` (ISO 8601; required if auto-scheduled), `duration` (`"NONE"` | `"REMINDER"` | minutes int>0), `status`, `priority` (`ASAP`|`HIGH`|`MEDIUM`|`LOW`), `labels` (array<string>), `assigneeId`, `autoScheduled` (object | null)
- `autoScheduled` object: `{ "startDate": "2026-06-01", "deadlineType": "HARD"|"SOFT"|"NONE", "schedule": "Work Hours" }` — `schedule` MUST be `"Work Hours"` when assigning to another user.

List tasks — `GET /v1/tasks` query params: `workspaceId`, `projectId`, `assigneeId`, `status` (array, mutually exclusive with `includeAllStatuses`), `includeAllStatuses` (bool), `label`, `name` (case-insensitive substring), `cursor` (pagination). Response: `{ meta: { nextCursor, pageSize }, tasks: [...] }`.

Create recurring task — `POST /v1/recurring-tasks`: `name`, `workspaceId`, `assigneeId`, plus `frequency` string using Motion's pattern syntax — e.g. `daily_specific_days_[MO,TU,FR]`, `weekly_specific_days_[MO]`, `biweekly_first_week_specific_days_[MO,TU]`, `monthly_first_MO`, `quarterly_first_MO`. Optional `idealTime` (`HH:mm`), `deadlineType`, `schedule` (default `"Work Hours"`).

List projects — `GET /v1/projects?workspaceId=...&cursor=...`. Create project — `POST /v1/projects`.
Get schedules — `GET /v1/schedules` → array of `{ name, timezone, isDefaultTimezone, <weekday>: [{start:"HH:MM", end:"HH:MM"}] }`. Use to read the user's work hours for daily-brief logic.

**Rate limits (verified verbatim):** "The base tier for individuals is **12 requests per minute**. Teams can request up to **120 requests per minute**. For even higher rate limits, please sign up for our enterprise tier." 12/min is tight — batch, cache the daily task pull, and add retry/backoff on the HTTP Request node.

## (2) n8n integration mechanism
- **No native n8n node. No community node.** Confirmed: `search_nodes` returns nothing relevant; npm has no `n8n-nodes-motion` package (only unrelated `motion`/`framer-motion` JS libs). Pipedream and Make have Motion connectors, but n8n does not.
- **Use the HTTP Request node.** Create one **Generic Header Auth credential** in n8n: name `X-API-Key`, value = the key. Reuse it on every Motion HTTP node so the key never sits in node JSON.
- Real precedent: the official n8n template **"Automated task tracking & notifications with Motion and Airtable" (workflow #7383, n8n.io)** drives Motion purely through HTTP Request nodes with the `X-API-Key` header — proof the HTTP-node approach is the established pattern.

## (3) Honest division-of-labor judgment
**Motion is the WRONG tool for drafting onboarding docs / invoices / emails, and the RIGHT tool for the task/calendar/scheduling layer.** Reasons:
1. The API literally cannot create documents — no endpoint exists. Even the in-app AI Docs are a collaborative wiki/notes surface, not a templated-deliverable renderer (no invoice templates, no DOCX/PDF export via API).
2. Your stack already has a far better drafter: **Claude bridge** for client-facing styling/nuance and **gpt-oss:20b** for bulk drafting — both local/$0 and controllable.

**Recommended split:**
- **Drafting / styling →** Claude bridge (client-facing: proposals, onboarding emails, invoices copy) or gpt-oss:20b (internal/bulk). Use qwen3:8b only to classify/extract the trigger data.
- **Rendering →** generate HTML/Markdown, convert to PDF via **Gotenberg** (`/forms/chromium/convert/html`) — already on your roadmap. DOCX via the existing `/client-proposal` skill path.
- **Motion's job →** after a deliverable is drafted/sent, create the **follow-up tasks** ("Send invoice #123 reminder", "Onboarding call prep") with `autoScheduled` so Motion time-blocks them on the calendar; pull the daily task list for the Telegram morning brief; create recurring tasks (weekly invoicing, monthly retainers).
- **Calendar:** Motion auto-schedules tasks onto its own calendar. For raw calendar reads use Google Calendar (you already have that MCP); Motion's value is the *auto-time-blocking of tasks*, not as a generic calendar API.

## (4) Exactly what the user must set up
1. **Plan:** A paid Motion plan — **Pro AI ($19/mo individual)** is sufficient. *Verified:* the official rate-limits doc grants "individuals" API access at the base tier (12 req/min); Enterprise is only needed for *higher* limits. (One marketing-roundup blog wrongly claims "API = Enterprise only" — the official docs contradict it. If after subscribing you don't see the API menu on Pro, contact Motion support; otherwise Pro is the assumed tier.)
2. **Create the key:** Motion app → **Settings → Integrations → API → "+ Create API Key"** → name it `n8n` → **copy immediately (shown once)**.
3. **Store it:** put in `./.env` as `MOTION_API_KEY=...` (chmod 600, git-ignored per CLAUDE.md), then create an n8n **Header Auth** credential (`X-API-Key`). Do not paste the raw key into workflow JSON.
4. **Bootstrap IDs:** run once `GET /v1/workspaces` and `GET /v1/users/me` to capture your `workspaceId` and your user `id`; store as n8n workflow variables — most write calls need `workspaceId`.
5. **Localhost vs tunnel:** All Motion calls are **outbound HTTPS to `api.usemotion.com`** → work **fully on localhost**, no Cloudflare Tunnel needed. (Only inbound Telegram *receiving* needs the tunnel/polling node — unrelated to Motion.)

## (5) Concrete n8n recipes (HTTP Request node configs)

**A. Create an auto-scheduled task** (e.g., after sending an invoice)
- Method `POST`, URL `https://api.usemotion.com/v1/tasks`, Auth = Header Auth cred, Body = JSON:
```json
{
  "name": "Follow up: Invoice #{{ $json.invoiceNo }} — {{ $json.client }}",
  "workspaceId": "{{ $vars.motionWorkspaceId }}",
  "description": "{{ $json.notes }}",
  "dueDate": "{{ $json.dueDateIso }}",
  "duration": 30,
  "priority": "HIGH",
  "labels": ["invoicing"],
  "autoScheduled": { "startDate": "{{ $now.toISODate() }}", "deadlineType": "SOFT", "schedule": "Work Hours" }
}
```

**B. Daily brief — fetch today's tasks** (Schedule Trigger → HTTP → LLM → Telegram)
- `GET https://api.usemotion.com/v1/tasks?workspaceId={{$vars.motionWorkspaceId}}&assigneeId={{$vars.motionUserId}}` (add `includeAllStatuses=false`).
- Paginate on `meta.nextCursor` (loop while present). Then **qwen3:8b** filters/ranks "due today + overdue", **gpt-oss:20b** writes the 3-line brief, send to Telegram. Cache the pull (12 req/min cap).

**C. Recurring agency task** (e.g., weekly invoicing reminder)
- `POST https://api.usemotion.com/v1/recurring-tasks`, body:
```json
{
  "name": "Send weekly invoices",
  "workspaceId": "{{ $vars.motionWorkspaceId }}",
  "assigneeId": "{{ $vars.motionUserId }}",
  "frequency": "weekly_specific_days_[MO]",
  "idealTime": "09:00",
  "deadlineType": "SOFT"
}
```

**D. Create a project on new client onboarding**
- `POST https://api.usemotion.com/v1/projects` with `name`, `workspaceId`, `description` → then loop create the onboarding tasks under `projectId`.

**Error handling for all:** set the HTTP node to retry on `429` with backoff; on `4x` other than 429, route to a Telegram alert.

---

## Sources
- Motion API getting-started / auth: https://docs.usemotion.com/cookbooks/getting-started/
- Create task: https://docs.usemotion.com/api-reference/tasks/post/
- List tasks: https://docs.usemotion.com/api-reference/tasks/list/
- List projects: https://docs.usemotion.com/api-reference/projects/list/
- Schedules: https://docs.usemotion.com/api-reference/schedules/get/
- Recurring tasks / frequency syntax: https://docs.usemotion.com/api-reference/recurring-tasks/post/ and https://docs.usemotion.com/cookbooks/frequency/
- Rate limits (individual API access confirmed): https://docs.usemotion.com/cookbooks/rate-limits/
- API key location (Settings → Integrations → API): https://www.usemotion.com/help/settings/integrations/integrations-how-to-guide
- AI Notetaker / Docs are UI-only (no API): https://help.usemotion.com/motion-ai-notetaker-and-motion-docs/motions-ai-notetaker-overview and https://www.usemotion.com/features/ai-meeting-notetaker
- Pricing tiers (Pro AI $19 / Business AI $29): https://get-alfred.ai/blog/motion-pricing
- Real n8n + Motion HTTP template (#7383): https://n8n.io/workflows/7383-automated-task-tracking-and-notifications-with-motion-and-airtable/
- No n8n node confirmation: n8n-mcp `search_nodes` (none) + npm registry (no `n8n-nodes-motion`); Pipedream/Make connectors exist but not n8n: https://pipedream.com/apps/motion and https://apps.make.com/motion
