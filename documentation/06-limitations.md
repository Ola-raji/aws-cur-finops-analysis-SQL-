# 06 — Limitations

What this analysis cannot tell you, and why those limits matter. **A portfolio piece that doesn't articulate its limitations is harder to trust than one that does.** Recruiters and senior practitioners look for this section specifically.

## Limitations of the dataset

### Partial billing period

The CUR sample covers **April 1–16, 2026 — 16 of 30 days**. The billing period is not closed. Three consequences:

- Month-to-date totals are 53% of a projected full month. Naïve scaling — `total × 30/16` — gives ~$93/month, but seasonality (week-of-pay-period effects, weekend/weekday traffic mix) means the partial window is unlikely to extrapolate linearly.
- Trend analysis is meaningfully limited. 16 days is too short for week-over-week comparison, too short for stable rolling averages, and far too short for any kind of seasonality decomposition.
- Forecasting (Phase 6) cannot produce credible numerical projections from this data alone. The forecasting work uses synthetic backfill clearly labelled as such, with the *technique* as the deliverable rather than the *numbers*.

### Free Tier coverage

The account is fully Free-Tier-covered for the analysis window. Realised invoice cost is $0. All economic analysis uses `pricing_public_on_demand_cost` instead.

This produces honest analysis but limits two specific things:

- **No real RI/Savings Plan coverage data exists** — the account has neither, and Free Tier doesn't generate data that would inform commitment-discount strategy. The Phase 4 RI/SP analysis is structured as what-if modelling against the on-demand baseline rather than descriptive reporting.
- **`line_item_net_unblended_cost` is NULL throughout.** This column is populated by AWS for accounts participating in EDP, PPA, or consolidated-billing allocation. A simple single account gets NULL. Any analysis that relies on the net-unblended figure (e.g. organisation-level cost allocation) cannot be performed against this dataset.

### Single-account scope

The CUR is from a single AWS account with no Organization. Several CUR features designed for multi-account billing are therefore inactive:

- **Blended cost equals unblended cost** because there's no AWS Organization to blend across.
- **`bill_payer_account_id` and `line_item_usage_account_id` are identical.** Cross-account showback queries would be no-ops.
- **`split_line_item_*` columns are unused.** These exist for split cost allocation across shared resources (most commonly EKS clusters used by multiple cost centres). The pattern is interesting but cannot be demonstrated against this dataset.

The data model is built to be portable to multi-account CURs — `bill_payer_account_id` is preserved as a column in the staging layer and the model would scale without structural change — but the demonstration of multi-account features happens against a different dataset.

### No commitment discounts

There are no Reserved Instances or Savings Plans on the account. Every Usage row has `pricing_term = 'OnDemand'`. The `reservation_*` and `savings_plan_*` column families (~20 columns each) are entirely null.

Phase 4 includes a what-if analysis ("what would 1-year No-Upfront Compute SP coverage save?"), structured as projection rather than descriptive reporting. The math is real; the input baseline is real; what's missing is the descriptive coverage / utilization / unused-commitment reporting that an account with actual SPs would generate.

### Workload characterization is real but constrained

The HR portal workload is genuine — the architecture, the stakeholder context, the tagging strategy are not synthetic. But the workload itself is at very low traffic levels during the analysis window. Two specific consequences:

- **Auto Scaling has not triggered any scale-out events.** The two-instance baseline is the entire compute footprint observed. Scaling cost behavior under load is not present in this data.
- **Data transfer volumes are tiny** (S3 `DataTransfer-Out-Bytes` totals well under a cent). Phase 3 data-transfer decomposition will identify the *types* of transfer accurately but cannot report meaningfully on transfer cost magnitude until traffic grows.

## Limitations of the analytical approach

### Cost categorisation is editorial

`dim_service.service_category` is an opinion, not a standard. AWS provides no canonical FinOps category for `AmazonEC2`. The choice to put ELB and VPC into "Network" rather than separating them is a judgment call that another practitioner might make differently. Where downstream analysis depends on the categorisation, the choice is documented and the SQL is easy to override.

### Tag inference is a model, not a measurement

The `inferred_partial` and `inferred_full` rows in `bridge_tags` are educated guesses based on resource type and architectural context. They are explicit, documented, and auditable — but they are not real tags. **A finance reader who wants to ground every chargeback dollar in an actual customer-set tag should restrict their analysis to `tag_source = 'resource_tag'` and report the remainder as "unallocated."**

The 100% coverage figure quoted in [`04-findings.md`](04-findings.md) is "100% attributed" — every dollar has a destination — not "100% verified" — every dollar's destination came from a real tag. The distinction is preserved by the `tag_source` column, which downstream consumers should consult.

### Inferred ENI workload attribution is conservative

Six ENI rows generate ~$7.26 of Public IPv4 charges. The bridge attributes all of them to `workload = 'shared-network'` because the CUR alone cannot tell us which ENI is attached to which resource (the ALB? the NAT gateway? the EC2 instances?). Reaching the truth would require cross-referencing the EC2 `describe-network-interfaces` API — possible but outside the scope of pure CUR analysis.

A more aggressive attribution would split the ENIs across web-tier and shared-network. The conservative approach is preferred here because **defensible inference beats clever inference for finance work.**

### Forecasting from 16 days is methodologically weak

Phase 6 will produce SQL-based forecasts using window functions and seasonal decomposition. The technique is real and the SQL is correct, but **the input data is too short for the output forecasts to be trusted as numerical predictions.** Phase 6 explicitly uses synthetic backfill data to demonstrate the technique. The deliverable is the methodology, not the predicted figures.

A reader interpreting Phase 6 outputs as actual cost forecasts is misreading the project. The disclaimer is repeated in the Phase 6 SQL files and in the relevant findings sections.

## Limitations of scope

### The analysis does not challenge the architecture

The project takes the 3-tier HA architecture as given and asks "is it operating efficiently within that pattern?" It does not ask "is this the right architectural pattern?" That is a deliberate scoping choice — architectural decisions involve security, compliance, and operational concerns that sit outside FinOps and that a CUR-centric analysis cannot evaluate. Findings that point toward architectural changes (NAT consolidation, IPv6 migration, public IPv4 elimination) are framed as input to architectural conversations, not as recommendations.

### The analysis does not include cost-of-cost

FinOps tooling, monitoring, dashboard licenses, and FinOps practitioner labour are real costs of running the operation that this analysis does not quantify. A complete unit-economics analysis for the HR portal would include these in the cost-per-employee calculation. They are excluded here because they are operational overhead allocated across many workloads and are difficult to fairly attribute to a single one.

### Cross-cloud and on-premises alternatives are out of scope

The HR portal could in principle run on Azure, GCP, or on-premises. The CUR can only describe what the workload costs *on AWS*. A make-or-buy / cloud-or-cloud comparison would require equivalent cost data from the alternative platform, which is not in scope for this project.

## Limitations as a portfolio piece

For a hiring manager evaluating this work:

- The dataset is small in absolute size (1,882 rows). The model and the SQL are designed to scale to multi-million-row CURs, but **scale is not demonstrated against this dataset alone.** A reader specifically evaluating performance characteristics on enterprise-scale CUR data should treat that as an open question.
- The analysis is single-author and has not been reviewed by a senior FinOps practitioner. The methodology choices reflect best practice as I understand it; they are open to challenge.
- The forecasting and showback phases (6 and 7) will lean heavily on synthetic data. That is documented honestly, but it does mean the project's full analytical surface is not entirely grounded in real observation.

These are honest framings rather than apologies. The work that is grounded in real data — the model layer, the descriptive findings, the tag attribution math — stands on its own.
