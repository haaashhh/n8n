I have everything I need. Producing the build-ready spec now.

---

# PERSONAL AUTOMATION SUITE — 7 build-ready workflows

All grounded against your actual stack (n8n 2.23.1, Ollama via `host.docker.internal:11434`, SearXNG, Postgres/pgvector, Telegram bot, optional Claude bridge at `:8787`). Node types below are the real `n8n-nodes-*` identifiers confirmed via n8n-mcp. Existing workflow reviewed: `/Users/achrafrachek/Desktop/Projects/n8nauto/workflows/financial-news-digest--vre5v4n2gvyUuPiK.json`.

## The one decision that unblocks half of these: Telegram receiving

Your CLAUDE.md says sending works on localhost but receiving needs a webhook (public URL) OR a long-poll node. **Recommendation: install the community node `n8n-nodes-telegram-polling` (bergi9), or the v7 fork `n8n-nodes-telegram-polling-v7` for current Bot API.** It uses `getUpdates` long-polling (60s timeout) — no Cloudflare Tunnel, no public IP, works 100% on localhost. This is the single highest-leverage setup step: it turns Telegram into a true bidirectional command center without exposing anything. The stock `n8n-nodes-base.telegramTrigger` is webhook-based and will NOT fire on localhost.
- Source: https://github.com/bergi9/n8n-nodes-telegram-polling , https://www.npmjs.com/package/n8n-nodes-telegram-polling-v7
- Install: n8n Settings → Community Nodes → `n8n-nodes-telegram-polling-v7`. Below I write the trigger as **`telegramPollingTrigger`** (community) wherever inbound Telegram is needed, and flag it.

Second cross-cutting setup: **voice/STT**. For voice capture (WF3, WF4) run a local Whisper ASR container (`onerahmet/openai-whisper-asr-webservice`, endpoint `http://whisper:9000/asr`, add to compose) — fully local, $0, matches your ethos. Cited pattern: n8n template 6012 "privacy-focused AI assistant with Telegram, Ollama, and Whisper."

---

## Priority ranking (leverage × delight)

| # | Workflow | Leverage | Why |
|---|---|---|---|
| 1 | **Morning Daily Brief** | Highest | Touches every morning; pure delight; no inbound Telegram needed (send-only) → ships today |
| 2 | **Telegram Command Center / Research Assistant** | Highest | The "interactive" hub you asked for; unlocks WF3/4/6 as sub-flows |
| 3 | **Email Triage + Draft Replies** | High | Saves the most real minutes/day for an agency inbox |
| 4 | **Capture → Motion** (idea/task, text+voice) | High | Frictionless capture is the habit that makes Motion actually work |
| 5 | **Read-it-later / Summarize-a-link** | Medium-High | Quick win, reuses the SearXNG+scrape+summarize pattern |
| 6 | **Content / LinkedIn drafting** | Medium | Agency visibility; Claude-styled output is genuinely good |
| 7 | **Weekly Personal Review** | Medium | Compounding value; closes the loop on tasks/email/content |
| + | **Financial digest upgrades** | (existing) | Cheap, high-ROI improvements below |

---

