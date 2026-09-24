-- Dora Mahjong Club v0.1
--
-- Canonical player identity and core club RPCs. Apply through the versioned
-- migration sequence; existing projects receive changes in later migrations.

create extension if not exists pgcrypto;

create schema if not exists private;

set search_path = public, extensions, pg_catalog;

-- ---------------------------------------------------------------------------
-- Public read models.  All writes go through the RPCs below.
-- ---------------------------------------------------------------------------

create table if not exists public.players (
  member_id uuid primary key default gen_random_uuid(),
  name text not null,
  normalized_name text not null,
  created_at timestamptz not null default now(),
  constraint players_name_length check (char_length(name) between 1 and 20),
  constraint players_name_characters check (name ~ '^[A-Za-z㐀-䶿一-鿿𠀀-𯨟]+$'),
  constraint players_normalized_name check (normalized_name = lower(btrim(name))),
  constraint players_normalized_name_unique unique (normalized_name)
);

create table if not exists public.rooms (
  id text primary key,
  name text not null,
  created_at timestamptz not null default now(),
  constraint rooms_name_length check (char_length(btrim(name)) between 1 and 30)
);

create table if not exists public.room_seats (
  room_id text not null references public.rooms(id) on delete cascade,
  wind text not null,
  member_id uuid not null references public.players(member_id) on delete restrict,
  seated_at timestamptz not null default now(),
  primary key (room_id, wind),
  constraint room_seats_wind check (wind in ('east', 'south', 'west', 'north')),
  constraint room_seats_member_unique unique (member_id)
);

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  room_id text not null references public.rooms(id) on delete restrict,
  creator_id uuid not null references public.players(member_id) on delete restrict,
  status text not null default 'active',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  cancelled_by uuid,
  cancelled_by_name text,
  version integer not null default 0,
  constraint games_status check (status in ('active', 'completed', 'cancelled')),
  constraint games_version_nonnegative check (version >= 0),
  constraint games_cancel_reason_length check (cancel_reason is null or char_length(btrim(cancel_reason)) between 1 and 500),
  constraint games_lifecycle_fields check (
    (status = 'active' and completed_at is null and cancelled_at is null and cancel_reason is null and cancelled_by is null and cancelled_by_name is null)
    or (status = 'completed' and completed_at is not null and cancelled_at is null and cancel_reason is null and cancelled_by is null and cancelled_by_name is null)
    or (status = 'cancelled' and completed_at is null and cancelled_at is not null and cancel_reason is not null and cancelled_by is not null and cancelled_by_name is not null)
  )
);

create unique index if not exists games_one_active_per_room
  on public.games(room_id)
  where status = 'active';

create table if not exists public.game_players (
  game_id uuid not null references public.games(id) on delete cascade,
  member_id uuid not null references public.players(member_id) on delete restrict,
  wind text not null,
  score integer,
  rank integer,
  primary key (game_id, member_id),
  constraint game_players_wind check (wind in ('east', 'south', 'west', 'north')),
  constraint game_players_wind_unique unique (game_id, wind),
  constraint game_players_score_multiple check (score is null or score % 100 = 0),
  constraint game_players_rank_range check (rank is null or rank between 1 and 4)
);

create table if not exists public.score_audits (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete restrict,
  actor_auth_id uuid not null,
  actor text not null,
  at timestamptz not null default now(),
  before_scores jsonb not null,
  after_scores jsonb not null,
  constraint score_audits_before_object check (jsonb_typeof(before_scores) = 'object'),
  constraint score_audits_after_object check (jsonb_typeof(after_scores) = 'object')
);

-- The fixed room IDs are stable historical identifiers.  The display names
-- can be changed by an administrator without changing these relationships.
insert into public.rooms (id, name)
values ('7699', '7699'), ('9162', '9162')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Private identity and idempotency state.
-- ---------------------------------------------------------------------------

create table if not exists private.session_members (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  member_id uuid not null references public.players(member_id) on delete restrict,
  selected_at timestamptz not null default now()
);

create table if not exists private.administrators (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint administrators_username_format check (username ~ '^[a-z0-9_-]{3,32}$'),
  constraint administrators_username_unique unique (username)
);

create table if not exists private.request_ledger (
  actor_id uuid not null,
  request_id uuid not null,
  operation text not null,
  fingerprint text not null,
  created_at timestamptz not null default now(),
  primary key (actor_id, request_id)
);

