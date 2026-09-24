# Player schema and deployment

SQL uses `public.players` as the member store:

| Purpose | Database column |
| --- | --- |
| Stable player identity | `players.member_id` |
| Display name | `players.name` |
| Case-insensitive name lookup | `players.normalized_name` |
| Current MMR | `players.current_mmr` |
| Rating starting point | `players.mmr_baseline` |

The Flutter API retains JSON keys such as `members`, `id`, and `mmr`, and RPC
parameters such as `p_member_id`. These are API names, not separate database
tables. All identity foreign keys and player lookups use `players.member_id`.

Migrations 001-003 initialize the players schema for a new database. For the
existing production database, migrations 002 and 003 verify and adopt its
already installed rating and event objects without recreating them. The
`202609240001_use_players.sql` migration updates the imported club's API
functions, preserving its carryover statistics, balances, and game history.
It saves the replaced function definitions privately and rejects unknown
function versions. It does not require the obsolete `members` table.

The production project's GitHub integration applies pending migrations when
changes are pushed to `main`. Verify the Supabase deployment check after a push;
GitHub Pages deployment alone does not establish that database deployment passed.
Do not rerun initialization SQL or reset migration history on an existing club.

The duplicated standalone repair and its embedded copy were removed. Maintain
the player API upgrade in the single `202609240001_use_players.sql` migration.
After server deployment succeeds, the existing APK can retry startup without
being rebuilt.
