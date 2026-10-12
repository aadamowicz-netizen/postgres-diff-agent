-- migrate_v_drift.sql — one-time update for existing installs: adds table_name to the view.
-- (Existing observed rows created before this change will have NULL table_name;
--  name/definition matching still finds them.)
DROP VIEW IF EXISTS agent.v_drift;
CREATE VIEW agent.v_drift AS
SELECT run_ts, object_name, status,
       metrics->>'kind'                                    AS kind,
       COALESCE(diagnosis, 'snapshot')                     AS change,
       metrics->>'before'                                  AS before,
       COALESCE(metrics->>'after', metrics->>'definition') AS after,
       (metrics->>'previous_run')::timestamptz             AS previous_run,
       metrics->>'source'                                  AS source,
       metrics->>'table'                                   AS table_name
FROM agent.agent_findings
WHERE domain = 'drift';
GRANT SELECT ON agent.v_drift TO pg_diff_agent;
