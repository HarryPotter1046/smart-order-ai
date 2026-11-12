# Sample Data — Inventory + 3 Demo Orders

The **inventory** below is baked into the `Build Order + Inventory` Set node (inside the
`user_message` field). To demo a different decision branch, edit **two things** in that node:

1. The 4 quick fields — `order_id`, `customer_name`, `order_total` — *(used for the
   Supabase log row)*.
2. The `ORDER:` block inside `user_message` — *(what Claude actually sees)*.

Each order below gives you all of it. Copy → paste → click **Execute Workflow**.

> Keep `order_id` distinct per real order, but feel free to **re-run the same `order_id`** —
> the Supabase node upserts on `order_id`, so a repeat run updates the row instead of erroring.
> (Handy for re-takes.)

---

## Inventory (6 products — already in the workflow)

| Product                       | current_stock | low_stock_threshold |
| ----------------------------- | ------------- | ------------------- |
| Wireless Mechanical Keyboard  | 14            | 10                  |
| USB-C Hub (7-in-1)            | 40            | 15                  |
| 4K Webcam                     | 8             | 6                   |
| Noise-Cancelling Headphones   | 22            | 8                   |
| Aluminum Laptop Stand         | 35            | 12                  |
| Ergonomic Mouse               | 18            | 10                  |

Thresholds: `high_value_threshold: 200`.

```json
[
  { "name": "Wireless Mechanical Keyboard", "current_stock": 14, "low_stock_threshold": 10 },
  { "name": "USB-C Hub (7-in-1)", "current_stock": 40, "low_stock_threshold": 15 },
  { "name": "4K Webcam", "current_stock": 8, "low_stock_threshold": 6 },
  { "name": "Noise-Cancelling Headphones", "current_stock": 22, "low_stock_threshold": 8 },
  { "name": "Aluminum Laptop Stand", "current_stock": 35, "low_stock_threshold": 12 },
  { "name": "Ergonomic Mouse", "current_stock": 18, "low_stock_threshold": 10 }
]
```

---

## ⭐ Order 1 — LOW STOCK (the headliner — also > $200, to show the priority rule)

5 keyboards drains stock from 14 → **9** (≤ threshold 10) → `low_stock`. Total is **$600**
(≥ $200), so it's *also* high-value — but `low_stock` wins. **This is the money shot:** the
system protects against a stockout even on a big-ticket order.

Set-node quick fields:

- `order_id` = `SO-1042`
- `customer_name` = `Brightline Studios`
- `order_total` = `600`

`ORDER:` block:

```json
{
  "order_id": "SO-1042",
  "customer_name": "Brightline Studios",
  "items": [
    { "product": "Wireless Mechanical Keyboard", "quantity": 5, "unit_price": 120 }
  ],
  "order_total": 600
}
```

Expected decision: **`low_stock`** · low_stock_items: `["Wireless Mechanical Keyboard"]` ·
suggested_reorder_quantity ≈ **30** (≈ 3× threshold) · Slack 🔴 fires · logged to Supabase.

---

## Order 2 — HIGH VALUE (over $200, healthy stock)

2 headphones @ $180 = **$360** (≥ $200). Stock 22 → 20, comfortably above threshold 8 →
no stock concern → `high_value`.

Set-node quick fields:

- `order_id` = `SO-1043`
- `customer_name` = `Northwind Traders`
- `order_total` = `360`

`ORDER:` block:

```json
{
  "order_id": "SO-1043",
  "customer_name": "Northwind Traders",
  "items": [
    { "product": "Noise-Cancelling Headphones", "quantity": 2, "unit_price": 180 }
  ],
  "order_total": 360
}
```

Expected decision: **`high_value`** · low_stock_items: `[]` · suggested_reorder_quantity:
`null` · Slack 🟢 fires · logged to Supabase.

---

## Order 3 — STANDARD (normal value, healthy stock)

1 mouse ($55) + 1 laptop stand ($40) = **$95** (< $200), both items stay well above
threshold → `standard`. No Slack alert — just logged.

Set-node quick fields:

- `order_id` = `SO-1044`
- `customer_name` = `Jane Patel`
- `order_total` = `95`

`ORDER:` block:

```json
{
  "order_id": "SO-1044",
  "customer_name": "Jane Patel",
  "items": [
    { "product": "Ergonomic Mouse", "quantity": 1, "unit_price": 55 },
    { "product": "Aluminum Laptop Stand", "quantity": 1, "unit_price": 40 }
  ],
  "order_total": 95
}
```

Expected decision: **`standard`** · low_stock_items: `[]` · suggested_reorder_quantity:
`null` · **no Slack** (log only) · logged to Supabase.
