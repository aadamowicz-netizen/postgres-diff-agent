# pg-diff-agent

A change-history agent for Postgres. It snapshots settings, extensions, and
every schema object (tables, columns, indexes, constraints, views, functions,
sequences, roles, grants), diffs snapshots, and stores each change as a fact
with before/after and a detection window. A coding agent (Claude Code, Codex,
OpenCode) sits in front of the table so you can ask in plain English:

- what changed in the last 5 days?
- did anyone make a config change?
- anything touch the orders table?
- when did the index on customer_id disappear?

It records; it does not judge and it does not change anything.

```
pg-diff-agent/
├── CLAUDE.md / AGENTS.md   agent entry points (Claude Code / Codex, OpenCode)
├── RULES.md                data model, facts to keep straight, how to answer
├── setup.sql               schema, table, view, optional role   (run once as admin)
├── collectors/
│   ├── snapshot.sql        snapshot every object → status='snapshot'
│   └── diff.sql            compare last two snapshots → status='observed'
├── demo_tables.sql         small demo schema
├── demo_plant.sql          make ~11 changes to detect
└── demo_unplant.sql        reverse them
```

## Setup

```bash
export DATABASE_URL='postgresql://<user>:<pw>@<host>:5432/<db>?sslmode=require'
psql "$DATABASE_URL" -f setup.sql
```

## Demo

```bash
psql "$DATABASE_URL" -f demo_tables.sql
psql "$DATABASE_URL" -f collectors/snapshot.sql     # baseline
psql "$DATABASE_URL" -f collectors/diff.sql         # no-op first time
psql "$DATABASE_URL" -f demo_plant.sql
psql "$DATABASE_URL" -f collectors/snapshot.sql     # new psql session, so ALTER DATABASE settings are visible
psql "$DATABASE_URL" -f collectors/diff.sql         # ~11 observed changes
claude                                              # then ask the questions above
psql "$DATABASE_URL" -f demo_unplant.sql            # reset
```

`demo_plant.sql` assumes the database is named `defaultdb`; edit the two
`ALTER DATABASE` lines otherwise.

## Running unattended (M.A.R.S.)

Environment: Claude Code adapter, this repo, `DATABASE_URL` provided by an
Action Gateway Postgres connection. Trigger: hourly, prompt
"run the collection". Detection granularity equals collection frequency.

## Notes

- Detection time ≠ change time: a change is dated to the window between two
  snapshots.
- Attribution is not available from snapshots; use pgaudit logs for "who".
- Snapshots are ~500 rows per run on a small database. Prune old snapshot
  rows (keep `observed` rows) with the query at the bottom of `collectors/diff.sql`.