## WF1 — Morning Daily Brief → Telegram
**Ships first: send-only, zero inbound dependency.** Combines calendar + Motion tasks + weather + top news into one Telegram message.
Inspiration (cited): n8n templates [9819 "Daily morning briefing — Calendar+weather+news"](https://n8n.io/workflows/9819-daily-morning-briefing-with-google-calendar-weather-and-news-to-slack/), [6593 "Personalized weather assistant w/ Calendar+Telegram"](https://n8n.io/workflows/6593-personalized-weather-assistant-with-google-calendar-weatherapi-gemini-and-telegram/), [6952 "Daily calendar summary via Telegram"](https://n8n.io/workflows/6952-daily-calendar-summary-notifications-via-telegram-from-google-calendar/).

- **Trigger:** `n8n-nodes-base.scheduleTrigger` (cron `0 7 * * *`, Europe/Berlin) + `manualTrigger` for testing.
- **Chain (parallel fetch → merge → summarize → send):**
  1. `scheduleTrigger`
  2. **Weather:** `n8n-nodes-base.httpRequest` → Open-Meteo (`https://api.open-meteo.com/v1/forecast?...&daily=...`) — **no API key**, free. (Or OpenWeatherMap if you want the named node.)
  3. **Calendar:** `n8n-nodes-base.googleCalendar` (operation: getAll, today's events) — **needs Google auth, see note**.
  4. **Tasks:** `n8n-nodes-base.httpRequest` → Motion `GET https://api.usemotion.com/v1/tasks?...` (Bearer/API-key header) — today's/overdue tasks.
  5. **News:** `n8n-nodes-base.rssFeedRead` (your curated feeds) OR `httpRequest` → SearXNG `http://searxng:8080/search?q=...&format=json` for topic news. Trim top 5 in a `code` node.
  6. `n8n-nodes-base.merge` (mode: combine) → `n8n-nodes-base.code` to assemble a single prompt.
  7. **Summarize/style:** model routing → **gpt-oss:20b** via `httpRequest` POST `http://host.docker.internal:11434/api/generate` (same pattern as your financial digest) — writes a warm, scannable brief. (Use **qwen3:8b** if you want it instant and RAM is tight that morning.)
  8. `n8n-nodes-base.telegram` (resource: message, sendMessage, your chatId `1816786906`) — **send works on localhost (your existing credential).**
- **Model routing:** assembly = deterministic code; brief prose = gpt-oss:20b (quality) — optionally Claude bridge for the "voice" if you want it to sound like you.
- **Keys/setup you provide:** Motion API key (Motion Settings → API; REST base `https://api.usemotion.com/v1`, [docs](https://docs.usemotion.com/api-reference/tasks/post/)); Google Calendar auth.
- **localhost vs tunnel:** Send-only Telegram = **localhost OK**. Open-Meteo/Motion/RSS/SearXNG = **localhost OK**. **Google Calendar OAuth needs a one-time public HTTPS callback** (per your integrations.md) → either do the one-time Cloudflare Tunnel grant (refresh token then persists at localhost) OR use a Google **Service Account** with calendar shared to it (no tunnel ever). Recommend the Service Account path.

---

## WF2 — Telegram Command Center + Research Assistant
The interactive hub with agent "personalities." One Telegram message → router → the right sub-skill (research / capture / summarize-link / ask) → answer or PDF back.
Inspiration (cited): [8237 "Personal Life Manager w/ Telegram + Google + Voice"](https://n8n.io/workflows/8237-personal-life-manager-with-telegram-google-services-and-voice-enabled-ai/) (34k views), [4457 "AI Telegram Bot Agent: Smart Assistant & Summarizer"](https://n8n.io/workflows/2462-angie-personal-ai-assistant-with-telegram-voice-and-text/), [6012 "privacy-focused assistant w/ Ollama + Whisper"](https://n8n.io/workflows/6012-create-a-privacy-focused-ai-assistant-with-telegram-ollama-and-whisper/).

- **Trigger:** `telegramPollingTrigger` (community long-poll node — REQUIRED for inbound on localhost).
- **Chain:**
  1. `telegramPollingTrigger`
  2. `n8n-nodes-base.if` — is it a voice message? If yes → `n8n-nodes-base.telegram` (file:get to download voice) → `httpRequest` POST to local **Whisper ASR** `http://whisper:9000/asr` → text. Else pass text through.
  3. **Intent router (fast):** `httpRequest` → Ollama **qwen3:8b** with a strict "classify into {research, capture_task, summarize_link, weekly_review, chat} + extract args, return JSON" prompt. (Per your workflows.md, avoid the Ollama tools-agent — do deterministic classify then branch.)
  4. `n8n-nodes-base.switch` on the intent → routes to sub-flows (WF3 research, WF4 capture, WF5 link, WF7 review) via `n8n-nodes-base.executeWorkflow`, or to a "chat" branch.
  5. **Research branch:** `httpRequest` → SearXNG `http://searxng:8080/search?q={{query}}&format=json` → `code` trim top 6 → **gpt-oss:20b** synthesize (cited answer). Optional: send to **Claude bridge** `http://host.docker.internal:8787` (Bearer) for a polished long-form answer.
  6. **PDF option:** if user asks for a PDF, `httpRequest` → **Gotenberg** (`/forms/chromium/convert/html`, to be added to compose) → returns PDF binary → `telegram` sendDocument.
  7. `n8n-nodes-base.telegram` sendMessage / sendDocument back to the user.
- **Agent personalities:** keep a small `code`/Set node mapping `personality → system prompt` (e.g. "Strategist", "Editor", "Researcher"); the user prefixes a command (`/strat`, `/edit`) and you inject that system prompt into the LLM call.
- **Model routing:** classify/route/extract = **qwen3:8b**; synthesis = **gpt-oss:20b**; client-grade styling / nuanced writing = **Claude bridge**; premium reasoning = qwen3.6:35b-a3b only when RAM free.
- **Keys/setup:** Telegram bot token (have it); install the polling community node; add Whisper + Gotenberg services to compose; (optional) Claude bridge token.
- **localhost vs tunnel:** **All localhost** with the polling node + local Whisper + local Gotenberg. **No tunnel needed** — this is the big win vs. webhook-based templates.

---

## WF3 — Email Triage + Draft Replies (Ollama, $0)
Watch inbox → classify → label → draft reply for important mail → optional Telegram alert. Closely mirrors a real, recent **Ollama-based** template.
Inspiration (cited, near-exact match): [13463 "Auto-label Gmail with Ollama AI and draft smart replies"](https://n8n.io/workflows/13463-auto-label-gmail-with-ollama-ai-and-draft-smart-replies/), [14852 "Triage Gmail, draft replies, alert urgent (Claude+Slack)"](https://n8n.io/workflows/14852-triage-gmail-inbox-draft-replies-and-alert-urgent-emails-with-claude-and-slack/).

- **Trigger:** `n8n-nodes-base.gmailTrigger` (polling, every 5–15 min) — **polling trigger works on localhost**; OR `n8n-nodes-base.emailReadImap` (IMAP, fully token-free, no OAuth) if you want to dodge Google OAuth entirely. **IMAP is the lower-friction path here.**
- **Chain:**
  1. Trigger (new unread)
  2. `code` — strip HTML, truncate body.
  3. **Classify (fast):** `httpRequest` → Ollama **qwen3:8b** → JSON `{category: Urgent|ActionRequired|FollowUp|Newsletter|Automated|Spam, priority, summary, needsReply}`.
  4. `n8n-nodes-base.switch` on category.
  5. **Label:** `n8n-nodes-base.gmail` (addLabels) — or skip if IMAP.
  6. **Draft reply (quality):** for ActionRequired/Urgent → **gpt-oss:20b** drafts a reply; for client-facing/nuanced → **Claude bridge** for styling. Save as Gmail **draft** (`gmail` resource: draft, create) — never auto-send.
  7. `n8n-nodes-base.if` Urgent → `telegram` sendMessage alert (localhost OK).
  8. Optional log to Postgres or Google Sheet.
- **Model routing:** classify = qwen3:8b; draft = gpt-oss:20b default; client-facing styling = Claude bridge.
- **Keys/setup:** IMAP creds (host/user/app-password) — **no OAuth, no tunnel**; OR Gmail OAuth (one-time tunnel grant). Telegram bot (have it).
- **localhost vs tunnel:** **IMAP path = fully localhost, recommended.** Gmail node OAuth = one-time tunnel for the grant only.

---

## WF4 — Capture → Motion (text + voice idea/task capture)
Send a Telegram message or voice note → it becomes a structured Motion task. The frictionless capture habit.
Inspiration (cited): [4142 "AI-Powered Telegram Task Assistant w/ Notion"](https://n8n.io/workflows/8237-personal-life-manager-with-telegram-google-services-and-voice-enabled-ai/), [4102 "Manage Calendar with Voice & Text"](https://n8n.io/workflows/4102), Motion create-task [API docs](https://docs.usemotion.com/api-reference/tasks/post/).

- **Trigger:** `telegramPollingTrigger` (inbound) — or invoked as a sub-flow from WF2's router via `executeWorkflow`.
- **Chain:**
  1. Trigger → voice? → Whisper ASR (`http://whisper:9000/asr`) → text (same as WF2).
  2. **Extract (fast):** `httpRequest` → Ollama **qwen3:8b** → JSON `{name, description, dueDate (ISO), priority, label}` from the freeform text.
  3. `n8n-nodes-base.httpRequest` → Motion `POST https://api.usemotion.com/v1/tasks` with header `X-API-Key: <key>`, body `{name, description, dueDate, workspaceId, ...}`. (Motion has **no native n8n node** → HTTP Request, confirmed via search; base `https://api.usemotion.com/v1`.)
  4. `telegram` sendMessage confirmation ("✅ Task created in Motion: …").
- **Model routing:** extraction only = **qwen3:8b** (cheap, instant).
- **Keys/setup:** Motion API key + your `workspaceId` (GET `/v1/workspaces` once to fetch it); Telegram bot; Whisper for voice.
- **localhost vs tunnel:** **All localhost** (polling node + local Whisper + Motion REST over API key). No tunnel.
- **Note on Motion:** Motion's API is solid for task CRUD but rate-limited; it's the right fit for *capture*. For document **drafting** (onboarding/invoices/emails) Motion's "AI docs" aren't API-exposed — so do drafting in n8n+Claude (WF6 / your `/client-proposal` skill) and only push the resulting *task/reminder* to Motion. That's the "better solution" vs trying to drive Motion docs via API.

---

## WF5 — Read-it-later / Summarize-a-link
Drop a URL (Telegram or a saved-bookmark webhook) → clean summary + key points + optional PDF, saved to your RAG store for later recall.
Inspiration (cited): [8210 "Summarize content from URLs, text & PDFs"](https://n8n.io/workflows/8210-summarize-content-from-urls-text-and-pdfs-using-openai/).

- **Trigger:** `telegramPollingTrigger` (inbound URL) or sub-flow from WF2.
- **Chain:**
  1. Trigger → `code` extract URL.
  2. **Fetch:** `n8n-nodes-base.httpRequest` GET the page (or SearXNG if it's a topic, not a URL).
  3. **Extract text:** `n8n-nodes-base.html` (extractHtmlContent) to strip to readable text, truncate in `code`.
  4. **Summarize (quality):** **gpt-oss:20b** → TL;DR + 5 bullets + "why it matters." Client-facing polish → Claude bridge.
  5. **Store for recall (RAG):** `n8n-nodes-base.httpRequest`/embeddings via **qwen3-embedding:0.6b** → insert into Postgres `rag` DB (pgvector) — so you can later ask WF2 "what did I read about X?"
  6. Optional PDF via **Gotenberg** → `telegram` sendDocument; else sendMessage.
- **Model routing:** summary = gpt-oss:20b; embeddings = qwen3-embedding:0.6b; styling = Claude bridge.
- **Keys/setup:** none beyond stack; add Gotenberg if you want PDFs.
- **localhost vs tunnel:** **All localhost.**

---

## WF6 — Content / LinkedIn drafting
Turn a saved article/idea (or a WF5 summary) into a LinkedIn post draft in *your* voice, sent to Telegram for approve/edit before you post.
Inspiration (cited): [5068 "Daily AI news digest → LinkedIn posts (RSS+GPT)"](https://n8n.io/workflows/5068-daily-ai-news-digest-to-linkedin-posts-with-openai-gpt-and-rss-feeds/), [6531 "LinkedIn content creator system"](https://n8n.io/workflows/6531-linkedin-content-creator-system/), [4631 "Auto-generate LinkedIn posts from articles"](https://n8n.io/workflows/4631-auto-generate-linkedin-posts-from-articles-with-dumpling-ai-and-gpt-4o/).

- **Trigger:** `scheduleTrigger` (e.g. pull RSS/your reading list weekly) OR `telegramPollingTrigger` ("/post <topic or URL>") OR sub-flow from WF5.
- **Chain:**
  1. Trigger → gather source (RSS / WF5 summary / SearXNG topic).
  2. **Angle ideation (fast):** qwen3:8b proposes 3 angles.
  3. **Draft (styling):** **Claude bridge** (`http://host.docker.internal:8787`, Bearer) writes the post in your voice — this is exactly the "Claude handles styling" role you wanted. Fallback gpt-oss:20b if bridge off.
  4. `telegram` sendMessage with the draft + inline approve/edit (the polling node supports callback queries).
  5. On approve: keep manual posting, OR push to a scheduler. **LinkedIn's native n8n node requires OAuth (tunnel)**; the $0/no-tunnel path is to deliver the finished post to Telegram and you paste it. (Optional: community `n8n-nodes-zernio`/Late for multi-platform scheduling if you later want auto-publish — adds an external account.)
- **Model routing:** angles = qwen3:8b; final styling = **Claude bridge** (quality), gpt-oss:20b fallback.
- **Keys/setup:** Claude bridge token; nothing else for the deliver-to-Telegram path. LinkedIn auto-post would need OAuth+tunnel — skip for now.
- **localhost vs tunnel:** **Localhost** for draft-and-deliver. Auto-publish to LinkedIn = tunnel/OAuth (defer).

---

## WF7 — Weekly Personal Review
Sunday evening: pull the week's completed Motion tasks + email-triage stats + links read + posts drafted → a reflective review + next-week priorities → Telegram (and archive to RAG).
Inspiration (cited): [7555 "Weekly Gratitude Digest (Notion+Email+Telegram)"](https://n8n.io/workflows/7555), [4420 "Daily/weekly calendar+meeting digest"](https://n8n.io/workflows/4420), [8591 "AI Personal Assistant for Google Tasks"](https://n8n.io/workflows/8591).

- **Trigger:** `scheduleTrigger` (cron `0 18 * * 0`, Europe/Berlin).
- **Chain:**
  1. Schedule
  2. `httpRequest` → Motion `GET /v1/tasks?status=completed` for the week + upcoming.
  3. `httpRequest`/Postgres → pull WF3 triage counts + WF5 links-read log (from your logs/RAG).
  4. `n8n-nodes-base.merge` → `code` assemble.
  5. **Review (quality/reasoning):** **gpt-oss:20b** (or qwen3.6:35b-a3b if RAM free that evening — close LM Studio first) → "What got done, what slipped, 3 priorities for next week, one reflection."
  6. `telegram` sendMessage; optional **Gotenberg** PDF to archive; optional embed into `rag`.
- **Model routing:** reasoning/synthesis = gpt-oss:20b default; qwen3.6:35b-a3b for premium when RAM allows.
- **Keys/setup:** Motion API key; reuses WF3/WF5 logs.
- **localhost vs tunnel:** **All localhost.**

---

## Upgrades to your existing Financial News Digest (`financial-news-digest--vre5v4n2gvyUuPiK.json`)
It currently: manual/schedule(08:00) → RSS CNBC → code (top 8, prompt) → Ollama `qwen3:8b` `/api/generate` → Telegram. Solid base. Concrete upgrades:

1. **Multi-source + dedup.** Add 2–3 more `rssFeedRead` (Reuters, FT/Bloomberg, a markets feed) → `merge` → `code` dedup by title similarity → top 8. One CNBC feed is thin. (Mirrors [12944 "daily market brief from multiple sources"](https://n8n.io/workflows/12944).)
2. **Watchlist relevance pass.** Insert a `qwen3:8b` classify step that tags each item to your tickers/themes and drops irrelevant items *before* the digest prompt — sharper output, fewer tokens.
3. **Upgrade the writer model.** The final digest is client-quality reading; route the summary step to **gpt-oss:20b** (you're already calling `/api/generate`, just change `model`). Keep qwen3:8b only for the relevance tagging. Add `"keep_alive":"5m"` to avoid reload thrash.
4. **Robustness.** Add error branch on the RSS + HTTP nodes (your workflows.md rule), and an `if` to skip sending on empty/failed fetch. Add `continueOnFail` to the Ollama node with a fallback "feed unavailable" message.
5. **Make it interactive.** Add an on-demand path: `telegramPollingTrigger` on `/markets` → same chain → reply. Turns the daily push into an ask-anytime tool (matches WF2).
6. **Optional voice digest.** Pipe the text to a local TTS (Piper/Kokoro container) → `telegram` sendAudio for a listen-on-commute brief (cited pattern: [8143 "Morning briefing podcast"](https://n8n.io/workflows/8143-morning-briefing-podcast-generate-daily-summaries-with-gemini-ai-weather-and-calendar/)).

---

## Consolidated setup checklist (what YOU must provide / install)
- **Telegram inbound:** install community node **`n8n-nodes-telegram-polling-v7`** (Settings → Community Nodes). Unlocks WF2/4/5/6 inbound + financial on-demand. *No tunnel.* (Sending already works.)
- **Local Whisper STT:** add `onerahmet/openai-whisper-asr-webservice` to compose (service `whisper`, port 9000) for voice (WF2/WF4). $0, local.
- **Gotenberg:** add to compose (already flagged in your stack) for HTML→PDF (WF2/WF5/WF7).
- **Motion API key + workspaceId:** Motion Settings → API; base `https://api.usemotion.com/v1`; header `X-API-Key`. (WF1/4/7.) No native node → HTTP Request.
- **Weather:** Open-Meteo (no key) recommended; OpenWeatherMap key optional. (WF1.)
- **Google Calendar:** prefer a **Service Account** (no tunnel) over OAuth; OAuth needs a one-time tunnel grant. (WF1.)
- **Email:** prefer **IMAP** creds (app password, no OAuth/tunnel) over Gmail OAuth. (WF3.)
- **Claude bridge:** turn on host service at `http://host.docker.internal:8787` + Bearer token for client-facing styling (WF2 research polish, WF3 nuanced replies, WF6 LinkedIn voice). Optional but it's your quality lever.
- **RAM discipline:** never run gpt-oss:20b and qwen3.6:35b together; close LM Studio before the 35b path (WF7 premium). Classify steps stay on qwen3:8b.

## What's fully localhost vs needs anything external
- **100% localhost, no tunnel:** WF1 (with Service Account or skip-calendar), WF2, WF3 (IMAP path), WF4, WF5, WF7, financial digest + on-demand. Everything inbound runs on the **polling node**.
- **One-time tunnel only:** Google Calendar OAuth grant (WF1) and Gmail OAuth (WF3) — both avoidable via Service Account / IMAP. LinkedIn auto-publish (WF6) — deferred; deliver-to-Telegram needs nothing.

## Suggested build order
WF1 (today, send-only) → install polling node → WF2 hub → WF3 (IMAP) → WF4 → WF5 → WF6 → WF7, then apply the financial-digest upgrades. Each should go through the validate-first n8n-mcp loop (`validate_node` → `validate_workflow` → `n8n_create_workflow` → `n8n_validate_workflow`) and be left **inactive** for your review per your workflows.md.

Relevant file on disk: `/Users/achrafrachek/Desktop/Projects/n8nauto/workflows/financial-news-digest--vre5v4n2gvyUuPiK.json` (the existing workflow these upgrades target).
