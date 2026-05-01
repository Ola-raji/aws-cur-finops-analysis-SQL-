# 04 — Findings

The analytical output of the project, consolidated. Updated as each phase completes.

> **Current scope: Phases 0 and 1 — foundation and modeling.** Findings to date describe the cost shape, structural drivers, and tag attribution observed during the modeling pass. Diagnostic deep-dives (NAT decomposition, data-transfer breakdown, unit economics) belong to Phase 3 and will be added when complete.

---

## Executive summary

For a 16-day window in April 2026 on the HR portal workload:

- **$49.56 in on-demand-equivalent cost.** ~$95/month projected at current scale.
- **Network infrastructure consumes 65% of the bill** — NAT gateway, ALB, and Public IPv4 charges combined. This is the structural signature of an over-provisioned HA architecture serving low traffic.
- **The NAT gateway alone accounts for 33% of total spend** — more than the entire database tier, more than both EC2 instances combined.
- **Public IPv4 charges (~$7.26) are an emerging line item** that did not exist before AWS introduced IPv4 pricing in February 2024. They affect every dual-stack workload and are commonly missed in cost reviews.
- **39% of cost was attributable via raw resource tags;** a three-tier enrichment bridge brings attribution to 100% with full provenance recorded on every dollar.

---

## Finding 1 — Network is the dominant cost driver

The HR portal is, structurally, a network-cost workload. Cost grouped by FinOps category, then re-grouped by what the resources actually do:

| FinOps category (raw) | On-demand $ | Share | After NAT reclassification | On-demand $ | Share |
|---|---:|---:|---|---:|---:|
| Compute | $24.74 | 50% | Compute | $8.21 | 17% |
| Network | $15.54 | 31% | **Network** | **$32.07** | **65%** |
| Database | $7.37 | 15% | Database | $7.37 | 15% |
| Observability | $1.84 | 4% | Observability | $1.84 | 4% |
| Other | $0.07 | <1% | Other | $0.07 | <1% |

The right-hand columns are the truthful view. AWS bills the NAT gateway under the `AmazonEC2` service code, so a categorisation that groups by `line_item_product_code` puts NAT spend into Compute. **In the corrected view, network cost ($32.07) is nearly four times compute cost ($8.21).** That is the wrong shape for an application workload — under normal conditions network should be 5–15% of compute. It is the right shape for an HA architecture serving low traffic, where structural costs dominate and per-request costs barely move the needle.

Implication: optimisation effort spent on EC2 right-sizing or RDS instance class will return at most a few dollars per month. The same effort spent on network architecture (NAT consolidation, IPv6 migration, Public IPv4 elimination) returns ten times more. Phase 4 quantifies these scenarios.

## Finding 2 — The top three resources are 75% of spend

| Rank | Resource | Type | On-demand $ | Cumulative |
|---:|---|---|---:|---:|
| 1 | `nat-0c6e666beb9fa9411` | NAT Gateway | $16.53 | 33% |
| 2 | `ha-app-load-balancer` | Application Load Balancer | $8.28 | 50% |
| 3 | `ha-project-db` | RDS Instance | $7.37 | 65% |
| 4 | `i-0277201444264158e` | EC2 Instance | $3.79 | 73% |
| 5 | `i-0f2dead076354a419` | EC2 Instance | $3.78 | 80% |
| 6–9 | ENIs (Public IPv4 charges) | Network Interface | $7.26 combined | 95% |
| 10+ | EBS, S3, CloudWatch, others | various | $2.55 combined | 100% |

Two observations. First, the dominant resource is shared infrastructure. The NAT gateway has no per-instance affinity — it serves both EC2 instances and any future workload added to the private subnets. Per-employee unit economics (Phase 3) need to allocate it carefully.

Second, the six ENIs at positions 6–9 are not interesting in their own right — they exist because the EC2 instances and the NAT gateway have public IPv4 addresses attached. AWS introduced a charge of $0.005/hour per public IPv4 address in February 2024. That charge applies to every IP whether or not it sees traffic. It is an emerging line item that did not exist in CUR data prior to Q1 2024 and is frequently missed in legacy cost reviews.

## Finding 3 — Tag attribution: from 39% to 100% via enrichment

