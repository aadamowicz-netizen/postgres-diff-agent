-- collectors/diff.sql   (domain = 'drift')
-- Run immediately after snapshot.sql. Compares the two most recent snapshots and
-- inserts one 'observed' row per difference. Rows are neutral facts; no
-- severity is set (see RULES.md).

WITH runs AS (
  SELECT DISTINCT run_ts FROM agent.agent_findings
  WHERE domain = 'drift' AND status = 'snapshot'
  ORDER BY run_ts DESC LIMIT 2
),
latest AS (SELECT max(run_ts) AS ts FROM runs),
previous AS (SELECT min(run_ts) AS ts FROM runs),
cur AS (
  SELECT object_name, metrics FROM agent.agent_findings, latest
  WHERE domain = 'drift' AND status = 'snapshot' AND run_ts = latest.ts
),
prev AS (
  SELECT object_name, metrics FROM agent.agent_findings, previous
  WHERE domain = 'drift' AND status = 'snapshot' AND run_ts = previous.ts
),
diff AS (
  SELECT COALESCE(c.object_name, p.object_name) AS object_name,
         CASE WHEN p.object_name IS NULL THEN 'added'
              WHEN c.object_name IS NULL THEN 'removed'
              ELSE 'changed' END AS change,
         p.metrics AS before, c.metrics AS after
  FROM cur c FULL OUTER JOIN prev p ON p.object_name = c.object_name
  WHERE p.object_name IS NULL OR c.object_name IS NULL
     OR (c.metrics->>'hash') <> (p.metrics->>'hash')
)
INSERT INTO agent.agent_findings
  (run_ts, domain, object_name, metrics, diagnosis, evidence, status, status_changed_at)
SELECT latest.ts, 'drift', d.object_name,
       jsonb_build_object('kind', COALESCE(d.after->>'kind', d.before->>'kind'),
                          'change', d.change,
                          'before', d.before->>'definition',
                          'after',  d.after->>'definition',
                          'source', COALESCE(d.after->>'source', d.before->>'source'),
                          'previous_run', previous.ts),
       d.change,
       format('%s %s%s%s',
              COALESCE(d.after->>'kind', d.before->>'kind'), d.change,
              CASE WHEN d.before IS NOT NULL THEN E'\n  before: ' || (d.before->>'definition') ELSE '' END,
              CASE WHEN d.after  IS NOT NULL THEN E'\n  after:  ' || (d.after->>'definition')  ELSE '' END),
       'observed', now()
FROM diff d, latest, previous
WHERE (SELECT count(*) FROM runs) = 2          -- no-op on the very first run
RETURNING object_name, diagnosis;

-- Answering "what changed in the last N days":
--   SELECT run_ts, previous_run, kind, object_name, change, before, after FROM agent.v_drift
--    WHERE status = 'observed' AND run_ts > now() - interval '5 days'
--    ORDER BY run_ts, object_name;
--
-- Trimming history: snapshots are ~1 row per object per run. Keep observed
-- rows forever; prune snapshot rows older than 30 days:
--   DELETE FROM agent.agent_findings WHERE domain='drift' AND status='snapshot' AND run_ts < now() - interval '30 days';
