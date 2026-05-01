-- ==============================================================================
-- 02-dim-resource.sql
-- Resource dimension. One row per distinct line_item_resource_id.
--
-- Resource type and resource name are derived from the identifier itself
-- (ARN structure or short-ID prefix), not from a manual lookup. New resource
-- types in future CUR loads degrade gracefully into 'Other' with the raw
-- ID preserved as the name, rather than silently misclassifying.
--
-- DISTINCT ON picks the information-richest row when the same resource
-- appears multiple times with varying region/AZ population.
--
-- Note on the table alias: PostgreSQL raises an "ambiguous column" error
-- in INSERT...SELECT when an ORDER BY column name matches both a source
-- column and a SELECT-output column. Using an alias (s.) on every reference
-- to source columns prevents the ambiguity.
-- ==============================================================================

DROP TABLE IF EXISTS marts.dim_resource;

CREATE TABLE marts.dim_resource (
  resource_id        TEXT NOT NULL,
  resource_type      TEXT NOT NULL,
  resource_name      TEXT NOT NULL,
  service_code       TEXT,
  region             TEXT,
  availability_zone  TEXT,
  PRIMARY KEY (resource_id)
);

INSERT INTO marts.dim_resource (
  resource_id, resource_type, resource_name, service_code, region, availability_zone
)
SELECT DISTINCT ON (s.line_item_resource_id)
  s.line_item_resource_id,

  -- Resource type from identifier pattern
  CASE
    WHEN s.line_item_resource_id LIKE 'arn:aws:elasticloadbalancing:%'    THEN 'Application Load Balancer'
    WHEN s.line_item_resource_id LIKE 'arn:aws:rds:%:db:%'                THEN 'RDS Instance'
    WHEN s.line_item_resource_id LIKE 'arn:aws:ec2:%:natgateway/%'        THEN 'NAT Gateway'
    WHEN s.line_item_resource_id LIKE 'arn:aws:ec2:%:network-interface/%' THEN 'Network Interface'
    WHEN s.line_item_resource_id LIKE 'arn:aws:s3:::%'                    THEN 'S3 Bucket'
    WHEN s.line_item_resource_id LIKE 'arn:aws:sns:%'                     THEN 'SNS Topic'
    WHEN s.line_item_resource_id ~ '^i-[0-9a-f]+'                         THEN 'EC2 Instance'
    WHEN s.line_item_resource_id ~ '^vol-[0-9a-f]+'                       THEN 'EBS Volume'
    WHEN s.line_item_resource_id LIKE 'aws-cloudtrail-logs-%'             THEN 'S3 Bucket'
    ELSE 'Other'
  END,

  -- Resource name parsed from each ARN style
  CASE
    WHEN s.line_item_resource_id LIKE 'arn:aws:elasticloadbalancing:%:loadbalancer/app/%'
      THEN split_part(split_part(s.line_item_resource_id, '/app/', 2), '/', 1)
    WHEN s.line_item_resource_id LIKE 'arn:aws:rds:%:db:%'
      THEN split_part(s.line_item_resource_id, ':db:', 2)
    WHEN s.line_item_resource_id LIKE 'arn:aws:ec2:%:natgateway/%'
      THEN split_part(s.line_item_resource_id, 'natgateway/', 2)
    WHEN s.line_item_resource_id LIKE 'arn:aws:ec2:%:network-interface/%'
      THEN split_part(s.line_item_resource_id, 'network-interface/', 2)
    WHEN s.line_item_resource_id LIKE 'arn:aws:s3:::%'
      THEN split_part(s.line_item_resource_id, ':::', 2)
    WHEN s.line_item_resource_id LIKE 'arn:aws:sns:%'
      THEN split_part(s.line_item_resource_id, ':', 6)
    ELSE s.line_item_resource_id
  END,

  s.line_item_product_code,
  s.product_region_code,
  s.line_item_availability_zone

FROM staging.cur_line_items s
WHERE s.line_item_resource_id IS NOT NULL
  AND s.line_item_resource_id != ''
ORDER BY
  s.line_item_resource_id,
  s.product_region_code         NULLS LAST,
  s.line_item_availability_zone NULLS LAST;

-- Verification: distribution of resources by type. Expected: 9 types.
SELECT resource_type, COUNT(*) AS resources
FROM marts.dim_resource
GROUP BY 1
ORDER BY 2 DESC;
