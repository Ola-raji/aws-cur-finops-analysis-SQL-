-- ==============================================================================
-- 04-fct-daily-cost.sql
-- Central fact table. One row per CUR line item — not pre-aggregated.
--
-- Tag attribution priority:
--   1. bridge_tags (resource-id rows) — covers ~95% of cost
--   2. inline CASE (null-resource-id rows) — covers ~4% of cost
--   3. 'unresolved' fallback — should always be 0 rows
--
-- All five org-level tags (project, environment, cost_center, owner,
-- criticality) collapse to single values for null-resource-id rows because
-- this is a single-project account. Workload is the only field that varies.
-- ==============================================================================

DROP TABLE IF EXISTS marts.fct_daily_cost;

CREATE TABLE marts.fct_daily_cost AS
SELECT
  -- Time
  (s.line_item_usage_start_date AT TIME ZONE 'UTC')::date               AS usage_date,

  -- Service / usage
  s.line_item_product_code                                              AS service_code,
  s.line_item_usage_type                                                AS usage_type,
  s.line_item_line_item_description                                     AS line_item_description,
  s.line_item_line_item_type                                            AS line_item_type,

  -- Resource
  s.line_item_resource_id                                               AS resource_id,
  s.line_item_availability_zone                                         AS availability_zone,
  s.product_region_code                                                 AS region,

  -- Cost measures
  COALESCE(s.pricing_public_on_demand_cost, 0)::numeric(20,10)          AS on_demand_cost,
  COALESCE(s.line_item_unblended_cost, 0)::numeric(20,10)               AS unblended_cost,
  COALESCE(s.line_item_net_unblended_cost,
           s.line_item_unblended_cost, 0)::numeric(20,10)               AS effective_cost,

  -- Usage
  COALESCE(s.line_item_usage_amount, 0)::numeric(20,10)                 AS usage_amount,
  s.pricing_unit                                                        AS usage_unit,

  -- Tag dimensions
  COALESCE(b.tag_project,
    CASE WHEN s.line_item_resource_id IS NULL OR s.line_item_resource_id = ''
         THEN 'ha-web-portal' END)                                      AS tag_project,

  COALESCE(b.tag_environment,
    CASE WHEN s.line_item_resource_id IS NULL OR s.line_item_resource_id = ''
         THEN 'production' END)                                         AS tag_environment,

  COALESCE(b.tag_cost_center,
    CASE WHEN s.line_item_resource_id IS NULL OR s.line_item_resource_id = ''
         THEN 'CC-1001' END)                                            AS tag_cost_center,

  COALESCE(b.tag_workload,
    CASE s.line_item_product_code
      WHEN 'AmazonCloudWatch'  THEN 'observability'
      WHEN 'AWSCloudTrail'     THEN 'management'
      WHEN 'awskms'            THEN 'management'
      WHEN 'AWSSecretsManager' THEN 'management'
      WHEN 'AWSQueueService'   THEN 'app-tier'
      WHEN 'AmazonSNS'         THEN 'management'
      WHEN 'AWSGlue'           THEN 'management'
      WHEN 'AWSDataTransfer'   THEN 'shared-network'
      WHEN 'AmazonS3'          THEN 'management'
      ELSE                          'unclassified'
    END)                                                                AS tag_workload,

  COALESCE(b.tag_owner,
    CASE WHEN s.line_item_resource_id IS NULL OR s.line_item_resource_id = ''
         THEN 'platform-team' END)                                      AS tag_owner,

  COALESCE(b.tag_criticality,
    CASE WHEN s.line_item_resource_id IS NULL OR s.line_item_resource_id = ''
         THEN 'high' END)                                               AS tag_criticality,

  -- Provenance
  CASE
    WHEN b.resource_id IS NOT NULL                                      THEN b.tag_source
    WHEN s.line_item_resource_id IS NULL OR s.line_item_resource_id = '' THEN 'usage_type_inferred'
    ELSE                                                                     'unresolved'
  END                                                                   AS tag_source

FROM staging.cur_line_items s
LEFT JOIN marts.bridge_tags b ON b.resource_id = s.line_item_resource_id;

-- Verification: row count must equal staging exactly. Expected: 1882.
SELECT COUNT(*) AS fct_rows FROM marts.fct_daily_cost;
