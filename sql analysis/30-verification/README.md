# Analytical SQL

Queries that read from `marts.fct_daily_cost` to produce FinOps insight. Files are added phase-by-phase as the project progresses.

## Current contents

| File | Purpose |
|---|---|
| `00-verification.sql` | Sanity checks for the model layer. Run after `sql/20-marts/` completes. Confirms row counts, cost totals, and tag attribution match documented expectations. |

## Coming in subsequent phases

- **Phase 2 — Descriptive.** Daily/service/region trend analysis. Cost-type comparison view. Tag hygiene audit. Free-Tier-adjusted economic cost view.
- **Phase 3 — Diagnostic.** Unit economics (cost per employee, per GB, per request). NAT gateway decomposition (hours vs. bytes). Data-transfer breakdown (intra-AZ, inter-AZ, internet). Top cost drivers Pareto.
- **Phase 4 — Optimization.** Idle Public IPv4 detection. ALB LCU utilisation analysis. EC2 right-sizing signals. S3 storage-class tiering opportunity. RI/Savings Plan break-even what-if.
- **Phase 5 — Anomaly & variance.** Rolling baseline (7-day median + MAD). Z-score spike detection. Budget variance framework.
- **Phase 6 — Forecasting.** SQL-based trend + weekly seasonality forecast. Scenario what-ifs (commitment coverage, NAT consolidation, IPv4 elimination).
- **Phase 7 — Showback & chargeback.** HR cost-centre attribution view. Per-employee unit economic rollup. Exec-ready BI view.

Each query, when added, will carry a header block stating the business question it answers, the technique used, and any caveats. Findings produced from these queries will land in [`docs/04-findings.md`](../../docs/04-findings.md).
