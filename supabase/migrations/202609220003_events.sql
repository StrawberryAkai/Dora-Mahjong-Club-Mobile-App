-- Dora Mahjong Club v0.1 events
--
-- This migration is source only.  It deliberately does not contact a
-- database, apply a migration, or seed production events.

set search_path = public, extensions, pg_catalog;

-- ---------------------------------------------------------------------------
-- Event metadata and the immutable game association.
-- ---------------------------------------------------------------------------

create table public.events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  room_ids text[] not null,
  version integer not null default 0,
  created_at timestamptz not null default now(),
  constraint events_name_trimmed check (name = btrim(name)),
  constraint events_name_length check (char_length(name) between 1 and 80),
  constraint events_description_trimmed check (description = btrim(description)),
  constraint events_description_length check (char_length(description) between 0 and 2000),
  constraint events_starts_finite check (
    starts_at <> 'infinity'::timestamptz
    and starts_at <> '-infinity'::timestamptz
  ),
  constraint events_ends_finite check (
    ends_at <> 'infinity'::timestamptz
    and ends_at <> '-infinity'::timestamptz
  ),
  constraint events_window check (starts_at < ends_at),
  constraint events_room_ids_shape check (
    coalesce(array_ndims(room_ids), 0) = 1
    and cardinality(room_ids) >= 1
  ),
  constraint events_version_nonnegative check (version >= 0)
);

alter table public.games
  add column event_id uuid references public.events(id) on delete restrict;

create index games_event_id_idx
  on public.games(event_id)
  where event_id is not null;

-- Room membership is checked in a private helper so both the RPC and the
-- table trigger enforce the same rule.  The table trigger also protects the
-- invariant from future owner/service-role writes.
create or replace function private.validate_event_room_ids(p_room_ids text[])
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_count integer;
  v_distinct integer;
  v_valid integer;
begin
  if p_room_ids is null
     or coalesce(array_ndims(p_room_ids), 0) <> 1
     or coalesce(cardinality(p_room_ids), 0) < 1 then
    raise exception using errcode = 'P0001', message = '活动至少需要一个房间';
  end if;

  if exists (
    select 1
      from unnest(p_room_ids) as ids(room_id)
     where ids.room_id is null or btrim(ids.room_id) = ''
  ) then
    raise exception using errcode = 'P0001', message = '活动房间编号无效';
  end if;

  select count(*)::integer, count(distinct ids.room_id)::integer
    into v_count, v_distinct
    from unnest(p_room_ids) as ids(room_id);
  if v_count <> v_distinct then
    raise exception using errcode = 'P0001', message = '活动房间不能重复';
  end if;

  select count(*)::integer
    into v_valid
    from public.rooms r
   where r.id = any(p_room_ids);
  if v_valid <> cardinality(p_room_ids) then
    raise exception using errcode = 'P0001', message = '活动包含不存在的房间';
  end if;
end;
$$;

create or replace function private.validate_event_room_ids_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  perform private.validate_event_room_ids(new.room_ids);
  return new;
end;
$$;

create trigger events_room_ids_valid
before insert or update on public.events
for each row execute function private.validate_event_room_ids_trigger();

-- A game is created with its event association in start_game.  Once it has a
-- started_at value the association is immutable, including for cancelled
-- games.  Existing 001/002 games retain NULL event_id.
create or replace function private.prevent_game_event_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.event_id is distinct from old.event_id
     and old.started_at is not null then
    raise exception using errcode = 'P0001', message = '对局开始后不能修改活动关联';
  end if;
  return new;
end;
$$;

create trigger games_event_id_immutable
before update on public.games
for each row execute function private.prevent_game_event_change();

-- ---------------------------------------------------------------------------
-- Administrator event create/edit RPC.
-- ---------------------------------------------------------------------------

