# Scripts

Reserved for:

- `load_cur.py` — production loader. Creates a typed `staging.cur_line_items` table from the raw CSV in one pass, eliminating the need for `sql/10-staging/00-load-fixes.sql`.
- `anonymise.py` — anonymisation utility. Replaces real AWS account IDs and payer names with placeholders consistently across direct columns, ARNs, and bucket names. Runs against the source CUR before publication.

Both scripts will be added in a subsequent commit.
