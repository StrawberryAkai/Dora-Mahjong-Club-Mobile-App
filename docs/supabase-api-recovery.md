# Recovering the deployed players API

Production uses `public.players.member_id` for member identity,
`current_mmr` for the current rating, and `private.member_carryovers.source` for
imported statistics. The original `public.members` table remains as an empty
base table and is not the production member store.

Re-running `202609220001_club.sql` can replace newer RPC definitions while
leaving the production tables in place. The app then receives an outdated
`club_snapshot()` and rejects it during startup, before the member selection
screen appears. Do not rerun 001 or rewrite migration history to recover the
API.

## Migration deployment

The production Supabase project is connected to the repository's `main`
branch. New files under `supabase/migrations/` are applied through that
integration; the history currently records 001, while the ratings and events
objects already exist from the manual cutover.

Migrations `202609220002_ratings.sql` and `202609220003_events.sql` support two
schema paths. On a fresh database without `public.players`, each executes its
complete original members-schema SQL. When `public.players` exists, each checks
the canonical schema and its required tables, columns, helpers, and triggers.
Only a complete matching schema is adopted as a no-op so Supabase can record
the pending migration without recreating tables, replaying rating history, or
changing balances. An incomplete or unknown schema stops the migration.

The new `202609240001_restore_players_api.sql` runs the guarded players API
repair when `public.players` exists and is a no-op on a fresh members-schema
database. Its embedded SQL body is copied from
`supabase/repairs/20260924_restore_players_api.sql`, with only that file's
outer `BEGIN` and `COMMIT` removed so Supabase controls the migration
transaction. Keep the embedded body in exact parity with the standalone repair
when either file changes. The standalone file remains available for explicit
review or recovery outside the connected migration flow.

The repair preserves member data, imported baselines, ratings, and game
history. It backs up the affected function definitions and restores the known
players-aware public API without replaying settlements or refreshing balances.
Unknown function definitions or incompatible schema must stop the repair;
investigate the difference instead of removing a guard. Compare member counts
and a deterministic digest of player rows before and after a manual recovery.

After the migration succeeds, retry startup in the installed app. A server-only
repair does not require a new APK. Do not work around the error by removing the
client's schema checks or substituting default MMR values.

Rollback requires reviewing saved function definitions against the current
schema. Restoring the old snapshot also restores the original startup failure;
do not apply a rollback after unrelated API changes without reviewing those
changes.
