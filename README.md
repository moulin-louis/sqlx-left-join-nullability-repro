# sqlx LEFT JOIN nullability inference bug — minimal repro

sqlx's Postgres `EXPLAIN`-based nullability inference assumes `"Parent
Relationship": "Inner"` in the query plan always means "the null-extended
side of a SQL outer join." That's only true for `Nested Loop` plans. For
`Merge Join`/`Hash Join` plans, `Inner`/`Outer` describe the join
*algorithm's* build/sort side, chosen by cost — independent of which side is
syntactically `LEFT`/`RIGHT` in the SQL. When the planner sorts/builds from
the non-nullable (driving) side, sqlx's patch marks the wrong side nullable
and the genuinely-nullable column is left `NOT NULL`, causing `query!`/
`query_as!` to panic at runtime with `unexpected null; try decoding as an
Option` — even when the Rust field is declared `Option<T>`, since the macro
decodes into its own inferred type first.

## Reproducing

Requires a throwaway Postgres instance (do not point this at anything you
care about) and `sqlx-cli` matching the `sqlx` version in `Cargo.toml`.

```sh
initdb -D /tmp/sqlx-repro-pgdata -U postgres --no-locale
pg_ctl -D /tmp/sqlx-repro-pgdata -l /tmp/sqlx-repro-pgdata/log.txt \
  -o "-p 5544 -k /tmp -h 127.0.0.1" start

createdb -h 127.0.0.1 -p 5544 -U postgres sqlx_repro
psql -h 127.0.0.1 -p 5544 -U postgres -d sqlx_repro -f setup.sql

export DATABASE_URL=postgres://postgres@127.0.0.1:5544/sqlx_repro

cargo sqlx prepare   # regenerates .sqlx/*.json — inspect the `nullable` array
cargo run            # triggers the runtime panic
```

## The plan shape (why this happens)

```sql
EXPLAIN (VERBOSE, FORMAT JSON)
SELECT p.id, u.display_name AS author_display_name
FROM posts_min p
LEFT JOIN users_min u ON u.id = p.author_id;
```

Postgres picks a `Merge Join` (1000 rows in `users_min` vs. 3 in
`posts_min`) and sorts the smaller, driving `posts_min` side:

```json
{
  "Node Type": "Merge Join",
  "Join Type": "Right",
  "Plans": [
    { "Node Type": "Index Scan", "Parent Relationship": "Outer", "Alias": "u", "Output": ["u.id", "u.display_name"] },
    { "Node Type": "Sort", "Parent Relationship": "Inner",
      "Plans": [{ "Node Type": "Seq Scan", "Parent Relationship": "Outer", "Alias": "p" }] }
  ]
}
```

`users_min` (the actually-nullable side of the SQL `LEFT JOIN`) is labeled
`"Outer"`; the `Sort` over `posts_min` (never null-extended) is labeled
`"Inner"`. sqlx's `visit_plan` (`sqlx-postgres/src/connection/describe.rs`)
marks nullable only what's under `"Inner"`, so it marks `p.id` nullable
(harmless false positive) and leaves `author_display_name` as `NOT NULL`
(the dangerous false negative).

## Captured evidence

`.sqlx/query-*.json` → `describe.nullable`: `[true, false]`
— index 0 (`p.id`) is a harmless false positive, index 1
(`author_display_name`, the column that's actually nullable here) is
`false` and should be `true`.

`cargo run` (no offline cache, live query against the row with
`author_id = NULL`):

```
Error: error occurred while decoding column 1: unexpected null; try decoding as an `Option`
```

Tested against PostgreSQL 17.10, sqlx/sqlx-cli 0.9.0.

## Mitigation

Add an explicit `?` override to any `LEFT`/`RIGHT JOIN`ed output column
instead of relying on inference: `u.display_name AS "author_display_name?"`.
