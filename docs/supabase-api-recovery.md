# Recovering the deployed players API

The production database uses `public.players.member_id` for member identity,
`current_mmr` for the current rating, and immutable
`private.member_carryovers.source` for imported statistics. The original
`public.members` schema is not the production member store.

Re-running `202609220001_club.sql` can overwrite newer RPC definitions without
removing the newer tables. In this state, `club_snapshot()` omits the rating and
event version fields. The app rejects that snapshot during startup, before the
member selection screen appears.

## Targeted recovery

`supabase/repairs/20260924_restore_players_api.sql` is a repair for this specific
schema and known overwritten function definitions. It is not an initialization
script or a replacement for the normal migration sequence.

The repository's `deploy-web.yml` deploys Flutter to GitHub Pages only; it does
not apply database SQL. The Supabase project's GitHub connection was also shown
as disconnected during this investigation. Pushing this repair to GitHub alone
therefore does not update the live database. Apply this reviewed file explicitly
in the target project's SQL Editor. Files under `supabase/repairs/` are not
automatically discovered as migrations by `supabase db push`.

- Check the target project and inspect its actual schema before applying it.
- Review the complete transaction, including preflight checks and backups.
- An unknown function definition or incompatible schema must stop the repair;
  investigate the difference rather than removing the guard.
- The repair preserves member data, imported baselines, ratings, and game history.
  It restores function definitions without replaying settlements or refreshing
  balances during deployment.
- Existing function permissions are retained. Original function definitions are
  saved privately so an operator can inspect and restore them if necessary.
- Compare member counts and a deterministic digest of player rows before and
  after deployment. This check reads data without creating test games or users.

After successful recovery, retry startup in the installed app. A server-only
repair does not require a new APK. Do not work around this error by removing the
client's schema checks or substituting default MMR values.

Rollback requires reviewing the saved definitions against the current schema.
Restoring the old snapshot also restores the original startup failure; do not
blindly apply a rollback after unrelated API changes.
