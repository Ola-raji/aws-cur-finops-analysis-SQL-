# 05 — Methodology

The decisions made in building this analysis, the alternatives considered, and the reasoning that selected one over the other. This document exists because **a portfolio piece is judged as much on the quality of its choices as on the correctness of its output.** Where a decision was non-obvious, this document records why.

## On choosing PostgreSQL

PostgreSQL was specified by the project brief, but it is also the right tool for this work for reasons worth naming. CUR data is structurally relational with deeply nested JSON in two columns (`resource_tags`, `cost_category`). Postgres handles both natively — JSONB with GIN indexing makes tag queries fast, and the relational core handles the dimensional model cleanly. SQLite would lack the JSONB ergonomics; DuckDB would handle the analytical workload well but lacks the index pattern variety we use in the model layer; a cloud warehouse (Snowflake, BigQuery, Redshift) would be overkill for a 1,882-row dataset. Postgres is the right size for the problem.

## On the cost column choice

CUR 2.0 carries five distinct cost figures per row (see [`02-cur-primer.md`](02-cur-primer.md)). The choice of which to foreground in analysis is the most consequential methodological decision in the project.

The realised invoice cost (`unblended_cost` summed across all line item types) is **zero** in this dataset because the account is fully Free-Tier-covered. Reporting on $0 produces nothing useful. The available alternatives:

| Option | Considered? | Outcome |
|---|---|---|
| Report on $0 invoice cost only | Yes | Rejected. No analytical signal. |
| Use `unblended_cost` filtered to Usage rows only | Yes | Rejected. Conceptually incoherent — strips Credit rows from the equation but still uses the post-Free-Tier metric structure. |
| Use `pricing_public_on_demand_cost` as the primary economic signal | Yes | **Selected.** Represents what the workload costs at AWS list price — the figure the bill will show on day 366 when Free Tier expires. Honest and defensible. |
| Synthesize a multiplier to project realised cost | No | Considered but rejected. Adds modelling complexity without adding accuracy; on-demand cost is itself the cleanest projection target. |

The choice has a downstream consequence: every cost figure in this analysis is labelled **on-demand** or **economic** rather than **invoice** or **realised**. That labelling discipline is preserved throughout the docs and SQL.

## On row grain in the fact table

Two reasonable grains for `fct_daily_cost`:

| Grain | Rows | Pros | Cons |
|---|---:|---|---|
| One row per CUR line item | 1,882 | Preserves `line_item_type` for every query; aggregation explicit and revisable; matches CUR's natural grain | Larger; some queries do a GROUP BY they wouldn't need otherwise |
| Pre-aggregated to (date, service, resource) | ~200 | Smaller; faster simple queries | Embeds line_item_type filtering decisions; harder to undo at query time |

**Selected: one row per line item.** Aggregation embeds assumptions. If the fact table is pre-aggregated with a "Usage rows only" filter applied, every downstream consumer is stuck with that filter. The day a finance reconciliation needs to see Credit rows separately, the table has to be rebuilt. Aggregating in queries — `SUM(on_demand_cost) WHERE line_item_type = 'Usage' GROUP BY date` — is a tiny cost that buys complete flexibility.

## On tag attribution priority

The bridge resolves tags in three tiers (real → inferred_partial → inferred_full). The order reflects a deliberate principle: **prefer the lowest-confidence, highest-fidelity source whenever available.**

A real tag set on a resource — even one that's incomplete — is more reliable than any rule-based inference. A rule-based inference applied to a resource that has *some* real tags is more reliable than one applied to a resource with *none*. The hierarchy preserves the maximum amount of real data and only falls back to inference when there is no alternative.

Two alternatives were considered and rejected:

| Approach | Rejected because |
|---|---|
| Apply inference rules uniformly, ignoring real tags | Loses real-tag fidelity. The whole point of tagging is the granularity it provides — overriding it with broad rules is wasteful. |
| Use only real tags; report ~61% of cost as "unknown" | Useful for tag hygiene reporting but unusable for showback. A finance team needs every dollar attributed somewhere; "unknown" is not an answer they can chargeback. |

The `tag_source` column makes the choice transparent — a stakeholder using the data can always re-segment by source and see exactly what they're standing on.

## On reclassifying NAT gateway as Network

