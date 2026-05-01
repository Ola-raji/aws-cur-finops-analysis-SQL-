-- ==============================================================================
-- 00-verification.sql
-- Sanity checks for the model layer. Run after sql/20-marts/ completes.
-- Expected outputs are documented inline.
-- ==============================================================================

-- ---- Row counts ------------------------------------------------------------
-- Expected: dim_service 13, dim_resource 23, bridge_tags 23, fct_daily_cost 1882.
SELECT
  (SELECT COUNT(*) FROM marts.dim_service)     AS dim_service_rows,
  (SELECT COUNT(*) FROM marts.dim_resource)    AS dim_resource_rows,
  (SELECT COUNT(*) FROM marts.bridge_tags)     AS bridge_tags_rows,
  (SELECT COUNT(*) FROM marts.fct_daily_cost)  AS fct_rows;

-- ---- Cost totals by line_item_type -----------------------------------------
-- Expected: Usage on_demand ~$49.56 unblended ~$47.68;
--           Credit unblended ~-$47.68;
--           Tax both ~$0.
SELECT
  line_item_type,
  COUNT(*)                                       AS rows,
  ROUND(SUM(on_demand_cost)::numeric, 2)         AS on_demand_cost,
  ROUND(SUM(unblended_cost)::numeric, 2)         AS unblended_cost
FROM marts.fct_daily_cost
GROUP BY 1
ORDER BY rows DESC;

-- ---- Tag attribution distribution ------------------------------------------
-- Expected: 4 sources, 0 'unresolved' rows.
-- Real tags ~$23.22, partial ~$16.53, full ~$7.97, usage_type ~$1.84.
SELECT
  tag_source,
  COUNT(*)                                       AS rows,
  ROUND(SUM(on_demand_cost)::numeric, 2)         AS on_demand_cost
FROM marts.fct_daily_cost
WHERE line_item_type = 'Usage'
GROUP BY 1
ORDER BY on_demand_cost DESC;

-- ---- Cost by service category ----------------------------------------------
-- Expected: Compute $24.74, Network $15.54, Database $7.37, Observability $1.84,
--           Storage $0.07, others $0. (Note: Compute includes NAT gateway —
--           see docs/04-findings.md for the corrected network view.)
SELECT
  d.service_category,
  ROUND(SUM(f.on_demand_cost)::numeric, 2)       AS on_demand_cost
FROM marts.fct_daily_cost f
JOIN marts.dim_service d ON d.service_code = f.service_code
WHERE f.line_item_type = 'Usage'
GROUP BY 1
ORDER BY on_demand_cost DESC;

-- ---- Top 10 resources by cost ----------------------------------------------
-- Expected top 5: NAT Gateway $16.53, ALB $8.28, RDS $7.37, two EC2 $3.79 each.
SELECT
  r.resource_name,
  r.resource_type,
  ROUND(SUM(f.on_demand_cost)::numeric, 2)       AS on_demand_cost
FROM marts.fct_daily_cost f
JOIN marts.dim_resource r ON r.resource_id = f.resource_id
WHERE f.line_item_type = 'Usage'
GROUP BY 1, 2
ORDER BY on_demand_cost DESC
LIMIT 10;
