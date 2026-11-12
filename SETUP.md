# SmartOrder AI — Setup Runbook

Local demo. n8n in Docker on macOS → Claude decision → Slack alert → Supabase log.
This file walks the workflow node-by-node, then gives a copy-pasteable setup sequence and a
troubleshooting list.

---

## What you'll wire up (3 secrets — 2 n8n credentials + 1 env var)

| Secret | Where it lives | Used by |
| ------ | -------------- | ------- |
| Anthropic API key | **n8n credential** — Header Auth (`x-api-key`) | `Call Claude` |
| Supabase `service_role` key | **n8n credential** — Custom Auth (`apikey` + `Authorization: Bearer`) | `Log to order_logs` |
| Slack Incoming Webhook URL | **Docker env var** `SLACK_WEBHOOK_URL` | the 3 Slack nodes |

> **Why two credentials and one env var?** A generic n8n credential injects *auth*
> (headers/query), not the request *URL*. The Anthropic key (`x-api-key`) and the Supabase
> key (`apikey` + `Authorization`) are **headers**, so they go into n8n credentials cleanly —
> Header Auth holds one header, Custom Auth holds several. The Slack **incoming-webhook URL**
> is itself the secret (there's no header to move), and n8n has no credential type that stores
> a request URL — so it stays a Docker env var referenced as `{{ $env.SLACK_WEBHOOK_URL }}`.
> The Supabase *project URL* lives in the node (it's not a secret — the key is). Either way,
> **nothing secret is hardcoded in the workflow JSON**, so exporting/sharing it leaks nothing.

---

## The workflow, node by node

```
Manual Trigger → Build Order + Inventory → Call Claude → Parse Claude JSON → Route by Decision ─┬─ Slack: Low Stock ──┐
                                                                                                ├─ Slack: High Value ─┤
                                                                                                ├─ (standard) ────────┤→ Log to order_logs → Done
                                                                                                └─ Slack: Parse Error ┘
```

1. **Manual Trigger** — the "Execute Workflow" button. No webhook needed for the recording.

2. **Build Order + Inventory** (Set) — produces 5 fields:
   - `order_id`, `customer_name`, `order_total` — structured fields used to build the
     Supabase log row.
   - `system_prompt` — the **verbatim** SmartOrder decision prompt (also in
     [system-prompt.txt](system-prompt.txt) for reference). Sent as the cached `system` block.
   - `user_message` — the order + inventory + thresholds, in the exact text shape Claude expects.
     Pre-loaded with the headline **low_stock** order. Swap orders using
     [sample-data/orders.md](sample-data/orders.md).

3. **Call Claude** (HTTP Request → `POST https://api.anthropic.com/v1/messages`)
   - Headers: `anthropic-version: 2023-06-01`, `content-type: application/json`,
     `anthropic-beta: prompt-caching-2024-07-31`. `x-api-key` is injected by the Header Auth
     **credential** (not in the JSON).
   - Body: `model: claude-haiku-4-5`, `max_tokens: 400`, `temperature: 0`; `system` is a
     single text block with `cache_control: {type: ephemeral}`; messages are the user
     `user_message` **plus an assistant turn prefilled with `{`**.
   - The system prompt and user message are injected with `JSON.stringify(...)` so any quotes
     / newlines are escaped correctly — guaranteeing a valid request body. *(This is the one
     intentional deviation from pasting the prompt inline in the body; the prompt text and the
     `cache_control` cached block are otherwise exactly as specified.)*

4. **Parse Claude JSON** (Code) — reads `content[0].text`, **prepends the `{`** the prefill
   consumed, strips any stray ```` ``` ```` fences, trims, and `JSON.parse()`s inside a
   try/catch. On success it outputs `decision / reasoning / actions / low_stock_items /
   suggested_reorder_quantity / model_used / raw_response`. On failure it outputs
   `decision: "parse_error"` with the raw text — **it degrades, it does not throw.**

5. **Route by Decision** (Switch) — 4 outputs on the `decision` field: `low_stock`,
   `high_value`, `standard`, `parse_error`.

6. **Slack: Low Stock / High Value / Parse Error** (HTTP Request → `SLACK_WEBHOOK_URL`) —
   post a formatted message (order, decision, reasoning, actions; low-stock adds the items +
   reorder qty). **`standard` skips Slack** and goes straight to logging.

7. **Log to order_logs** (HTTP Request → Supabase PostgREST) — runs on **every** path. POSTs to
   `https://YOUR-PROJECT.supabase.co/rest/v1/order_logs?on_conflict=order_id` with
   `Prefer: resolution=merge-duplicates,return=representation` → a true **upsert** on
   `order_id`, so a double-run during a take updates instead of erroring. The `apikey` +
   `Authorization: Bearer` auth comes from a **Custom Auth credential** (not in the JSON); you
   replace `YOUR-PROJECT` with your Supabase project ref in the node URL.

8. **Done** (NoOp) — tidy success end state.

---

## Setup sequence

### 1. Supabase — create the table

1. Create a free Supabase project (or use an existing one).
2. Open **SQL Editor** → paste the contents of [supabase/order_logs.sql](supabase/order_logs.sql)
   → **Run**.
3. Grab two values from **Project Settings → API** (you'll use them in steps 4 & 5):
   - **Project URL** → e.g. `https://abcd1234.supabase.co` → goes in the **node URL** (not secret).
   - **`service_role` key** (Project API keys) → goes in the **Custom Auth credential** (the secret).

> The `service_role` key bypasses Row Level Security, which is what we want for a server-side
> insert in a local demo. It is a powerful secret — keep it in the n8n credential, never in the
> workflow JSON, and don't commit it.

### 2. Slack — create an Incoming Webhook

1. https://api.slack.com/apps → **Create New App** → *From scratch* → pick your workspace.
2. **Incoming Webhooks** → toggle **On** → **Add New Webhook to Workspace** → choose the
   channel (e.g. `#smartorder-alerts`) → **Allow**.
3. Copy the webhook URL (`https://hooks.slack.com/services/T.../B.../xxxx`) → this is
   `SLACK_WEBHOOK_URL`.

### 3. Start n8n in Docker (Compose)

The repo ships a [docker-compose.yml](docker-compose.yml). Only one secret goes in the
environment — the Slack webhook URL (Anthropic + Supabase keys live in n8n credentials):

```bash
cp .env.example .env          # then paste your Slack webhook URL into .env
docker compose up -d
```

Then open http://localhost:5678. Compose reads `SLACK_WEBHOOK_URL` from your local `.env`
(gitignored) and persists workflows + credentials in `~/.n8n`, so they survive
`docker compose down` / `up`. After changing `.env`, run `docker compose up -d` again to
recreate the container (env vars are read at container start).

<details><summary>Prefer a one-off <code>docker run</code> instead?</summary>

```bash
docker run -it --rm \
  --name n8n \
  -p 5678:5678 \
  -v ~/.n8n:/home/node/.n8n \
  -e N8N_SECURE_COOKIE=false \
  -e N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
  -e SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxxx" \
  docker.n8n.io/n8nio/n8n
```
</details>

### 4. Create the two n8n credentials

**a) Anthropic — Header Auth**
1. **Credentials → New → Header Auth**.
2. **Name** = `x-api-key`, **Value** = your Anthropic API key (`sk-ant-...`).
3. Name the credential `Anthropic API (x-api-key)`. Save.

**b) Supabase — Custom Auth** (holds both headers from one key)
1. **Credentials → New → Custom Auth**.
2. In the **JSON** field, paste this and replace both copies of the key with your
   `service_role` key:
   ```json
   {
     "headers": {
       "apikey": "YOUR_SERVICE_ROLE_KEY",
       "Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"
     }
   }
   ```
3. Name the credential `Supabase service_role`. Save.

### 5. Import the workflow, attach credentials, set the Supabase URL

1. **Workflows → Import from File** → select
   [workflow/smartorder-ai.json](workflow/smartorder-ai.json).
2. **Call Claude** node → **Authentication** is already *Generic Credential Type → Header
   Auth* → pick `Anthropic API (x-api-key)` in the **Credential** dropdown. Save.
3. **Log to order_logs** node →
   - **Authentication** is already *Generic Credential Type → Custom Auth* → pick
     `Supabase service_role` in the **Credential** dropdown.
   - In **URL**, replace `YOUR-PROJECT` with your project ref so it reads
     `https://abcd1234.supabase.co/rest/v1/order_logs?on_conflict=order_id`. Save.
   *(Slack nodes need nothing attached — they read `$env.SLACK_WEBHOOK_URL` directly.)*

### 6. Run the demo

1. The workflow is pre-loaded with the **low_stock** headliner order (`SO-1042`).
2. Click **Execute Workflow**.
3. Watch the nodes light green left to right. Expect:
   - **Call Claude** → a Claude `messages` response.
   - **Parse Claude JSON** → `decision: "low_stock"`,
     `low_stock_items: ["Wireless Mechanical Keyboard"]`, a `suggested_reorder_quantity`
     (~30), and an `actions` array.
   - **Route by Decision** → the `low_stock` output fires.
   - **Slack: Low Stock** → a 🔴 message appears in your channel:
     ```
     🔴 *SmartOrder AI — LOW STOCK*
     *Order:* SO-1042  —  Brightline Studios  ($600)
     *Decision:* low_stock
     *Why:* <one-sentence reason>
     *Low-stock items:* Wireless Mechanical Keyboard
     *Suggested reorder qty:* 30
     *Actions:*
     • slack_alert: ...
     • email_supplier_draft: ...
     ```
   - **Log to order_logs** → a row in Supabase (check **Table Editor → order_logs**).
4. To demo the other branches, swap in **Order 2** (high_value) or **Order 3** (standard) from
   [sample-data/orders.md](sample-data/orders.md) and run again.

---

## Troubleshooting — if X breaks, check Y

| Symptom | Likely cause / fix |
| ------- | ------------------ |
| **Call Claude → 401 / "authentication_error"** | Header Auth credential not selected on the node, or header name isn't exactly `x-api-key`, or the key is wrong. Re-open the node → confirm the credential is attached. |
| **Call Claude → 400 on the `anthropic-beta` header** | Prompt caching is GA now; the beta header is optional. If it ever 400s, delete the `anthropic-beta` header row from the Call Claude node — caching still works without it. |
| **Parse Claude JSON → `decision: "parse_error"`** | Claude returned something non-JSON. Open the node output → read `raw_response`. Confirm `temperature` is `0` and the assistant prefill `"content": "{"` is intact in Call Claude. The flow still logs the error to Supabase and posts a ⚠️ Slack notice — by design. |
| **No Slack message** | `SLACK_WEBHOOK_URL` not set in the container (env vars are read at start — restart after adding), webhook revoked, or you ran a `standard` order (those intentionally don't alert). Open the Slack node → check it resolved a URL. If your n8n blocks `$env`, set `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` or paste the URL into the node. |
| **Slack → `invalid_payload`** | The channel/webhook was deleted, or the message body isn't JSON. Re-create the Incoming Webhook and update the env var. |
| **Supabase → 401 / 403** | The `Supabase service_role` Custom Auth credential isn't attached to the Log node, or the key in it is wrong (must be the **service_role** key, pasted into *both* `apikey` and `Authorization: Bearer` in the credential JSON). |
| **Supabase → 404 / "relation order_logs does not exist"** | DDL not run, or you didn't replace `YOUR-PROJECT` in the Log node URL (or it points at the wrong project). Re-run [order_logs.sql](supabase/order_logs.sql) and fix the URL. |
| **Supabase → 409 / duplicate key on re-run** | The upsert isn't matching. Confirm the URL keeps `?on_conflict=order_id` and the `Prefer: resolution=merge-duplicates` header is present, and that `order_logs.order_id` has its `unique` constraint (it does in the provided DDL). |
| **Prompt caching shows `cache_creation_input_tokens: 0`** | Expected. Haiku 4.5's minimum cacheable prefix is ~4096 tokens and this system prompt is smaller, so caching silently no-ops. Not an error — the demo is unaffected; the cost-savings line just doesn't kick in at this prompt size. |
| **`$env.SLACK_WEBHOOK_URL` is empty in expressions** | The container was started before the env var was added. Stop and re-run the `docker run` (or `docker compose up -d`) with the `-e SLACK_WEBHOOK_URL=...` flag present. |
