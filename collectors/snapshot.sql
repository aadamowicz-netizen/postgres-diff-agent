-- collectors/snapshot.sql   (domain = 'drift')
-- Run each collection. One snapshot row per configuration setting, extension,
-- and schema object, each with a hash of its definition. Needs no extensions
-- and no elevated privileges beyond SELECT on the objects it describes.
--
-- Object naming (object_name):
--   setting:<name>                     extension:<name>
--   table:<schema>.<table>             column:<schema>.<table>.<column>
--   index:<schema>.<index>             constraint:<schema>.<table>.<constraint>
--   view:<schema>.<view>               function:<schema>.<name>(<args>)
--   sequence:<schema>.<name>           role:<name>
--   grant:<schema>.<table>:<grantee>

WITH ts AS (SELECT now() AS run_ts),

settings AS (
  SELECT 'setting:' || name AS object_name, 'setting' AS kind,
         setting AS definition,
         jsonb_build_object('source', source, 'unit', unit, 'context', context, 'pending_restart', pending_restart) AS extra
  FROM pg_settings
  -- Exclude GUCs that only appear once a session has loaded a library
  -- (plpgsql.* shows up after the first DO block); they flap between runs.
  WHERE name NOT LIKE 'plpgsql.%'
    AND NOT (name LIKE '%.%' AND source = 'default' AND context = 'user'
             AND split_part(name, '.', 1) NOT IN
                 (SELECT trim(unnest(string_to_array(current_setting('shared_preload_libraries'), ','))))
            )
),
extensions AS (
  SELECT 'extension:' || extname, 'extension', extversion, '{}'::jsonb
  FROM pg_extension
),
tables AS (
  SELECT 'table:' || n.nspname || '.' || c.relname, 'table',
         format('relkind=%s owner=%s options=%s partitioned=%s',
                c.relkind, pg_get_userbyid(c.relowner), COALESCE(array_to_string(c.reloptions, ','), '-'),
                (c.relkind = 'p')),
         jsonb_build_object('owner', pg_get_userbyid(c.relowner))
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r','p') AND n.nspname NOT IN ('pg_catalog','information_schema','agent') AND n.nspname NOT LIKE 'pg_toast%'
),
columns AS (
  SELECT 'column:' || n.nspname || '.' || c.relname || '.' || a.attname, 'column',
         format('%s%s%s', format_type(a.atttypid, a.atttypmod),
                CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END,
                CASE WHEN d.adbin IS NOT NULL THEN ' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid) ELSE '' END),
         jsonb_build_object('table', n.nspname || '.' || c.relname)
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attnum > 0 AND NOT a.attisdropped AND c.relkind IN ('r','p')
    AND n.nspname NOT IN ('pg_catalog','information_schema','agent') AND n.nspname NOT LIKE 'pg_toast%'
),
indexes AS (
  SELECT 'index:' || n.nspname || '.' || c.relname, 'index', pg_get_indexdef(c.oid),
         jsonb_build_object('table', n.nspname || '.' || t.relname, 'valid', i.indisvalid)
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  JOIN pg_class t ON t.oid = i.indrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname NOT IN ('pg_catalog','information_schema','agent') AND n.nspname NOT LIKE 'pg_toast%'
),
constraints AS (
  SELECT 'constraint:' || n.nspname || '.' || t.relname || '.' || con.conname, 'constraint',
         pg_get_constraintdef(con.oid),
         jsonb_build_object('table', n.nspname || '.' || t.relname, 'type', con.contype, 'validated', con.convalidated)
  FROM pg_constraint con
  JOIN pg_class t ON t.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname NOT IN ('pg_catalog','information_schema','agent')
),
views AS (
  SELECT 'view:' || n.nspname || '.' || c.relname, 'view', pg_get_viewdef(c.oid, true), '{}'::jsonb
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('v','m') AND n.nspname NOT IN ('pg_catalog','information_schema','agent')
),
functions AS (
  SELECT 'function:' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', 'function',
         pg_get_functiondef(p.oid), jsonb_build_object('language', l.lanname)
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language l ON l.oid = p.prolang
  WHERE n.nspname NOT IN ('pg_catalog','information_schema','agent') AND p.prokind IN ('f','p')
    AND l.lanname <> 'c'
),
sequences AS (
  SELECT 'sequence:' || schemaname || '.' || sequencename, 'sequence',
         format('%s start=%s inc=%s max=%s', data_type, start_value, increment_by, max_value), '{}'::jsonb
  FROM pg_sequences WHERE schemaname NOT IN ('pg_catalog','information_schema','agent')
),
roles AS (
  SELECT 'role:' || rolname, 'role',
         format('super=%s createrole=%s createdb=%s login=%s replication=%s bypassrls=%s connlimit=%s validuntil=%s',
                rolsuper, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit,
                COALESCE(rolvaliduntil::text, 'none')),
         jsonb_build_object('members_of', (SELECT array_agg(b.rolname ORDER BY b.rolname)
                                            FROM pg_auth_members m JOIN pg_roles b ON b.oid = m.roleid
                                           WHERE m.member = r.oid))
  FROM pg_roles r WHERE rolname NOT LIKE 'pg\_%'
),
grants AS (
  SELECT 'grant:' || table_schema || '.' || table_name || ':' || grantee, 'grant',
         string_agg(privilege_type, ',' ORDER BY privilege_type), '{}'::jsonb
  FROM information_schema.role_table_grants
  WHERE table_schema NOT IN ('pg_catalog','information_schema','agent')
  GROUP BY table_schema, table_name, grantee
),
all_objects AS (
  SELECT * FROM settings   UNION ALL SELECT * FROM extensions UNION ALL SELECT * FROM tables
  UNION ALL SELECT * FROM columns  UNION ALL SELECT * FROM indexes  UNION ALL SELECT * FROM constraints
  UNION ALL SELECT * FROM views    UNION ALL SELECT * FROM functions UNION ALL SELECT * FROM sequences
  UNION ALL SELECT * FROM roles    UNION ALL SELECT * FROM grants
)
,inserted AS (
  INSERT INTO agent.agent_findings (run_ts, domain, object_name, metrics, status)
  SELECT ts.run_ts, 'drift', o.object_name,
         jsonb_build_object('kind', o.kind, 'definition', o.definition, 'hash', md5(o.definition)) || o.extra,
         'snapshot'
  FROM all_objects o CROSS JOIN ts
  RETURNING metrics->>'kind' AS kind
)
SELECT kind, count(*) AS objects FROM inserted GROUP BY kind ORDER BY kind;
