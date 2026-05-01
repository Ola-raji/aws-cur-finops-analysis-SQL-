## AWS CUR FinOps Analysis (SQL) ☁️ 📊

This project takes raw AWS CUR Report (2.0) covering 16 days of an internal HR portal running on a 3-tier, highly available architecture and turns it into a clean dimensional model in PostgreSQL, then layers analytical SQL on top to extract custom insights that AWS-native tools (Cost Explorer, Budgets, Trust Advisor etc.) do not surface.

The analysis is built in phases. Each phase ends with a concrete deliverable: a model layer, a set of analytical views, a forecasting module, or a showback view. The repository is updated after each phase completes. **The current scope covers Phase 0 (foundation) and Phase 1 (modelling).**

---

### ⭐ Star schema

<img src="https://github.com/user-attachments/assets/09aa9dce-550f-4a32-a853-3cff28fd1a5c" width="555">

---

### 🏢 Business context

The system under analysis is an **internal, read-only HR portal serving ~500 employees**. It is built on a production-shaped 3-tier architecture: an Application Load Balancer fronting two EC2 instances spread across availability zones, an RDS Multi-AZ MySQL backend, and a NAT gateway providing outbound internet access from private subnets. The workload has business-hours traffic, predictable seasonality, modest data volume, and read-heavy patterns.

The architectural pattern is intentionally over-provisioned for the actual traffic profile — that is exactly what makes it a useful FinOps subject. An under-utilized production-grade architecture is the most common pattern in real enterprise IT, and the question "what does this system cost, and where is the cost actually going" is harder to answer than people assume.

The AWS account is currently within Free Tier coverage, so the realised invoice cost is $0. **All economic analysis in this project uses `pricing_public_on_demand_cost`** — what this workload would cost at AWS list prices once Free Tier expires or the workload scales beyond its limits. This is documented in detail in [`docs/02-cur-primer.md`](docs/02-cur-primer.md) and [`docs/06-limitations.md`](docs/06-limitations.md).

---

### 🔍 Headline finding

For a 16-day window in April 2026:

- **$49.56 in on-demand-equivalent cost.** ~$95/month projected at current scale.
- **65% of the bill is network infrastructure** — NAT gateway, ALB, and Public IPv4 charges combined. Network spend exceeds compute spend in this workload, which is the structural signature of an HA architecture serving low traffic. A NAT gateway costs the same per hour whether 500 employees use the portal or zero.
- **The single most expensive resource is the NAT gateway at $16.53.** It outspends the entire ALB, the entire RDS instance, and both EC2 web tier instances combined.
- **AWS bills the NAT gateway under the EC2 service code, not VPC.** Any cost categorisation that groups by `line_item_product_code` will misclassify NAT gateway spend as Compute. This is a known FinOps trap and is handled explicitly in the data model.
- **Raw resource-tag coverage is 39% of cost.** A three-tier enrichment bridge (real tags, partial inference, full inference from resource type) brings attribution to 100% with full provenance recorded on every dollar.

Detailed findings — including the breakdown of every cost driver, the tag attribution math, and the supporting queries — are in [`docs/04-findings.md`](docs/04-findings.md).

---

### 🧪 Methodology summary

The data is modelled as a small star schema. One fact table (`fct_daily_cost`) holds one row per CUR line item with all six tag dimensions resolved and three cost variants carried forward. Three dimensions hang off it: `dim_service` (service codes mapped to FinOps categories), `dim_resource` (ARNs parsed into readable names and types), and `bridge_tags` (a tag-attribution bridge that brings raw 39% tag coverage to 100% via three-tier enrichment with provenance). Every analytical query reads from `fct_daily_cost`. The raw CUR is treated as immutable — no transformations are applied in place. Full reasoning, alternatives considered, and trade-offs are in [`docs/05-methodology.md`](docs/05-methodology.md).

---

### 🏗️ Data model

The diagram at the top of this README shows the schema. Below is the file layout — what each script does and where it lives.

```
Raw CUR (CSV in S3)
        │
        ▼
┌───────────────────────────────────────────────┐
│ schema: staging                               │
│   • cur_line_items                            │    
└───────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────┐
│ schema: marts                                 │
│   • dim_service                               │   
│   • dim_resource                              │   
│   • bridge_tags                               │   
│   • fct_daily_cost                            │   
└───────────────────────────────────────────────┘
```

| Schema | Script | Purpose |
|---|---|---|
| `staging` | [`sql/10-staging/00-load-fixes.sql`](sql/10-staging/00-load-fixes.sql) | Type corrections for the raw CUR table after CSV import. Run only if you load via DBeaver's import wizard rather than the production loader. |
| `marts` | [`sql/20-marts/01-dim-service.sql`](sql/20-marts/01-dim-service.sql) | Service dimension. 13 service codes mapped to 9 FinOps categories. |
| `marts` | [`sql/20-marts/02-dim-resource.sql`](sql/20-marts/02-dim-resource.sql) | Resource dimension. 23 ARNs parsed into readable names and types. |
| `marts` | [`sql/20-marts/03-bridge-tags.sql`](sql/20-marts/03-bridge-tags.sql) | Tag attribution bridge. Three-tier enrichment, raw 39% coverage to 100% with provenance. |
| `marts` | [`sql/20-marts/04-fct-daily-cost.sql`](sql/20-marts/04-fct-daily-cost.sql) | Central fact table. 1,882 rows, one per CUR line item, all tags resolved. |


Full data model documentation: [`docs/03-data-model.md`](docs/03-data-model.md).

---

### 🛠️ Tools and stack

| Layer | Tool |
|---|---|
| Source data | S3, AWS CLI |
| Database | PostgreSQL 18 |
| SQL client | DBeaver |
| Reference for cross-validation | AWS Cost Explorer, AWS Compute Optimizer, |

The stack is deliberately minimal — no orchestration framework, no notebook environment, no BI tool dependencies. Anyone with PostgreSQL and a SQL client can clone this repo and reproduce the analysis end-to-end.

---

### 🗺️ Project roadmap

The project is organized in phases, each producing a concrete reviewable deliverable. **Phases 0 and 1 are complete and represent the current scope of this repository.** This README and [`docs/04-findings.md`](docs/04-findings.md) will be extended as each subsequent phase ships.

---

### 📂 Repository structure

```
aws-cur-finops-analysis/
│
├── README.md                       
│
├── docs/
│   ├── 01-context.md               Business setting and architecture under analysis.
│   ├── 02-cur-primer.md            What CUR data is, how it's structured, what to know before querying.
│   ├── 03-data-model.md            Star schema, layer architecture, design decisions.
│   ├── 04-findings.md              Insights produced to date. Updated as phases complete.
│   ├── 05-methodology.md           How decisions were made. What alternatives were rejected and why.
│   └── 06-limitations.md           What this analysis cannot tell you, and why that matters.
│
├── sql/
│   ├── 10-staging/                 Type fixes for the raw CUR table after CSV import.
│   └── 20-marts/                   The dimensional model: dim_service, dim_resource, bridge_tags, fct_daily_cost.

│
├── images/
│   ├── star-schema.png             
│   └── data-model.png             
│
└── LICENSE                         MIT.
```

