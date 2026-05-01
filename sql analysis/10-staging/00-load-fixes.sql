-- ==============================================================================
-- 00-load-fixes.sql
-- Type corrections for the raw CUR table after CSV import.
--
-- Why this file exists: most CSV-import wizards (DBeaver, pgAdmin, naive
-- COPY) infer column types from string content. CUR data is particularly
-- prone to misinference. Timestamps come in as TEXT, costs come in as REAL
-- with empty-string values that subsequently break numeric casts, and the
-- JSON tag column comes in as TEXT.
--
-- The downstream marts SQL assumes canonical types: TIMESTAMPTZ for date
-- columns, NUMERIC for cost and usage columns, JSONB for resource_tags.
-- This file ALTERs the columns in place to those types.
--
-- A production loader (see scripts/load_cur.py) creates the table with
-- correct types from the start and does not need this file. Run this only
-- if your staging.cur_line_items was created via a CSV import wizard.
-- ==============================================================================

-- ---- Timestamp columns -----------------------------------------------------
-- Defensive USING clause: empty strings, malformed values, and NULLs all
-- convert to NULL rather than aborting the cast.
ALTER TABLE staging.cur_line_items
  ALTER COLUMN line_item_usage_start_date TYPE TIMESTAMPTZ
  USING CASE
    WHEN line_item_usage_start_date ~ '^\d{4}-\d{2}-\d{2}'
      THEN line_item_usage_start_date::timestamptz
    ELSE NULL
  END;

ALTER TABLE staging.cur_line_items
  ALTER COLUMN line_item_usage_end_date TYPE TIMESTAMPTZ
  USING CASE
    WHEN line_item_usage_end_date ~ '^\d{4}-\d{2}-\d{2}'
      THEN line_item_usage_end_date::timestamptz
    ELSE NULL
  END;

ALTER TABLE staging.cur_line_items
  ALTER COLUMN bill_billing_period_start_date TYPE TIMESTAMPTZ
  USING CASE
    WHEN bill_billing_period_start_date ~ '^\d{4}-\d{2}-\d{2}'
      THEN bill_billing_period_start_date::timestamptz
    ELSE NULL
  END;

ALTER TABLE staging.cur_line_items
  ALTER COLUMN bill_billing_period_end_date TYPE TIMESTAMPTZ
  USING CASE
    WHEN bill_billing_period_end_date ~ '^\d{4}-\d{2}-\d{2}'
      THEN bill_billing_period_end_date::timestamptz
    ELSE NULL
  END;

-- ---- Numeric cost columns --------------------------------------------------
-- NULLIF maps empty strings to NULL before casting. Without it the cast
-- aborts on the first '' it encounters.
ALTER TABLE staging.cur_line_items
  ALTER COLUMN pricing_public_on_demand_cost TYPE NUMERIC(20,10)
  USING NULLIF(pricing_public_on_demand_cost::text, '')::numeric;

ALTER TABLE staging.cur_line_items
  ALTER COLUMN line_item_unblended_cost TYPE NUMERIC(20,10)
  USING NULLIF(line_item_unblended_cost::text, '')::numeric;

ALTER TABLE staging.cur_line_items
  ALTER COLUMN line_item_net_unblended_cost TYPE NUMERIC(20,10)
  USING NULLIF(line_item_net_unblended_cost::text, '')::numeric;

ALTER TABLE staging.cur_line_items
  ALTER COLUMN line_item_blended_cost TYPE NUMERIC(20,10)
  USING NULLIF(line_item_blended_cost::text, '')::numeric;

ALTER TABLE staging.cur_line_items
  ALTER COLUMN line_item_usage_amount TYPE NUMERIC(20,10)
  USING NULLIF(line_item_usage_amount::text, '')::numeric;

-- ---- JSON tag column -------------------------------------------------------
ALTER TABLE staging.cur_line_items
  ALTER COLUMN resource_tags TYPE JSONB
  USING NULLIF(resource_tags::text, '')::jsonb;

-- ---- Verification ----------------------------------------------------------
-- Confirm conversions succeeded.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'staging'
  AND table_name = 'cur_line_items'
  AND column_name IN (
    'line_item_usage_start_date',
    'line_item_usage_end_date',
    'pricing_public_on_demand_cost',
    'line_item_unblended_cost',
    'line_item_net_unblended_cost',
    'line_item_usage_amount',
    'resource_tags'
  )
ORDER BY column_name;