-- ---------------------------------------------------------------------------
-- Small locked helpers.  Every callable function fixes search_path so an
-- untrusted caller cannot shadow a name used by SECURITY DEFINER code.
-- ---------------------------------------------------------------------------

create or replace function private.current_actor_id()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception using errcode = 'P0001', message = '请先登录';
  end if;
  return v_actor;
end;
$$;

create or replace function private.is_admin(p_actor uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1
    from private.administrators a
    where a.auth_user_id = p_actor
      and a.enabled
  );
$$;

create or replace function private.require_allowed_session()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.current_actor_id();
begin
  if private.is_admin(v_actor) then
    return v_actor;
  end if;

  -- Anonymous Auth sessions are the only ordinary-member sessions in v0.1.
  -- A permanent non-admin account must never silently acquire member powers.
  if coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true' then
    raise exception using errcode = 'P0001', message = '此账号不是俱乐部管理员，请退出后使用成员身份';
  end if;
  return v_actor;
end;
$$;

create or replace function private.require_member_actor()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_allowed_session();
  v_member uuid;
begin
  if private.is_admin(v_actor) then
    raise exception using errcode = 'P0001', message = '管理员账号不占座，请先使用普通成员身份';
  end if;

  select sm.member_id
    into v_member
    from private.session_members sm
   where sm.auth_user_id = v_actor;

  if v_member is null then
    raise exception using errcode = 'P0001', message = '请先选择成员';
  end if;
  return v_member;
end;
$$;

create or replace function private.require_anonymous_actor()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.current_actor_id();
begin
  if private.is_admin(v_actor) then
    raise exception using errcode = 'P0001', message = '管理员请使用独立账号';
  end if;
  if coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true' then
    raise exception using errcode = 'P0001', message = '此账号不能使用普通成员流程';
  end if;
  return v_actor;
end;
$$;

create or replace function private.current_member_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select sm.member_id
  from private.session_members sm
  where sm.auth_user_id = auth.uid()
    and not private.is_admin(auth.uid());
$$;

create or replace function private.actor_label(p_actor uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_label text;
begin
  select a.username
    into v_label
    from private.administrators a
   where a.auth_user_id = p_actor
     and a.enabled;
  if v_label is not null then
    return v_label;
  end if;

  select m.name
    into v_label
    from private.session_members sm
    join public.players m on m.member_id = sm.member_id
   where sm.auth_user_id = p_actor;
  if v_label is not null then
    return v_label;
  end if;

  raise exception using errcode = 'P0001', message = '找不到操作人身份';
end;
$$;

create or replace function private.normalize_member_name(p_name text)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public, private
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
begin
  if char_length(v_name) < 1 or char_length(v_name) > 20
     or v_name !~ '^[A-Za-z㐀-䶿一-鿿𠀀-𯨟]+$' then
    raise exception using errcode = 'P0001', message = '姓名须为 1–20 个中文或英文字母，不能含数字、空格或符号';
  end if;
  return lower(v_name);
end;
$$;

create or replace function private.require_room_name(p_name text)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public, private
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
begin
  if char_length(v_name) < 1 or char_length(v_name) > 30 then
    raise exception using errcode = 'P0001', message = '房间名称不能为空，长度不能超过 30 个字符';
  end if;
  return v_name;
end;
$$;

create or replace function private.require_wind(p_wind text)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public, private
as $$
begin
  if p_wind not in ('east', 'south', 'west', 'north') then
    raise exception using errcode = 'P0001', message = '无效的座位';
  end if;
  return p_wind;
end;
$$;

create or replace function private.lock_room(p_room_id text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_room_id text;
begin
  select r.id into v_room_id
    from public.rooms r
   where r.id = p_room_id
   for update;
  if v_room_id is null then
    raise exception using errcode = 'P0001', message = '房间不存在';
  end if;
end;
$$;

create or replace function private.assert_score(p_score integer)
returns integer
language plpgsql
immutable
set search_path = pg_catalog, public, private
as $$
begin
  if p_score is null or p_score % 100 <> 0 then
    raise exception using errcode = 'P0001', message = '点数必须是 100 的倍数';
  end if;
  return p_score;
end;
$$;

create or replace function private.wind_order(p_wind text)
returns integer
language sql
immutable
set search_path = pg_catalog, public, private
as $$
  select case p_wind
    when 'east' then 1
    when 'south' then 2
    when 'west' then 3
    when 'north' then 4
    else 99
  end;
$$;

create or replace function private.claim_request(
  p_actor uuid,
  p_request_id uuid,
  p_operation text,
  p_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_inserted integer;
  v_existing_operation text;
  v_existing text;
begin
  if p_request_id is null then
    raise exception using errcode = 'P0001', message = '请求编号不能为空';
  end if;

  insert into private.request_ledger(actor_id, request_id, operation, fingerprint)
  values (p_actor, p_request_id, p_operation, p_fingerprint)
  on conflict (actor_id, request_id) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return true;
  end if;

  select rl.operation, rl.fingerprint
    into v_existing_operation, v_existing
    from private.request_ledger rl
   where rl.actor_id = p_actor
     and rl.request_id = p_request_id;

  if v_existing_operation is distinct from p_operation or v_existing is distinct from p_fingerprint then
    raise exception using errcode = 'P0001', message = '请求编号已用于其他操作';
  end if;
  return false;
end;
$$;

create or replace function private.raise_duplicate_name()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  raise exception using errcode = 'P0001', message = '姓名已存在';
end;
$$;

-- ---------------------------------------------------------------------------
-- Snapshot RPC.  A single JSON document is built by one MVCC statement, so
-- the client never combines separately-read rooms, games, and audits.
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
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.member_id::text,
        'name', m.name
      ) order by m.name, m.member_id)
      from public.players m
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
    'games', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', g.id::text,
        'room_id', g.room_id,
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
          join public.players m on m.member_id = gp.member_id
          where gp.game_id = g.id
        ), '[]'::jsonb),
        'started_at', g.started_at,
        'status', g.status,
        'completed_at', g.completed_at,
        'cancelled_at', g.cancelled_at,
        'cancel_reason', g.cancel_reason,
        'cancelled_by', g.cancelled_by_name,
        'version', g.version
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
-- Ordinary member identity RPCs.
-- ---------------------------------------------------------------------------

