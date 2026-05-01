CREATE SCHEMA IF NOT EXISTS marts;

DROP TABLE IF EXISTS marts.dim_service;

CREATE TABLE marts.dim_service (
  service_code      TEXT NOT NULL,
  service_name      TEXT NOT NULL,
  service_category  TEXT NOT NULL,
  PRIMARY KEY (service_code)
);

INSERT INTO marts.dim_service (service_code, service_name, service_category)
SELECT DISTINCT
  line_item_product_code,
  CASE line_item_product_code
    WHEN 'AmazonEC2'         THEN 'Amazon EC2'
    WHEN 'AmazonRDS'         THEN 'Amazon RDS'
    WHEN 'AmazonS3'          THEN 'Amazon S3'
    WHEN 'AWSELB'            THEN 'Elastic Load Balancing'
    WHEN 'AmazonVPC'         THEN 'Amazon VPC'
    WHEN 'AWSDataTransfer'   THEN 'AWS Data Transfer'
    WHEN 'AWSCloudTrail'     THEN 'AWS CloudTrail'
    WHEN 'AmazonCloudWatch'  THEN 'Amazon CloudWatch'
    WHEN 'awskms'            THEN 'AWS KMS'
    WHEN 'AWSSecretsManager' THEN 'AWS Secrets Manager'
    WHEN 'AWSQueueService'   THEN 'Amazon SQS'
    WHEN 'AmazonSNS'         THEN 'Amazon SNS'
    WHEN 'AWSGlue'           THEN 'AWS Glue'
    ELSE line_item_product_code
  END,
  CASE line_item_product_code
    WHEN 'AmazonEC2'         THEN 'Compute'
    WHEN 'AmazonRDS'         THEN 'Database'
    WHEN 'AmazonS3'          THEN 'Storage'
    WHEN 'AWSELB'            THEN 'Network'
    WHEN 'AmazonVPC'         THEN 'Network'
    WHEN 'AWSDataTransfer'   THEN 'Network'
    WHEN 'AWSCloudTrail'     THEN 'Management'
    WHEN 'AmazonCloudWatch'  THEN 'Observability'
    WHEN 'awskms'            THEN 'Security'
    WHEN 'AWSSecretsManager' THEN 'Security'
    WHEN 'AWSQueueService'   THEN 'Messaging'
    WHEN 'AmazonSNS'         THEN 'Messaging'
    WHEN 'AWSGlue'           THEN 'Analytics'
    ELSE 'Other'
  END
FROM staging.cur_line_items
WHERE line_item_product_code IS NOT NULL;

-- Verification: any service codes in staging without a mapping?
-- Expected: 0 rows.
SELECT DISTINCT s.line_item_product_code AS unmapped_code
FROM staging.cur_line_items s
LEFT JOIN marts.dim_service d ON d.service_code = s.line_item_product_code
WHERE d.service_code IS NULL
  AND s.line_item_product_code IS NOT NULL;
