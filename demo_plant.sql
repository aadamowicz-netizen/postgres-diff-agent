-- demo_plant.sql
-- Demo changes for the diff agent. Take a baseline (collectors/snapshot.sql then
-- collectors/diff.sql), run this file, reconnect, then run the collectors
-- again. Expect ~11 observed changes across settings, schema, roles, grants.
-- Run as doadmin. Requires the tables from demo_tables.sql.

-- dropped index the churn loop uses (indexes domain should also notice)
DROP INDEX IF EXISTS orders_customer_created_idx;

-- table-level grant to PUBLIC
GRANT SELECT ON orders TO PUBLIC;

-- foreign key removed
ALTER TABLE order_items DROP CONSTRAINT IF EXISTS order_items_order_id_fkey;

-- column added, column widened, view created, function created
ALTER TABLE events ADD COLUMN IF NOT EXISTS source text;
ALTER TABLE sessions ALTER COLUMN token TYPE varchar(64);
CREATE OR REPLACE VIEW recent_orders AS SELECT * FROM orders WHERE created_at > now() - interval '7 days';
CREATE OR REPLACE FUNCTION order_total(p_id bigint) RETURNS int LANGUAGE sql
  AS $$ SELECT coalesce(sum(qty),0)::int FROM order_items WHERE order_id = p_id $$;

-- a new login role (only works if you can create roles)
DO $$ BEGIN
  CREATE ROLE reporting_admin LOGIN CREATEDB CREATEROLE PASSWORD 'demo-only';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skipped role: %', SQLERRM; END $$;

-- settings change (managed clusters usually refuse ALTER SYSTEM; the
-- per-database form below is allowed and is picked up in pg_settings by
-- sessions connecting to this database)
ALTER DATABASE defaultdb SET work_mem = '256MB';
ALTER DATABASE defaultdb SET statement_timeout = '30s';
-- reconnect before the second collection so the new values show in pg_settings
