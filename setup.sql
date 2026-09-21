-- setup.sql — run once as an admin user (e.g. doadmin) in the target database.
-- Creates the schema, the change-history table, the query view, and an
-- optional read-only role for the agent.

CREATE SCHEMA IF NOT EXISTS agent;

-- One row per object per snapshot (status='snapshot') and one row per
-- detected change (status='observed'). Facts only; no judgments stored.
CREATE TABLE IF NOT EXISTS agent.agent_findings (
    id                bigserial PRIMARY KEY,
    run_ts            timestamptz NOT NULL,
    domain            text        NOT NULL DEFAULT 'drift',
    object_name       text        NOT NULL,      -- <kind>:<qualified name>
    metrics           jsonb       NOT NULL DEFAULT '{}'::jsonb,
    diagnosis         text,                      -- added | removed | changed  (observed rows)
    severity          text,                      -- unused by this agent; kept for compatibility
    evidence          text,
    recommended_sql   text,
    status            text NOT NULL DEFAULT 'snapshot'
                      CHECK (status IN ('snapshot','observed','proposed','approved','applied','rejected','verified')),
    status_changed_at timestamptz
);

CREATE INDEX IF NOT EXISTS agent_findings_run_idx     ON agent.agent_findings (domain, run_ts DESC);
CREATE INDEX IF NOT EXISTS agent_findings_object_idx  ON agent.agent_findings (domain, object_name, run_ts DESC);
CREATE INDEX IF NOT EXISTS agent_findings_status_idx  ON agent.agent_findings (status) WHERE status <> 'snapshot';
CREATE INDEX IF NOT EXISTS agent_findings_metrics_idx ON agent.agent_findings USING gin (metrics);

COMMENT ON TABLE agent.agent_findings IS
  'Change history. status=snapshot rows are the raw state per run; status=observed rows are detected changes with before/after.';

DROP VIEW IF EXISTS agent.v_drift;
CREATE VIEW agent.v_drift AS
SELECT run_ts, object_name, status,
       metrics->>'kind'                                    AS kind,
       COALESCE(diagnosis, 'snapshot')                     AS change,
       metrics->>'before'                                  AS before,
       COALESCE(metrics->>'after', metrics->>'definition') AS after,
       (metrics->>'previous_run')::timestamptz             AS previous_run,
       metrics->>'source'                                  AS source
FROM agent.agent_findings
WHERE domain = 'drift';

-- Optional read-only role for the agent. Replace the password. On managed
-- Postgres you may not be able to grant pg_read_all_stats; if so the agent
-- can run as the admin user, since it only writes to the agent schema.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pg_diff_agent') THEN
    CREATE ROLE pg_diff_agent LOGIN PASSWORD 'CHANGE_ME';
  END IF;
END$$;
GRANT USAGE ON SCHEMA agent TO pg_diff_agent;
GRANT SELECT, INSERT ON agent.agent_findings TO pg_diff_agent;
GRANT SELECT ON agent.v_drift TO pg_diff_agent;
GRANT USAGE, SELECT ON SEQUENCE agent.agent_findings_id_seq TO pg_diff_agent;
GRANT USAGE ON SCHEMA public TO pg_diff_agent;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO pg_diff_agent;   -- needed to read column defaults/definitions
