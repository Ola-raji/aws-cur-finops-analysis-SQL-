# 02 — CUR primer

A working primer on AWS Cost and Usage Report (CUR) data, oriented toward what a SQL analyst needs to know before writing the first query. Focused, not exhaustive — AWS's own documentation covers the full schema; this document covers the parts that matter for analytical work and the corners where beginners go wrong.

## What CUR is

The Cost and Usage Report is AWS's most granular billing export. Everything visible in the Billing console, in Cost Explorer, in Budgets, and in Cost Anomaly Detection is aggregated from the same underlying data the CUR delivers directly. The CUR is to the AWS billing surface what the general ledger is to a P&L statement — the lowest layer of truth, with one row per metered unit of usage per resource per cost dimension.

If a question can be answered by Cost Explorer, Cost Explorer is usually the right tool. The CUR comes into its own for questions Cost Explorer cannot answer: per-resource unit economics, custom showback logic, cross-account allocation, commitment-coverage what-ifs, and tag-hygiene audits.

## CUR 1.0 vs CUR 2.0

Two generations exist. **CUR 2.0** is the current standard, delivered via the AWS Data Exports service. It uses a stable column set, stores tags as a single JSONB-compatible column, and includes new fields for Savings Plans and split cost allocation. CUR 1.0 (the legacy format, delivered via the Billing console's Reports feature) carries a column per user-defined tag, which makes the schema mutate as tagging strategy evolves.

This project uses CUR 2.0. Everything in this primer reflects 2.0 conventions.

## Delivery shape

A CUR export is an S3 directory tree:

```
s3://<bucket>/<export-name>/data/BILLING_PERIOD=2026-04/<timestamp>-<execId>/
    ├── <export-name>-00001.csv.gz
    └── ...
s3://<bucket>/<export-name>/metadata/BILLING_PERIOD=2026-04/<timestamp>-<execId>/
    └── <export-name>-Manifest.json
```

Two operational details worth knowing:

1. **The manifest is the source of truth for column order and types.** The CSV has no header guarantee across versions. Always parse the manifest first.
2. **CURs are rewritten in place within a billing period.** AWS re-delivers the entire month's data each time charges finalise, typically once or twice a day. The file you have today may differ from the file you have tomorrow for the same billing period. **Production load pipelines drop and reload the billing period — they do not incrementally append.**

## The column families

The 127 columns in a CUR group by prefix into about ten families:

| Prefix | Purpose |
|---|---|
| `identity_*` | Row-level identifiers |
| `bill_*` | Which bill this row belongs to |
| `line_item_*` | The meat — what was used, when, what it cost |
| `product_*` | Product/service metadata |
| `pricing_*` | How the price was computed |
| `reservation_*` | Reserved Instance fields (mostly null in non-RI accounts) |
| `savings_plan_*` | Savings Plan fields |
| `discount_*` | Enterprise Discount Program fields |
| `split_line_item_*` | Split cost allocation for shared resources |
| `resource_tags`, `tags` | User-defined tags as JSON |
| `cost_category` | User-defined cost categories |

You can ignore `reservation_*` and `savings_plan_*` for accounts without commitments. The two tag columns are redundant — `resource_tags` uses concise keys (`user_environment`), `tags` uses verbose keys (`resourceTags/user:Environment`). Standardising on `resource_tags` is cleaner.

## The single most important column: `line_item_line_item_type`

This is the column that breaks more CUR queries than any other. Every row has a type:

| Type | Meaning |
|---|---|
| `Usage` | Actual consumption at on-demand rates |
| `Credit` | Offsets — Free Tier, promotional credits, refunds |
| `Tax` | Sales/VAT/GST rows |
| `RIFee` | Reserved Instance recurring fees |
| `SavingsPlanCoveredUsage` | Usage covered by a Savings Plan |
| `SavingsPlanRecurringFee` | The SP commitment fee itself |
| `DiscountedUsage` | Usage discounted by an RI |
| `Refund`, `Fee`, `BundledDiscount` | Various adjustments |

**Cost queries that omit a `line_item_type` filter or grouping produce wrong answers, silently.** Credit rows have negative cost; summing them with Usage rows nets to invoice cost, which is sometimes what you want and sometimes catastrophically not. Tax rows can have zero cost and exist purely for audit. Well-formed CUR queries either filter to one type explicitly or group by the column.

## Five cost columns. Pick the right one.

CUR 2.0 carries five distinct cost figures per row. Summing the wrong one returns the wrong answer with full confidence:

| Column | What it represents |
|---|---|
| `line_item_unblended_cost` | The actual cost charged to this account for this line item. **Default for single-account analysis.** |
| `line_item_blended_cost` | Blended RI rate across the AWS Organization. Equal to unblended in single-account setups. |
| `line_item_net_unblended_cost` | Unblended cost after credits, discounts, and EDP. Often NULL for accounts without discount programs. |
| `pricing_public_on_demand_cost` | What this usage would cost at AWS list prices. The "economic" cost. |
| Amortized cost (derived) | Spreads RI/SP upfront fees across the commitment period. |

For this project, **`pricing_public_on_demand_cost` is the primary signal** because the account is Free-Tier-covered and `unblended_cost` nets to zero. The on-demand column gives an honest view of what the workload would cost at scale. This decision and its rationale are detailed in [`05-methodology.md`](05-methodology.md).

## Tags

Tags arrive as a JSON object per row inside `resource_tags`:

```json
{"user_project":"ha-web-portal","user_environment":"production",
 "user_cost_center":"CC-1001","user_workload":"web-tier",
 "user_owner":"platform-team","user_criticality":"high"}
```

**Tag coverage is rarely 100%, for three reasons that beginners frequently misdiagnose:**

1. **Some line items are structurally untaggable.** Public IPv4 charges, CloudWatch dashboards, KMS API requests, free-tier CloudTrail event records — these don't have a parent resource to inherit tags from. AWS does not support tagging them. They will never appear tagged in the CUR no matter how thorough the tagging strategy.

2. **Sub-line-items don't always inherit parent tags.** An EC2 instance produces a `BoxUsage` line that inherits the instance's tags, plus separate lines for EBS volumes, data transfer, and snapshots that often don't. The same applies to ALB, RDS, and S3. The same physical resource appears in the CUR as both tagged and untagged rows.

3. **Cost allocation tags must be activated in the Billing console.** This is the most common cause of "I tagged everything and nothing shows up." Tags exist in the AWS APIs as soon as you set them, but they don't appear in the CUR until you go to Billing → Cost allocation tags and click Activate on each key. **Activation is prospective only — historical CUR data is not backfilled.**

This project handles all three failure modes via an enrichment bridge documented in [`03-data-model.md`](03-data-model.md) and surfaced as a FinOps finding in [`04-findings.md`](04-findings.md).

## Time and timezones

The export is configured as daily granularity, but `line_item_usage_start_date` and `_end_date` may carry hourly precision when AWS recorded the underlying usage that way. All timestamps are UTC. Aggregation queries should truncate to date with explicit timezone discipline:

```sql
(line_item_usage_start_date AT TIME ZONE 'UTC')::date AS usage_date
```

Storing as `TIMESTAMPTZ` and presenting in a local timezone via a view layer is the cleanest pattern.

## What's specifically unusual about this dataset

The CUR sample shipped in this repository has a few characteristics worth flagging up front so a reader of the queries understands certain choices:

- **Single AWS account, no Organization.** Blended cost equals unblended cost.
- **No Reserved Instances, no Savings Plans.** All usage is on-demand. The `reservation_*` and `savings_plan_*` columns are entirely null.
- **Free Tier covers 100% of charges.** Hence the on-demand-cost-first approach.
- **Partial month (16 of 30 days).** Month-to-date projections scale `(days_elapsed / days_in_month)`.
- **Account anonymised.** The real 12-digit account ID and payer name are substituted in the sample. The substitution is documented in `scripts/anonymise.py`.

These are real-world conditions. The model and queries in this project are written to be portable to fuller datasets — multi-account, with commitment discounts, with longer history — without structural changes.
