-- demo_tables.sql — small demo schema for the diff agent. Run once, then take
-- a baseline (collectors/snapshot.sql + collectors/diff.sql) BEFORE demo_plant.sql.
CREATE TABLE IF NOT EXISTS orders AS
  SELECT g AS id, (random()*1000)::int AS customer_id,
         now() - (random()*interval '90 days') AS created_at,
         'pending' AS status, md5(g::text) AS payload
  FROM generate_series(1, 200000) g;
ALTER TABLE orders ADD PRIMARY KEY (id);
CREATE INDEX IF NOT EXISTS orders_customer_idx ON orders (customer_id);
CREATE INDEX IF NOT EXISTS orders_customer_created_idx ON orders (customer_id, created_at);
CREATE INDEX IF NOT EXISTS orders_payload_idx ON orders (payload);

CREATE TABLE IF NOT EXISTS order_items (
  id bigserial PRIMARY KEY,
  order_id bigint REFERENCES orders(id),
  sku text, qty int
);
INSERT INTO order_items (order_id, sku, qty)
  SELECT (random()*199999)::int + 1, md5(g::text), 1 FROM generate_series(1, 100000) g;

CREATE TABLE IF NOT EXISTS events AS
  SELECT g AS id, now() - (random()*interval '30 days') AS ts, md5(g::text) AS body
  FROM generate_series(1, 200000) g;
ALTER TABLE events ADD PRIMARY KEY (id);

CREATE TABLE IF NOT EXISTS sessions AS
  SELECT g AS id, now() AS last_seen, md5(g::text) AS token
  FROM generate_series(1, 50000) g;
ALTER TABLE sessions ADD PRIMARY KEY (id);
