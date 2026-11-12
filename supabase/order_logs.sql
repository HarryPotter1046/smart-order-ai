-- SmartOrder AI — logging table (source of truth)
-- Paste this into the Supabase SQL Editor and run it once.
--
-- The single dedup mechanism for this demo is the UNIQUE constraint on order_id.
-- The n8n workflow upserts on this constraint (PostgREST: Prefer: resolution=merge-duplicates,
-- on_conflict=order_id), so re-running the same order during a recording take updates the
-- existing row instead of erroring on a duplicate key.

create table if not exists order_logs (
  id            bigint generated always as identity primary key,
  order_id      text not null unique,              -- dedup: same order never logged twice
  customer_name text,
  order_total   numeric,
  decision      text not null,                     -- low_stock | high_value | standard (| parse_error)
  reasoning     text,
  actions       jsonb,                             -- the actions array
  low_stock_items jsonb,                            -- array of product names
  suggested_reorder_quantity integer,
  model_used    text,                              -- e.g. claude-haiku-4-5
  raw_response  text,                              -- Claude's raw output, for debugging
  created_at    timestamptz default now()
);

-- Most-recent-first view is handy when you eyeball the table during the demo.
create index if not exists order_logs_created_at_idx on order_logs (created_at desc);