`dim_service` puts NAT gateway cost into "Compute" because AWS bills it under the `AmazonEC2` service code. The findings document publishes both the raw and reclassified views. Three options were considered:

| Approach | Selected? |
|---|---|
| Override `dim_service` so all NAT gateway charges land in "Network" by detecting `usage_type LIKE 'NatGateway-%'` | No — this conflates `dim_service` (a service-code dimension) with semantic resource categorisation |
| Add a separate `resource_function` column to `dim_resource` and let analysis queries group by it | **Yes** — keeps each dimension's purpose pure |
| Leave the trap unaddressed and document it as a known issue | No — the trap is significant enough that silently misleading readers is unacceptable |

The chosen approach lets `dim_service` continue to faithfully reflect AWS's billing taxonomy, while `dim_resource.resource_type` provides the semantic view. Analytical queries pick whichever serves the question.

## On indexing scope at small data sizes

Four indexes are defined on `fct_daily_cost`. At 1,882 rows none of them measurably improves query performance — sequential scan beats most index lookups at this scale.

Why include them anyway:

1. **Demonstrate correct indexing decisions** for the production-scale CUR this model is built to handle. The same indexes are appropriate at 50M rows; the table size doesn't change which columns are the right indexing targets.
2. **Make `EXPLAIN` plans readable** when the project is run against larger samples. Without indexes, every plan says "Seq Scan" and conveys nothing about query design.
3. **Document the partial-index pattern** (`WHERE line_item_type = 'Usage'`, `WHERE resource_id IS NOT NULL`) which is a Postgres-specific capability worth knowing for CUR work.

The indexes are honestly labelled as "demonstration scale" in their definition file. A reader who wants to remove them for this dataset can do so safely — no query depends on them.

## On partitioning, deferred

Range partitioning on `bill_billing_period_start_date` is the right pattern for CUR data at scale, with one partition per calendar month. It is not implemented because the threshold for benefit hasn't been crossed (~5M rows or 12+ months of data). The decision is documented in [`03-data-model.md`](03-data-model.md) so a future maintainer knows when to revisit. **Premature partitioning adds DDL complexity for zero query-time benefit; the cost-benefit math reverses cleanly above the threshold.**

## On not using dbt

dbt would be a natural fit for the staging-and-marts pattern this project uses. It is not used here for two reasons:

1. **Stack discipline.** The project brief specifies PostgreSQL + DBeaver. Adding dbt would expand the dependency surface for a reader cloning the repo.
2. **Educational clarity.** The transformation logic is more visible as plain SQL files than as dbt models with macros and refs. A reader unfamiliar with dbt can understand `01-dim-service.sql` immediately; the same reader has to learn dbt before understanding `models/dim_service.sql`.

The folder structure mirrors dbt conventions (`staging/`, `marts/`) so a future port to dbt is one rename away.

## On anonymisation of the CUR sample

The raw CUR contains a real 12-digit AWS account ID and a personal-looking payer name. Both appear in direct columns and embedded inside ARNs (`arn:aws:ec2:us-east-1:147303435917:natgateway/...`). The shipped sample is anonymised by the script in `scripts/anonymise.py` which replaces both values with placeholders consistently across direct columns, ARNs, S3 bucket names, and any other location the values appear.

The script is in the repo (rather than just the anonymised output) so a reader can audit exactly what was scrubbed and what was preserved. Anonymisation by hand-editing files is a common cause of incomplete scrubbing in public datasets; a documented programmatic substitution is more defensible.

## On scope boundaries

The project addresses things this analysis does and does not include. **Excluded by design:**

- AWS Compute Optimizer recommendations — the AWS-native tool already does this well; rebuilding it as SQL would add no value.
- Cost Anomaly Detection — same reasoning.
- Live alerting / notification logic — out of scope for an analytical artifact; lives appropriately in a CloudWatch / EventBridge / SNS layer.
- Cross-cloud comparison — single-cloud (AWS) by design.

**Included by design but flagged as artificial in the current dataset:**

- RI / Savings Plan analysis (Phase 4) — the account has neither, so the work is structured as what-if modelling rather than descriptive reporting. Documented honestly in [`06-limitations.md`](06-limitations.md).
- Forecasting (Phase 6) — 16 days of history is below the threshold for meaningful seasonality detection. Phase 6 will use synthetic backfill clearly labelled as such, with the forecasting *technique* (not the forecasted *numbers*) as the deliverable.
