-- ==============================================================================
-- 03-bridge-tags.sql
-- Tag enrichment bridge. One row per distinct resource_id with the canonical
-- tag set for that resource and a tag_source column documenting provenance.
--
-- Three-tier attribution:
--   1. resource_tag      — best-available real tags (richest set per resource)
--   2. inferred_partial  — real tags + missing key filled by rule
--   3. inferred_full     — all values inferred from resource type
--
-- Lines with no resource_id (CloudWatch dashboards, KMS API calls, free-tier
-- CloudTrail events) are not in this table — they are attributed inline in
-- fct_daily_cost via line_item_product_code and recorded with
-- tag_source = 'usage_type_inferred'.
-- ==============================================================================

DROP TABLE IF EXISTS marts.bridge_tags;

CREATE TABLE marts.bridge_tags (
  resource_id      TEXT NOT NULL,
  tag_project      TEXT,
  tag_environment  TEXT,
  tag_cost_center  TEXT,
  tag_workload     TEXT,
  tag_owner        TEXT,
  tag_criticality  TEXT,
  tag_source       TEXT NOT NULL,
  PRIMARY KEY (resource_id)
);

-- ---- Tier 1: best-available real tags --------------------------------------
-- For each resource_id, take the row with the most populated tag keys.
-- LOWER() on workload normalises the 'Observability' vs 'observability'
-- inconsistency observed in this dataset.
INSERT INTO marts.bridge_tags (
  resource_id, tag_project, tag_environment, tag_cost_center,
  tag_workload, tag_owner, tag_criticality, tag_source
)
SELECT DISTINCT ON (line_item_resource_id)
  line_item_resource_id,
  resource_tags ->> 'user_project',
  resource_tags ->> 'user_environment',
  resource_tags ->> 'user_cost_center',
  LOWER(resource_tags ->> 'user_workload'),
  resource_tags ->> 'user_owner',
  resource_tags ->> 'user_criticality',
  'resource_tag'
FROM staging.cur_line_items
WHERE line_item_resource_id IS NOT NULL
  AND line_item_resource_id != ''
  AND resource_tags != '{}'::jsonb
ORDER BY
  line_item_resource_id,
  (SELECT COUNT(*) FROM jsonb_each(resource_tags)) DESC;

-- ---- Tier 2: inferred_partial — NAT gateway workload -----------------------
-- The NAT gateway carries five of six tags. Workload is intentionally absent
-- (it's shared infrastructure, doesn't belong to any single tier). Fill the
-- gap with 'shared-network' and record the partial inference.
UPDATE marts.bridge_tags
SET tag_workload = 'shared-network',
    tag_source   = 'inferred_partial'
WHERE resource_id LIKE '%natgateway%'
  AND tag_workload IS NULL;

-- ---- Tier 3: inferred_full — resources with no real tags -------------------
-- ENIs (Public IPv4 charges), EBS volumes, the CloudTrail S3 bucket, and the
-- SNS topic have no real tags anywhere in the CUR. Infer from resource type
-- and architectural context. Conservative attribution: ENIs go to
-- 'shared-network' rather than guessing which resource each is attached to
-- (would require cross-referencing the EC2 describe-network-interfaces API).
INSERT INTO marts.bridge_tags (
  resource_id, tag_project, tag_environment, tag_cost_center,
  tag_workload, tag_owner, tag_criticality, tag_source
)
SELECT
  r.resource_id,
  'ha-web-portal',
  'production',
  'CC-1001',
  CASE r.resource_type
    WHEN 'Network Interface' THEN 'shared-network'
    WHEN 'EBS Volume'        THEN 'web-tier'
    WHEN 'S3 Bucket'         THEN 'management'
    WHEN 'SNS Topic'         THEN 'management'
    ELSE                          'unclassified'
  END,
  'platform-team',
  'high',
  'inferred_full'
FROM marts.dim_resource r
WHERE NOT EXISTS (
  SELECT 1 FROM marts.bridge_tags b WHERE b.resource_id = r.resource_id
);

-- Verification: tier breakdown. Expected ~ 8 / 1 / 14 rows by source.
SELECT tag_source, COUNT(*) AS resources
FROM marts.bridge_tags
GROUP BY 1
ORDER BY 2 DESC;