create or replace function public.save_event(
  p_event_id uuid,
  p_name text,
  p_description text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_room_ids text[],
  p_expected_version integer,
  p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_allowed_session();
  v_name text := btrim(coalesce(p_name, ''));
  v_description text := btrim(coalesce(p_description, ''));
  v_event_version integer;
  v_game record;
begin
  if not private.is_admin(v_actor) then
    raise exception using errcode = 'P0001', message = '只有管理员可以管理活动';
  end if;

  -- Keep the same global lock ordering as rating lifecycle operations:
  -- rating state, request ledger, event row, then linked game rows.
  perform private.lock_rating_state();
  if not private.claim_request(
    v_actor,
    p_request_id,
    'save_event',
    jsonb_build_object(
      'event_id', p_event_id,
      'name', p_name,
      'description', p_description,
      'starts_at', p_starts_at,
      'ends_at', p_ends_at,
      'room_ids', p_room_ids,
      'expected_version', p_expected_version
    )::text
  ) then
    return;
  end if;

  if char_length(v_name) < 1 or char_length(v_name) > 80 then
    raise exception using errcode = 'P0001', message = '活动名称须为 1–80 个字符';
  end if;
  if char_length(v_description) > 2000 then
    raise exception using errcode = 'P0001', message = '活动说明不能超过 2000 个字符';
  end if;
  if p_starts_at is null or p_ends_at is null
     or p_starts_at = 'infinity'::timestamptz
     or p_starts_at = '-infinity'::timestamptz
     or p_ends_at = 'infinity'::timestamptz
     or p_ends_at = '-infinity'::timestamptz then
    raise exception using errcode = 'P0001', message = '活动时间必须是有限时间';
  end if;
  if p_starts_at >= p_ends_at then
    raise exception using errcode = 'P0001', message = '活动结束时间必须晚于开始时间';
  end if;
  perform private.validate_event_room_ids(p_room_ids);

  if p_event_id is null then
    if p_expected_version is not null then
      raise exception using errcode = 'P0001', message = '新活动不能携带版本号';
    end if;

    insert into public.events(name, description, starts_at, ends_at, room_ids)
    values (v_name, v_description, p_starts_at, p_ends_at, p_room_ids);
    return;
  end if;

  if p_expected_version is null then
    raise exception using errcode = 'P0001', message = '更新活动必须携带版本号';
  end if;

  select e.version
    into v_event_version
    from public.events e
   where e.id = p_event_id
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = '活动不存在';
  end if;
  if v_event_version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = '活动已被其他人更新，请刷新后重试';
  end if;

  -- Lock and validate every linked game, including cancelled games.  This
  -- prevents an edit from shrinking the event scope around an existing link.
  for v_game in
    select g.id, g.room_id, g.started_at
      from public.games g
     where g.event_id = p_event_id
     order by g.id
     for update
  loop
    if not (v_game.room_id = any(p_room_ids)) then
      raise exception using errcode = 'P0001', message = '活动房间范围不能移除已有对局';
    end if;
    if v_game.started_at < p_starts_at or v_game.started_at >= p_ends_at then
      raise exception using errcode = 'P0001', message = '活动时间范围不能移除已有对局';
    end if;
  end loop;

  update public.events
     set name = v_name,
         description = v_description,
         starts_at = p_starts_at,
         ends_at = p_ends_at,
         room_ids = p_room_ids,
         version = v_event_version + 1
   where id = p_event_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Start RPC cutover.  The old two-argument overload is dropped so PostgREST
-- cannot select an ambiguous function.  The event is checked with server
-- time while holding the event row lock and the global rating lock.
-- ---------------------------------------------------------------------------

drop function public.start_game(text, uuid);

create or replace function public.start_game(
  p_room_id text,
  p_request_id uuid,
  p_event_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_allowed_session();
  v_creator uuid;
  v_game uuid;
  v_count integer;
  v_event_starts_at timestamptz;
  v_event_ends_at timestamptz;
  v_event_room_ids text[];
  v_now timestamptz;
begin
  perform private.lock_rating_state();
  if not private.claim_request(
    v_actor,
    p_request_id,
    'start_game',
    case
      -- Keep already accepted casual requests idempotent across the 002 to
      -- 003 cutover; event-linked starts include the complete new input.
      when p_event_id is null then p_room_id
      else jsonb_build_object(
        'room_id', p_room_id,
        'event_id', p_event_id
      )::text
    end
  ) then
    return;
  end if;
  v_creator := private.require_member_actor();

  -- Lock the event before the room/game rows.  An event edit therefore cannot
  -- race the active-window and room-scope check below.
  if p_event_id is not null then
    select e.starts_at, e.ends_at, e.room_ids
      into v_event_starts_at, v_event_ends_at, v_event_room_ids
      from public.events e
     where e.id = p_event_id
     for update;
    if not found then
      raise exception using errcode = 'P0001', message = '活动不存在';
    end if;

    if not (p_room_id = any(v_event_room_ids)) then
      raise exception using errcode = 'P0001', message = '活动不包含所选房间';
    end if;
  end if;

  perform private.lock_room(p_room_id);
  if exists (
    select 1 from public.games g
     where g.room_id = p_room_id and g.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = '该房间已有进行中的对局';
  end if;

  perform 1
    from public.room_seats rs
   where rs.room_id = p_room_id
   for update;
  select count(*) into v_count
    from public.room_seats rs
   where rs.room_id = p_room_id;
  if v_count <> 4 then
    raise exception using errcode = 'P0001', message = '需要四位成员入座后才能开始';
  end if;
  if not exists (
    select 1 from public.room_seats rs
     where rs.room_id = p_room_id and rs.member_id = v_creator
  ) then
    raise exception using errcode = 'P0001', message = '只有在座成员可以开始对局';
  end if;

  -- Take the authoritative start instant only after every lifecycle lock and
  -- seat check.  Store that same instant so a start cannot pass the event
  -- window check while persisting an older transaction-start timestamp.
  v_now := clock_timestamp();
  if p_event_id is not null
     and (v_now < v_event_starts_at or v_now >= v_event_ends_at) then
    raise exception using errcode = 'P0001', message = '活动当前不在进行时间内';
  end if;

  insert into public.games(room_id, creator_id, event_id, started_at)
  values (p_room_id, v_creator, p_event_id, v_now)
  returning id into v_game;

  insert into public.game_players(game_id, member_id, wind)
  select v_game, rs.member_id, rs.wind
    from public.room_seats rs
   where rs.room_id = p_room_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- One-MVCC snapshot with the rating and event JSON contracts.
-- ---------------------------------------------------------------------------

create or replace function public.club_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_allowed_session();
  v_member uuid := private.current_member_id();
  v_is_admin boolean := private.is_admin(v_actor);
  v_admin_name text;
  v_snapshot jsonb;
begin
  select a.username into v_admin_name
    from private.administrators a
   where a.auth_user_id = v_actor
     and a.enabled;

  select jsonb_build_object(
    'event_schema_version', 1,
    'rating_schema_version', 1,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id::text,
        'name', m.name,
        'mmr', m.mmr,
        'mmr_baseline', m.mmr_baseline
      ) order by m.name, m.id)
      from public.members m
    ), '[]'::jsonb),
    'rooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'seats', coalesce((
          select jsonb_object_agg(rs.wind, rs.member_id::text order by private.wind_order(rs.wind))
          from public.room_seats rs
          where rs.room_id = r.id
        ), '{}'::jsonb)
      ) order by r.id)
      from public.rooms r
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id::text,
        'name', e.name,
        'description', e.description,
        'starts_at', e.starts_at,
        'ends_at', e.ends_at,
        'created_at', e.created_at,
        'room_ids', e.room_ids,
        'version', e.version
      ) order by e.starts_at, e.name, e.id)
      from public.events e
    ), '[]'::jsonb),
    'games', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', g.id::text,
        'room_id', g.room_id,
        'event_id', g.event_id::text,
        'creator_id', g.creator_id::text,
        'players', coalesce((
          select jsonb_agg(jsonb_build_object(
            'member_id', gp.member_id::text,
            'name', m.name,
            'wind', gp.wind,
            'score', gp.score,
            'rank', gp.rank
          ) order by private.wind_order(gp.wind))
          from public.game_players gp
          join public.members m on m.id = gp.member_id
          where gp.game_id = g.id
        ), '[]'::jsonb),
        'started_at', g.started_at,
        'status', g.status,
        'completed_at', g.completed_at,
        'cancelled_at', g.cancelled_at,
        'cancel_reason', g.cancel_reason,
        'cancelled_by', g.cancelled_by_name,
        'version', g.version,
        'settlement', (
          select jsonb_build_object(
            'rule_version', rs.rule_version,
            'order', rs.settlement_order,
            'revision', rs.revision,
            'settled_at', rs.settled_at,
            'source_game_id', rs.source_game_id::text,
            'players', coalesce((
              select jsonb_agg(jsonb_build_object(
                'member_id', rp.member_id::text,
                'final_points', rp.final_points,
                'actual_uma', rp.actual_uma,
                'pt', rp.pt,
                'old_mmr', rp.old_mmr,
                'mmr_delta', rp.mmr_delta,
                'new_mmr', rp.new_mmr
              ) order by rp.member_id)
              from public.rating_settlement_players rp
              where rp.settlement_id = rs.id
            ), '[]'::jsonb)
          )
          from public.rating_settlements rs
          where rs.game_id = g.id
          order by rs.revision desc
          limit 1
        ),
        'settlement_history', coalesce((
          select jsonb_agg(jsonb_build_object(
            'rule_version', history.rule_version,
            'order', history.settlement_order,
            'revision', history.revision,
            'settled_at', history.settled_at,
            'source_game_id', history.source_game_id::text,
            'players', coalesce((
              select jsonb_agg(jsonb_build_object(
                'member_id', hp.member_id::text,
                'final_points', hp.final_points,
                'actual_uma', hp.actual_uma,
                'pt', hp.pt,
                'old_mmr', hp.old_mmr,
                'mmr_delta', hp.mmr_delta,
                'new_mmr', hp.new_mmr
              ) order by hp.member_id)
              from public.rating_settlement_players hp
              where hp.settlement_id = history.id
            ), '[]'::jsonb)
          ) order by history.revision)
          from public.rating_settlements history
          where history.game_id = g.id
            and history.revision < coalesce((
              select max(current_revision.revision)
              from public.rating_settlements current_revision
              where current_revision.game_id = g.id
            ), 0)
        ), '[]'::jsonb)
      ) order by g.started_at desc, g.id)
      from public.games g
    ), '[]'::jsonb),
    'audits', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sa.id::text,
        'game_id', sa.game_id::text,
        'actor', sa.actor,
        'at', sa.at,
        'before', sa.before_scores,
        'after', sa.after_scores
      ) order by sa.at desc, sa.id)
      from public.score_audits sa
    ), '[]'::jsonb),
    'member_id', v_member::text,
    'is_admin', v_is_admin,
    'admin_name', v_admin_name
  ) into v_snapshot;

  return v_snapshot;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS and RPC permissions.
-- ---------------------------------------------------------------------------

revoke all on public.events from public, anon, authenticated;
grant select on public.events to authenticated;

alter table public.events enable row level security;

drop policy if exists events_read on public.events;
create policy events_read
  on public.events for select to authenticated using (true);

-- Reassert the privileges for the replaced functions.  The two-argument
-- start_game overload was dropped above; all other 001/002 grants remain the
-- existing authenticated-only boundary.
revoke all on function public.club_snapshot() from public, anon, authenticated;
revoke all on function public.start_game(text, uuid, uuid) from public, anon, authenticated;
revoke all on function public.save_event(
  uuid, text, text, timestamptz, timestamptz, text[], integer, uuid
) from public, anon, authenticated;

grant execute on function public.club_snapshot() to authenticated;
grant execute on function public.start_game(text, uuid, uuid) to authenticated;
grant execute on function public.save_event(
  uuid, text, text, timestamptz, timestamptz, text[], integer, uuid
) to authenticated;

revoke all on function private.validate_event_room_ids(text[])
  from public, anon, authenticated;
revoke all on function private.validate_event_room_ids_trigger()
  from public, anon, authenticated;
revoke all on function private.prevent_game_event_change()
  from public, anon, authenticated;
