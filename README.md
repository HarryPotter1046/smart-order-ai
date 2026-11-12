# SmartOrder AI

A small, recordable demo: an **n8n** workflow processes an e-commerce order, asks **Claude**
for one structured decision, fires a **Slack** alert, and logs everything to **Supabase**.
Built to look clean on a Loom, build fast, and cost almost nothing to run.

This repo is the **automation core only** — the n8n workflow + the Claude decision logic.
The Next.js dashboard is a separate build and is **not** here.

## How it works

```
Manual Trigger → Set (order + inventory) → HTTP → Claude → Code (parse JSON)
   → Switch (low_stock / high_value / standard / parse_error)
   → Slack alert (skipped for standard)  → Supabase upsert  → Done
```

Claude classifies each order into exactly one decision using a strict priority —
**`low_stock` > `high_value` > `standard`** — so a big order that depletes stock is flagged
for the stockout risk, not just the dollar value. That priority is the headline moment of the
demo.

Key locked choices: model `claude-haiku-4-5`, `temperature: 0` (repeatable takes),
`max_tokens: 400`, cached `system` block, and the assistant-prefill-`{` trick (the parser
prepends the `{` back). Secrets never live in the workflow JSON.

## Files

| Path | What |
| ---- | ---- |
| [docker-compose.yml](docker-compose.yml) + [.env.example](.env.example) | Run n8n locally: `cp .env.example .env` → `docker compose up -d`. |
| [workflow/smartorder-ai.json](workflow/smartorder-ai.json) | The importable n8n workflow (10 nodes). |
| [supabase/order_logs.sql](supabase/order_logs.sql) | `order_logs` table DDL — paste into the Supabase SQL editor. |
| [system-prompt.txt](system-prompt.txt) | The verbatim Claude decision prompt (also embedded in the Set node). |
| [sample-data/orders.md](sample-data/orders.md) | Inventory + 3 ready-to-paste demo orders (one per branch). |
| [SETUP.md](SETUP.md) | Node-by-node walkthrough, setup runbook, troubleshooting. |

## Quick start

See **[SETUP.md](SETUP.md)**. In short: run the DDL in Supabase → create a Slack Incoming
Webhook → `cp .env.example .env` (paste the webhook URL) and `docker compose up -d` → create
two n8n credentials (Anthropic key as **Header Auth**, Supabase `service_role` key as **Custom
Auth**) → import the workflow → attach both credentials and set your Supabase project URL on
the Log node → **Execute Workflow**.

## A note on prompt caching

The request sends the system prompt as a `cache_control: {type: ephemeral}` block. On
`claude-haiku-4-5` the minimum cacheable prefix is ~4096 tokens, and this system prompt is
smaller — so caching **silently no-ops** here (you'll see `cache_creation_input_tokens: 0`).
That's expected and harmless; the demo runs fine. The block is left in place because it's the
right pattern and costs nothing — it'll start paying off the moment the prompt grows past the
threshold.

---

## Later / productionization — NOT built here

Deliberately out of scope for this demo. Listed so they're not forgotten, **not implemented**:

- **Tool-use / structured outputs** instead of the assistant-prefill JSON trick (stronger schema
  guarantees than prefill + parse).
- **Idempotency/dedup beyond the single `order_id` unique constraint** (event IDs, exactly-once).
- **Rate limiting + retry/backoff** on the Claude, Slack, and Supabase HTTP calls.
- **Monitoring & alerting** on workflow failures (dead-letter path, error workflow).
- **Real webhook ingestion + auth** (replace the Manual Trigger; verify Shopify/Stripe signatures).
- **Secrets management & multi-environment config** (vault-backed creds, staging vs prod) and a
  real deployment (VPS / n8n Cloud) instead of local Docker.
