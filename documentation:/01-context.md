# 01 — Business context

## The system under analysis

The workload is an **internal HR portal for an organisation of approximately 500 employees**. It serves the typical HR self-service surface: pay statements, leave balances, benefits enrolment, document downloads, organisational directory. Traffic is read-heavy — employees consume information far more often than they update it. Usage is concentrated in business hours, with predictable seasonality (high traffic in the first week of each pay period and during open enrolment, low traffic on weekends and holidays).

The portal is operated as an internal cost centre. There is no revenue tied directly to its operation. From a FinOps perspective this is significant — the success metric is not unit margin, it is **cost-per-employee-served and cost-per-feature-delivered**, set against the value of HR self-service automation versus the alternative of more help-desk staff.

## Architecture

The system runs on AWS in `us-east-1` on a production-shaped 3-tier highly available architecture:

- **Web/application tier** — two `t3.micro` EC2 instances, one in each of two availability zones, behind an Application Load Balancer. Auto Scaling is configured but not currently triggering scale-out events.
- **Data tier** — Amazon RDS for MySQL on `db.t3.micro`, Multi-AZ deployment for failover capability.
- **Network** — application-tier instances in private subnets. Outbound internet access (for OS patches, package downloads, third-party API calls) routed through a NAT Gateway in a public subnet. Public-facing traffic enters via the ALB.
- **Supporting services** — CloudWatch for metrics and dashboards, CloudTrail for audit logs delivered to a private S3 bucket, KMS for encryption, Secrets Manager for the database credentials, SNS for operational alerts.

The architecture is intentionally over-provisioned for the actual traffic profile. Two EC2 instances spread across availability zones is the minimum HA configuration; it will not scale down further without sacrificing fault tolerance. Multi-AZ RDS doubles the database cost compared to single-AZ but eliminates a single-AZ failure as a recovery scenario. **This pattern — production-grade resilience on a low-traffic workload — is the most common cost shape in real enterprise IT**, and is exactly the territory where FinOps work produces the most value.

## Why this analysis matters despite small absolute spend

The realised invoice cost during the analysis window is $0 — the account is fully covered by AWS Free Tier. The on-demand-equivalent cost is approximately $49.56 over 16 days, which projects to ~$95/month at current scale.

These numbers are small. The reason the analysis is still worth doing:

**The cost shape is real and revealing.** Free Tier covers usage volumes, not pricing logic. The pattern of spend — what proportion goes to compute vs storage vs network, what proportion is structural overhead vs variable usage, how much is taggable vs untaggable — tells the same story whether the absolute numbers are $50 or $50,000. A FinOps practitioner who can read the cost shape on a tiny workload will read it correctly on a large one.

**The architectural decisions are scaling-invariant.** The 65% network share, the dominance of NAT gateway hours, the structural cost of public IPv4 charges — these are functions of the architecture, not the traffic level. They will look exactly the same on a workload 100x this size, except the dollars will be 100x larger. **Catching them now, when the absolute exposure is $16/month rather than $1,600/month, is precisely how mature FinOps practice works.**

**Free Tier ends.** Twelve months from account creation, or sooner if the organisation moves to consolidated billing. The numbers in this analysis are what the workload will start costing on day 366.

## Stakeholders the analysis serves

A useful FinOps deliverable serves multiple audiences. This project organises its outputs around three:

| Stakeholder | Question they ask | Where this project answers it |
|---|---|---|
| **Finance / cost centre owner** | What does HR's portal cost us, and is that cost trending up or down? | Phase 2 (descriptive trend) and Phase 7 (showback) |
| **Engineering** | Where can we cut without sacrificing reliability? Which resources are oversized? | Phase 3 (diagnostic) and Phase 4 (optimization) |
| **Leadership** | What will this cost in six months at our growth trajectory? What if we change architectural decisions? | Phase 5 (anomaly), Phase 6 (forecasting) |

The data model in Phase 1 is built to serve all three. Every analytical query downstream reads from the same fact table; only the grouping, filtering, and presentation change.

## What this analysis is not

This analysis is **not** a recommendation that the organisation abandon its 3-tier HA architecture in favour of something cheaper. The architecture is the right pattern for a system that holds employee personal data and must remain available during business hours. The point of the analysis is to ensure the architecture is *operating efficiently within its chosen pattern* — not to challenge the pattern itself.

It is also **not** a substitute for AWS Compute Optimizer or Cost Anomaly Detection. Those services solve specific problems well. This project's value lies in the questions they don't answer — unit economics, internal showback, scenario forecasting, structural-cost decomposition.

## Connection to prior projects

This is the third project in a connected series:

1. **Project 1 — Highly Available 3-Tier Architecture on AWS.** Built the system being analysed here.
2. **Project 2 — FinOps Foundation Layer.** Applied tagging strategy, AWS Budgets, Cost Explorer baselining, Compute Optimizer review, IAM/SCP guardrails, and configured CUR delivery to S3 — the data this project consumes.
3. **Project 3 (this repository) — CUR-Driven SQL Analysis.** Takes the CUR output from Project 2 and extracts insights beyond what the AWS-native console surfaces.

Each project stands alone but they are designed as a chain: provisioning → governance → analytical depth.