create or replace function public.create_member(p_name text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_anonymous_actor();
  v_name text := btrim(coalesce(p_name, ''));
  v_normalized text := private.normalize_member_name(p_name);
  v_member uuid;
begin
  begin
    insert into public.players(name, normalized_name)
    values (v_name, v_normalized)
    returning member_id into v_member;
  exception when unique_violation then
    perform private.raise_duplicate_name();
  end;

  insert into private.session_members(auth_user_id, member_id, selected_at)
  values (v_actor, v_member, now())
  on conflict (auth_user_id) do update
    set member_id = excluded.member_id,
        selected_at = excluded.selected_at;
end;
$$;

create or replace function public.select_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_allowed_session();
begin
  if private.is_admin(v_actor) then
    raise exception using errcode = 'P0001', message = '管理员请使用独立账号';
  end if;
  if coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true' then
    raise exception using errcode = 'P0001', message = '此账号不能选择普通成员';
  end if;
  if not exists (select 1 from public.players m where m.member_id = p_member_id) then
    raise exception using errcode = 'P0001', message = '成员不存在';
  end if;

  insert into private.session_members(auth_user_id, member_id, selected_at)
  values (v_actor, p_member_id, now())
  on conflict (auth_user_id) do update
    set member_id = excluded.member_id,
        selected_at = excluded.selected_at;
end;
$$;

create or replace function public.clear_member()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_allowed_session();
begin
  if private.is_admin(v_actor) then
    raise exception using errcode = 'P0001', message = '管理员请直接退出管理员账号';
  end if;
  delete from private.session_members where auth_user_id = v_actor;
end;
$$;

-- ---------------------------------------------------------------------------
-- Seating and game lifecycle RPCs.
-- ---------------------------------------------------------------------------

create or replace function public.sit_down(p_room_id text, p_wind text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_member uuid := private.require_member_actor();
  v_wind text := private.require_wind(p_wind);
  v_existing uuid;
begin
  -- The room lock serializes seat changes with starts and the member advisory
  -- lock serializes the same member trying to sit in two different rooms.
  perform pg_advisory_xact_lock(hashtext(v_member::text));
  perform private.lock_room(p_room_id);
  if exists (select 1 from public.games g where g.room_id = p_room_id and g.status = 'active') then
    raise exception using errcode = 'P0001', message = '对局进行中，暂不能调整座位';
  end if;

  select rs.member_id into v_existing
    from public.room_seats rs
   where rs.room_id = p_room_id and rs.wind = v_wind
   for update;
  if v_existing is not null and v_existing <> v_member then
    raise exception using errcode = 'P0001', message = '该座位已被占用';
  end if;
  if exists (
    select 1 from public.room_seats rs
    where rs.member_id = v_member
      and (rs.room_id <> p_room_id or rs.wind <> v_wind)
  ) then
    raise exception using errcode = 'P0001', message = '同一成员不能同时坐在两个房间';
  end if;

  insert into public.room_seats(room_id, wind, member_id)
  values (p_room_id, v_wind, v_member)
  on conflict (room_id, wind) do nothing;
end;
$$;

create or replace function public.leave_seat(p_room_id text, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_allowed_session();
  v_admin boolean := private.is_admin(v_actor);
  v_member uuid;
begin
  perform private.lock_room(p_room_id);
  if exists (select 1 from public.games g where g.room_id = p_room_id and g.status = 'active') then
    raise exception using errcode = 'P0001', message = '对局进行中，暂不能离座';
  end if;

  if v_admin then
    if p_member_id is null then
      raise exception using errcode = 'P0001', message = '管理员清理座位时必须指定成员';
    end if;
    v_member := p_member_id;
  else
    if coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true' then
      raise exception using errcode = 'P0001', message = '此账号不能操作座位';
    end if;
    v_member := private.require_member_actor();
    if p_member_id is not null and p_member_id <> v_member then
      raise exception using errcode = 'P0001', message = '普通成员只能离开自己的座位';
    end if;
  end if;

  delete from public.room_seats
   where room_id = p_room_id and member_id = v_member;
end;
$$;

create or replace function public.start_game(p_room_id text, p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_creator uuid;
  v_game uuid;
  v_count integer;
begin
  if not private.claim_request(auth.uid(), p_request_id, 'start_game', p_room_id) then
    return;
  end if;
  v_creator := private.require_member_actor();

  perform private.lock_room(p_room_id);
  if exists (select 1 from public.games g where g.room_id = p_room_id and g.status = 'active') then
    raise exception using errcode = 'P0001', message = '该房间已有进行中的对局';
  end if;

  perform 1 from public.room_seats rs where rs.room_id = p_room_id for update;
  select count(*) into v_count from public.room_seats rs where rs.room_id = p_room_id;
  if v_count <> 4 then
    raise exception using errcode = 'P0001', message = '需要四位成员入座后才能开始';
  end if;
  if not exists (
    select 1 from public.room_seats rs
    where rs.room_id = p_room_id and rs.member_id = v_creator
  ) then
    raise exception using errcode = 'P0001', message = '只有在座成员可以开始对局';
  end if;

  insert into public.games(room_id, creator_id)
  values (p_room_id, v_creator)
  returning id into v_game;

  insert into public.game_players(game_id, member_id, wind)
  select v_game, rs.member_id, rs.wind
    from public.room_seats rs
   where rs.room_id = p_room_id;
end;
$$;

create or replace function public.save_score(
  p_game_id uuid,
  p_member_id uuid,
  p_score integer,
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
  v_member uuid := private.current_member_id();
  v_admin boolean := private.is_admin(v_actor);
  v_creator uuid;
  v_status text;
  v_version integer;
  v_count integer;
  v_total bigint;
  v_next_version integer;
begin
  if not private.claim_request(v_actor, p_request_id, 'save_score', p_game_id::text || ':' || p_member_id::text || ':' || p_score::text || ':' || p_expected_version::text) then
    return;
  end if;
  perform private.assert_score(p_score);

  select g.creator_id, g.status, g.version
    into v_creator, v_status, v_version
    from public.games g
   where g.id = p_game_id
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = '对局不存在';
  end if;
  if v_status <> 'active' then
    raise exception using errcode = 'P0001', message = '该对局已经结束，需使用更正流程';
  end if;
  if v_version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = '对局已被其他人更新，请刷新后重试';
  end if;
  if not exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.member_id = p_member_id) then
    raise exception using errcode = 'P0001', message = '该成员不在本场对局中';
  end if;
  if not v_admin and (v_member is null or (p_member_id <> v_member and v_creator <> v_member)) then
    raise exception using errcode = 'P0001', message = '没有代填该成员成绩的权限';
  end if;

  update public.game_players
     set score = p_score, rank = null
   where game_id = p_game_id and member_id = p_member_id;
  select count(gp.score), coalesce(sum(gp.score), 0)
    into v_count, v_total
    from public.game_players gp
   where gp.game_id = p_game_id;

  v_next_version := v_version + 1;
  if v_count = 4 and v_total = 100000 then
    with ranked as (
      select gp.member_id,
             row_number() over (order by gp.score desc, private.wind_order(gp.wind))::integer as rank
        from public.game_players gp
       where gp.game_id = p_game_id
    )
    update public.game_players gp
       set rank = ranked.rank
      from ranked
     where gp.game_id = p_game_id and gp.member_id = ranked.member_id;

    update public.games
       set status = 'completed', completed_at = now(), version = v_next_version
     where id = p_game_id;
  else
    update public.games set version = v_next_version where id = p_game_id;
  end if;
end;
$$;

create or replace function public.correct_scores(
  p_game_id uuid,
  p_scores jsonb,
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
  v_member uuid := private.current_member_id();
  v_admin boolean := private.is_admin(v_actor);
  v_creator uuid;
  v_status text;
  v_version integer;
  v_before jsonb;
  v_after jsonb;
  v_key text;
  v_value text;
  v_member_id uuid;
  v_score integer;
  v_player_count integer;
  v_input_count integer;
  v_total bigint;
begin
  if not private.claim_request(v_actor, p_request_id, 'correct_scores', p_game_id::text || ':' || coalesce(p_scores::text, 'null') || ':' || p_expected_version::text) then
    return;
  end if;
  if p_scores is null or jsonb_typeof(p_scores) <> 'object' then
    raise exception using errcode = 'P0001', message = '更正成绩格式无效';
  end if;

  select g.creator_id, g.status, g.version
    into v_creator, v_status, v_version
    from public.games g
   where g.id = p_game_id
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = '对局不存在';
  end if;
  if v_status <> 'completed' then
    raise exception using errcode = 'P0001', message = '只有已完成对局可以更正';
  end if;
  if v_version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = '对局已被其他人更新，请刷新后重试';
  end if;
  if not v_admin and (v_member is null or v_creator <> v_member) then
    raise exception using errcode = 'P0001', message = '只有本场创建者或管理员可以更正成绩';
  end if;

  select jsonb_object_agg(gp.member_id::text, gp.score order by gp.member_id)
    into v_before
    from public.game_players gp
   where gp.game_id = p_game_id;
  select count(*) into v_player_count from public.game_players gp where gp.game_id = p_game_id;
  select count(*) into v_input_count from jsonb_object_keys(p_scores);
  if v_player_count <> 4 or v_input_count <> v_player_count then
    raise exception using errcode = 'P0001', message = '请一次提交本场四位成员的成绩';
  end if;

  for v_key, v_value in select key, value from jsonb_each_text(p_scores) loop
    begin
      v_member_id := v_key::uuid;
    exception when invalid_text_representation then
      raise exception using errcode = 'P0001', message = '更正成绩包含无效成员';
    end;
    if v_value !~ '^-?[0-9]+$' then
      raise exception using errcode = 'P0001', message = '成绩必须是整数';
    end if;
    v_score := v_value::integer;
    perform private.assert_score(v_score);
    update public.game_players
       set score = v_score, rank = null
     where game_id = p_game_id and member_id = v_member_id;
    if not found then
      raise exception using errcode = 'P0001', message = '更正成绩包含非本场成员';
    end if;
  end loop;

  select coalesce(sum(gp.score), 0) into v_total
    from public.game_players gp where gp.game_id = p_game_id;
  if v_total <> 100000 or exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.score is null) then
    raise exception using errcode = 'P0001', message = '更正后四人成绩合计必须为 100,000';
  end if;

  with ranked as (
    select gp.member_id,
           row_number() over (order by gp.score desc, private.wind_order(gp.wind))::integer as rank
      from public.game_players gp
     where gp.game_id = p_game_id
  )
  update public.game_players gp
     set rank = ranked.rank
    from ranked
   where gp.game_id = p_game_id and gp.member_id = ranked.member_id;

  select jsonb_object_agg(gp.member_id::text, gp.score order by gp.member_id)
    into v_after
    from public.game_players gp
   where gp.game_id = p_game_id;
  insert into public.score_audits(game_id, actor_auth_id, actor, at, before_scores, after_scores)
  values (p_game_id, v_actor, private.actor_label(v_actor), clock_timestamp(), v_before, v_after);
  update public.games set version = v_version + 1 where id = p_game_id;
end;
$$;

create or replace function public.cancel_game(
  p_game_id uuid,
  p_reason text,
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
  v_member uuid := private.current_member_id();
  v_admin boolean := private.is_admin(v_actor);
  v_creator uuid;
  v_status text;
  v_version integer;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if not private.claim_request(v_actor, p_request_id, 'cancel_game', p_game_id::text || ':' || v_reason || ':' || p_expected_version::text) then
    return;
  end if;
  if char_length(v_reason) < 1 or char_length(v_reason) > 500 then
    raise exception using errcode = 'P0001', message = '取消原因不能为空，长度不能超过 500 个字符';
  end if;

  select g.creator_id, g.status, g.version
    into v_creator, v_status, v_version
    from public.games g
   where g.id = p_game_id
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = '对局不存在';
  end if;
  if v_status <> 'active' then
    raise exception using errcode = 'P0001', message = '只有进行中的对局可以取消';
  end if;
  if v_version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = '对局已被其他人更新，请刷新后重试';
  end if;
  if not v_admin and (v_member is null or v_creator <> v_member) then
    raise exception using errcode = 'P0001', message = '只有本场创建者或管理员可以取消对局';
  end if;

  update public.games
     set status = 'cancelled',
         cancelled_at = now(),
         cancel_reason = v_reason,
         cancelled_by = v_actor,
         cancelled_by_name = private.actor_label(v_actor),
         version = v_version + 1
   where id = p_game_id;
end;
$$;

create or replace function public.rename_room(p_room_id text, p_name text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := private.require_allowed_session();
  v_name text := private.require_room_name(p_name);
begin
  if not private.is_admin(v_actor) then
    raise exception using errcode = 'P0001', message = '只有管理员可以修改房间名称';
  end if;
  update public.rooms set name = v_name where id = p_room_id;
  if not found then
    raise exception using errcode = 'P0001', message = '房间不存在';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Service-only admin provisioning wrapper.  It is intentionally unusable by
-- the mobile client; the script calls it with a service-role key after the
-- Auth user has been created or reset through the Auth admin API.
-- ---------------------------------------------------------------------------

create or replace function public.provision_admin(
  p_username text,
  p_auth_user_id uuid,
  p_is_new_auth_user boolean default false
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_username text := lower(btrim(coalesce(p_username, '')));
  v_email text;
  v_existing uuid;
begin
  if coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = '仅服务端初始化脚本可以配置管理员';
  end if;
  if v_username !~ '^[a-z0-9_-]{3,32}$' then
    raise exception using errcode = 'P0001', message = '管理员用户名须为 3–32 位小写字母、数字、下划线或短横线';
  end if;
  if p_auth_user_id is null then
    raise exception using errcode = 'P0001', message = '管理员 Auth 用户不存在';
  end if;
  v_email := v_username || '@admin.dora.invalid';
  if not exists (
    select 1 from auth.users u where u.id = p_auth_user_id and lower(u.email) = v_email
  ) then
    raise exception using errcode = 'P0001', message = 'Auth 用户与管理员用户名不匹配';
  end if;

  select a.auth_user_id into v_existing
    from private.administrators a
   where a.username = v_username;
  if v_existing is null and not coalesce(p_is_new_auth_user, false) then
    raise exception using errcode = 'P0001', message = '已有 Auth 账号尚未配置为管理员，请选择未使用的用户名';
  end if;
  if v_existing is not null and v_existing <> p_auth_user_id then
    raise exception using errcode = 'P0001', message = '管理员用户名已绑定其他 Auth 用户';
  end if;

  insert into private.administrators(auth_user_id, username, enabled, updated_at)
  values (p_auth_user_id, v_username, true, now())
  on conflict (auth_user_id) do update
    set username = excluded.username,
        enabled = true,
        updated_at = excluded.updated_at;
end;
$$;

create or replace function public.admin_identity_status(
  p_username text,
  p_auth_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_username text := lower(btrim(coalesce(p_username, '')));
begin
  if coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = '仅服务端初始化脚本可以查询管理员配置';
  end if;
  if v_username !~ '^[a-z0-9_-]{3,32}$' or p_auth_user_id is null then
    return false;
  end if;
  return exists (
    select 1
      from private.administrators a
     where a.username = v_username
       and a.auth_user_id = p_auth_user_id
       and a.enabled
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS and grants.  Authenticated clients can read through policies but cannot
-- mutate tables directly.  The private schema and private rows are never
-- exposed to PostgREST.
-- ---------------------------------------------------------------------------

alter table public.players enable row level security;
alter table public.rooms enable row level security;
alter table public.room_seats enable row level security;
alter table public.games enable row level security;
alter table public.game_players enable row level security;
alter table public.score_audits enable row level security;

drop policy if exists players_read on public.players;
create policy players_read on public.players for select to authenticated using (true);
drop policy if exists rooms_read on public.rooms;
create policy rooms_read on public.rooms for select to authenticated using (true);
drop policy if exists room_seats_read on public.room_seats;
create policy room_seats_read on public.room_seats for select to authenticated using (true);
drop policy if exists games_read on public.games;
create policy games_read on public.games for select to authenticated using (true);
drop policy if exists game_players_read on public.game_players;
create policy game_players_read on public.game_players for select to authenticated using (true);
drop policy if exists score_audits_read on public.score_audits;
create policy score_audits_read on public.score_audits for select to authenticated using (true);

revoke all on schema private from public, anon, authenticated;
revoke all on private.session_members, private.administrators, private.request_ledger from public, anon, authenticated;

revoke all on public.players, public.rooms, public.room_seats, public.games, public.game_players, public.score_audits from anon, authenticated;
grant usage on schema public to authenticated, service_role;
grant select on public.players, public.rooms, public.room_seats, public.games, public.game_players, public.score_audits to authenticated;

revoke all on function public.club_snapshot() from public, anon, authenticated;
revoke all on function public.create_member(text) from public, anon, authenticated;
revoke all on function public.select_member(uuid) from public, anon, authenticated;
revoke all on function public.clear_member() from public, anon, authenticated;
revoke all on function public.sit_down(text, text) from public, anon, authenticated;
revoke all on function public.leave_seat(text, uuid) from public, anon, authenticated;
revoke all on function public.start_game(text, uuid) from public, anon, authenticated;
revoke all on function public.save_score(uuid, uuid, integer, integer, uuid) from public, anon, authenticated;
revoke all on function public.correct_scores(uuid, jsonb, integer, uuid) from public, anon, authenticated;
revoke all on function public.cancel_game(uuid, text, integer, uuid) from public, anon, authenticated;
revoke all on function public.rename_room(text, text) from public, anon, authenticated;
revoke all on function public.provision_admin(text, uuid, boolean) from public, anon, authenticated;
revoke all on function public.admin_identity_status(text, uuid) from public, anon, authenticated;

grant execute on function public.club_snapshot() to authenticated;
grant execute on function public.create_member(text) to authenticated;
grant execute on function public.select_member(uuid) to authenticated;
grant execute on function public.clear_member() to authenticated;
grant execute on function public.sit_down(text, text) to authenticated;
grant execute on function public.leave_seat(text, uuid) to authenticated;
grant execute on function public.start_game(text, uuid) to authenticated;
grant execute on function public.save_score(uuid, uuid, integer, integer, uuid) to authenticated;
grant execute on function public.correct_scores(uuid, jsonb, integer, uuid) to authenticated;
grant execute on function public.cancel_game(uuid, text, integer, uuid) to authenticated;
grant execute on function public.rename_room(text, text) to authenticated;
grant execute on function public.provision_admin(text, uuid, boolean) to service_role;
grant execute on function public.admin_identity_status(text, uuid) to service_role;

revoke all on function private.current_actor_id() from public, anon, authenticated;
revoke all on function private.is_admin(uuid) from public, anon, authenticated;
revoke all on function private.require_allowed_session() from public, anon, authenticated;
revoke all on function private.require_member_actor() from public, anon, authenticated;
revoke all on function private.current_member_id() from public, anon, authenticated;
revoke all on function private.require_anonymous_actor() from public, anon, authenticated;
revoke all on function private.actor_label(uuid) from public, anon, authenticated;
revoke all on function private.normalize_member_name(text) from public, anon, authenticated;
revoke all on function private.require_room_name(text) from public, anon, authenticated;
revoke all on function private.require_wind(text) from public, anon, authenticated;
revoke all on function private.lock_room(text) from public, anon, authenticated;
revoke all on function private.assert_score(integer) from public, anon, authenticated;
revoke all on function private.wind_order(text) from public, anon, authenticated;
revoke all on function private.claim_request(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function private.raise_duplicate_name() from public, anon, authenticated;
