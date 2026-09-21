-- demo_unplant.sql — reverse demo_plant.sql so the demo can be rerun.
CREATE INDEX IF NOT EXISTS orders_customer_created_idx ON orders (customer_id, created_at);
REVOKE SELECT ON orders FROM PUBLIC;
ALTER TABLE order_items ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) NOT VALID;
ALTER TABLE events DROP COLUMN IF EXISTS source;
ALTER TABLE sessions ALTER COLUMN token TYPE text;
DROP VIEW IF EXISTS recent_orders;
DROP FUNCTION IF EXISTS order_total(bigint);
DROP ROLE IF EXISTS reporting_admin;
ALTER DATABASE defaultdb RESET work_mem;
ALTER DATABASE defaultdb RESET statement_timeout;