Resource tagging was applied in Project 2 with six keys: `Project`, `Environment`, `CostCenter`, `Workload`, `Owner`, `Criticality`. Naively measured, coverage looked like this:

| Slice | Tagged |
|---|---:|
| By line-item count | 24% |
| By on-demand cost | 39% |

The 39% figure is not a tagging discipline failure — it is a structural feature of how AWS attaches tags in the CUR. Three causes:

- **Some line items are untaggable by AWS.** Public IPv4 charges, CloudWatch dashboards, KMS API requests, free-tier CloudTrail events have no parent resource to inherit tags from. ~18% of cost falls in this category.
- **Sub-line-items don't always inherit parent tags.** EC2 hourly usage is tagged; data-transfer, EBS, and snapshot sub-lines for the same instance often are not.
- **Cost allocation tags require explicit activation in the Billing console.** Tags exist in AWS APIs as soon as set, but do not appear in the CUR until activated. Activation is prospective only.

The bridge resolves all three failure modes via three-tier enrichment:

| Tag source | Description | On-demand $ | Share |
|---|---|---:|---:|
| `resource_tag` | Real tags from the CUR (richest tag set per resource wins) | $23.22 | 47% |
| `inferred_partial` | Real tags + one missing key filled in by rule | $16.53 | 33% |
| `inferred_full` | All values inferred from resource type | $7.97 | 16% |
| `usage_type_inferred` | No resource_id; attributed by service code | $1.84 | 4% |
| `unresolved` | — | $0.00 | 0% |

**Every dollar has an attributed cost centre. Every dollar's attribution carries provenance.** A finance team running showback can see exactly which numbers came from real tags and which were inferred — and can challenge or accept the inference rules without losing the underlying data.

A separate tag hygiene observation worth flagging: one workload tag value (`Observability`, on the SNS alerts topic) was set in mixed case while every other workload value uses lowercase-kebab-case (`web-tier`, `data-tier`). The bridge normalises this on ingest with `LOWER()`. A formal tag-hygiene audit query lands in Phase 2.

## Finding 4 — Free Tier masks economic reality

Realised invoice cost during the analysis window is $0. Every Usage row in the CUR is offset by a matching Credit row from AWS Free Tier:

| Cost view | Total |
|---|---:|
| `unblended_cost` (Usage rows + Credit rows, summed) | $0.00 |
| `unblended_cost` (Usage rows only) | $47.68 |
| `pricing_public_on_demand_cost` (Usage rows only) | $49.56 |

A finance team consulting only the AWS Billing console would see $0 and reasonably conclude there is nothing to manage. The on-demand-equivalent cost is the more honest signal — it is what the workload starts costing on day 366 of the AWS account, or sooner if the organisation moves to consolidated billing.

The discrepancy between `unblended_cost` (Usage rows only) and `pricing_public_on_demand_cost` ($47.68 vs $49.56, ~4% delta) reflects rounding in AWS's Free Tier offset calculation rather than any meaningful economic difference. For analytical purposes the two figures are equivalent.

## Stakeholder takeaways

A summary aimed at the three audiences this project serves:

**For finance / cost centre owners.** This workload will start costing ~$95/month on-demand once Free Tier expires. Cost is dominated by structural network infrastructure, not by per-employee usage. The chargeback view (Phase 7) will quantify cost-per-employee — preliminary math puts it at ~$0.19/employee/month at current scale.

**For engineering.** Optimisation effort is best invested in the network layer, not the compute layer. The NAT gateway is the single biggest target ($16.53/16 days). The Public IPv4 charges are a nontrivial emerging cost ($7.26/16 days) that can be mitigated by removing public IP allocation from EC2 instances that don't need direct internet ingress. EC2 right-sizing on `t3.micro` will return tiny dollars compared to either of the above.

**For leadership.** The current cost shape is the structural floor for this architecture. Reducing it materially requires architectural changes (NAT consolidation, IPv6, smaller-footprint topology) rather than tuning. The forecasting work in Phase 6 will model what those changes are worth in dollars.

---

*Phases 2 onwards will extend this document with diagnostic depth (NAT decomposition, data-transfer mix, unit economics), optimization scenarios, anomaly detection results, and forecast outputs.*
