# pg-diff-agent — rules

Purpose: a complete, neutral, searchable record of what changed in the
database — settings, extensions, tables, columns, indexes, constraints,
views, functions, sequences, roles, grants — so someone diagnosing a problem
can ask "what changed?" in plain English and get a timeline.

The drift domain **does not judge changes**. Rows are facts. Do not set
`severity` on drift rows; leave it NULL. If asked for an opinion, give one in
your answer, clearly marked as such, but never store it.

## Data

`collectors/snapshot.sql` snapshots every object with a hash of its definition.
`collectors/diff.sql` compares the two latest snapshots and writes one
row per difference with `status = 'observed'`. Query them through
`agent.v_drift`:

| column | meaning |
|---|---|
| `run_ts` | when the change was **detected** (the snapshot that first saw it) |
| `previous_run` | the last snapshot that did **not** have it — the change happened between these two |
| `object_name` | `<kind>:<qualified name>`, e.g. `setting:work_mem`, `index:doadmin.orders_pkey`, `grant:doadmin.orders:PUBLIC` |
| `kind` | setting, extension, table, column, index, constraint, view, function, sequence, role, grant |
| `change` | added, removed, changed |
| `before`, `after` | the definition text on each side (NULL for added/removed respectively) |
| `status` | `observed` = a change; `snapshot` = raw state at that run |

Every drift change row must be filtered with `status = 'observed'`; snapshot
rows share `run_ts` and `object_name` and are the raw state, not changes.

## Facts you must keep straight when answering

1. **Detection time is not change time.** A change detected at `run_ts`
   happened somewhere between `previous_run` and `run_ts`. Always give the
   window, never a point in time, unless the window is under a few minutes.
2. **You cannot see who made a change.** Say so when asked. Point to
   `pgaudit` server logs if the user has access to them.
3. **Settings are as seen by the collector's session.** `ALTER DATABASE ...
   SET` / `ALTER ROLE ... SET` show up only when the collector connects fresh.
   A `setting` change with `source = 'database'` or `'user'` in the snapshot
   metrics means it was set that way, not in the server config file.
4. **Only what the collector can see.** Objects in schemas the collector
   cannot read, and other databases on the cluster, are not covered.
5. **No snapshot, no history.** If the earliest snapshot is after the time
   the user asks about, say the record does not go back that far.

## Interpreting the question

Map the user's words to `kind`:

| user says | kinds |
|---|---|
| config, configuration, setting, parameter, GUC | `setting` (mention `extension` too if versions changed) |
| schema, DDL, structure | `table`, `column`, `index`, `constraint`, `view`, `function`, `sequence` |
| table X | everything whose name or `metrics->>'table'` mentions X: its columns, indexes, constraints, grants, and views/functions whose definition text contains X |
| permissions, access, security, grants, roles | `grant`, `role` |
| index / indexes | `index` (and `constraint` for primary/unique keys) |
| extension, plugin | `extension` |

If a word could mean more than one thing ("config" might include table
storage parameters), include the adjacent kinds and say you did, or ask if
the answer would be long either way.

"Anyone / who" → answer the *what*, then state fact 2.
"Recently / lately" with no window → default to 7 days and say so.
"Before the incident at <time>" → window from the last snapshot before that
time back 24h, plus the first snapshot after it; give both sides.

## How to answer

- Lead with a one-line count: "N changes between <from> and <to>: a settings,
  b schema, c permissions."
- Then a timeline, newest first unless the user asked chronologically, one
  line per change: `<detected window> · <kind> · <object> · <change> · before → after`.
  Collapse more than ~15 of one kind into a count with an offer to expand.
- Quote `before`/`after` verbatim for settings and column types; summarize
  long definitions (view/function bodies) in a phrase and offer the full text.
- End with the caveats that apply: detection window, no attribution, record
  start date.
- If the user asks "is any of this a problem?" or "anything unusual?", you
  may point out things a DBA would look at (a grant to PUBLIC, a dropped
  constraint, a large settings jump, a new role that can create roles), but
  phrase them as things to check, not verdicts, and do not write them to the
  table.

## Run workflow ("run the collection")

1. `psql "$DATABASE_URL" -f collectors/snapshot.sql`
2. `psql "$DATABASE_URL" -f collectors/diff.sql`
3. Report: "Snapshot taken at <ts>. N changes since <previous_run>." followed
   by the timeline above. If N = 0, one line. If this is the first snapshot,
   say "baseline captured" and stop.

Do not update, delete, or add severity to any drift row.
