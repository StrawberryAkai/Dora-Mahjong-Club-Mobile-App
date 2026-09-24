-- Dora Mahjong Club v0.1 PT / MMR settlement integration
--
-- This migration is source only.  It deliberately does not contact a
-- database, apply a migration, or backfill games that were completed before
-- the rating cutover.

set search_path = public, extensions, pg_catalog;

-- A pre-existing rating balance/history is an owner-reviewed migration input,
-- not something this cutover is allowed to overwrite.  The guard is kept
-- deliberately broad for the common rating table/column names while allowing
-- the known 001 schema (which has no rating columns or tables).
do $$
begin
  if exists (
    select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname in ('public', 'private')
       and c.relname in (
         'ratings', 'rating', 'rating_history', 'rating_ledger',
         'member_ratings', 'mmr_history', 'mmr_ledger', 'mmr_state',
         'rating_state', 'rating_settlements', 'rating_settlement_players'
       )
  ) then
    raise exception using
      errcode = 'P0001',
      message = '检测到未受支持的既有 MMR/评级表；请先完成经过审核的基线迁移';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'members'
       and column_name in (
         'mmr', 'mmr_baseline', 'elo', 'rating', 'rating_points',
         'rating_balance', 'mmr_balance'
       )
  ) then
    raise exception using
      errcode = 'P0001',
      message = '检测到 members 中未受支持的既有 MMR/评级列；请先完成经过审核的基线迁移';
  end if;
end;
$$;

-- Start/cancel also take the global rating lock before their request/game
-- locks.  They do not create ratings, but this keeps lifecycle operations from
-- forming a lock cycle with save_score/correct_scores.
create or replace function public.start_game(p_room_id text, p_request_id uuid)
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
begin
  perform private.lock_rating_state();
  if not private.claim_request(v_actor, p_request_id, 'start_game', p_room_id) then
    return;
  end if;
  v_creator := private.require_member_actor();

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

  insert into public.games(room_id, creator_id)
  values (p_room_id, v_creator)
  returning id into v_game;

  insert into public.game_players(game_id, member_id, wind)
  select v_game, rs.member_id, rs.wind
    from public.room_seats rs
   where rs.room_id = p_room_id;
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
  perform private.lock_rating_state();
  if not private.claim_request(
    v_actor,
    p_request_id,
    'cancel_game',
    p_game_id::text || ':' || v_reason || ':' || p_expected_version::text
  ) then
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


-- ---------------------------------------------------------------------------
-- Rating-aware correct_scores (same public signature and access semantics)
-- ---------------------------------------------------------------------------

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
  v_is_rated boolean;
begin
  perform private.lock_rating_state();
  if not private.claim_request(
    v_actor,
    p_request_id,
    'correct_scores',
    p_game_id::text || ':' || coalesce(p_scores::text, 'null') || ':'
      || p_expected_version::text
  ) then
    return;
  end if;
  -- Reject JSON null values explicitly.  jsonb_each_text otherwise returns a
  -- NULL text value which the 001 implementation could pass through.
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
  select count(*)
    into v_player_count
    from public.game_players gp
   where gp.game_id = p_game_id;
  select count(*)
    into v_input_count
    from jsonb_object_keys(p_scores);
  if v_player_count <> 4 or v_input_count <> v_player_count then
    raise exception using errcode = 'P0001', message = '请一次提交本场四位成员的成绩';
  end if;

  for v_key, v_value in
    select key, value
      from jsonb_each_text(p_scores)
  loop
    if v_value is null or v_value !~ '^-?[0-9]+$' then
      raise exception using errcode = 'P0001', message = '成绩必须是整数且不能为 null';
    end if;
    begin
      v_member_id := v_key::uuid;
      v_score := v_value::integer;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception using errcode = 'P0001', message = '更正成绩包含无效成员或成绩';
    end;
    perform private.assert_score(v_score);
    update public.game_players
       set score = v_score, rank = null
     where game_id = p_game_id and member_id = v_member_id;
    if not found then
      raise exception using errcode = 'P0001', message = '更正成绩包含非本场成员';
    end if;
  end loop;

  select coalesce(sum(gp.score), 0)
    into v_total
    from public.game_players gp
   where gp.game_id = p_game_id;
  if v_total <> 100000
     or exists (
       select 1
         from public.game_players gp
        where gp.game_id = p_game_id and gp.score is null
     ) then
    raise exception using errcode = 'P0001', message = '更正后四人成绩合计必须为 100,000';
  end if;

  with ranked as (
    select gp.member_id,
           row_number() over (
             order by gp.score desc, private.wind_order(gp.wind)
           )::integer as rank
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

  select exists (
    select 1
      from public.rating_settlements rs
     where rs.game_id = p_game_id
  ) into v_is_rated;

  insert into public.score_audits(
    game_id, actor_auth_id, actor, at, before_scores, after_scores
  )
  values (
    p_game_id, v_actor, private.actor_label(v_actor), clock_timestamp(),
    v_before, v_after
  );

  -- The target score correction advances its game version exactly once.  A
  -- rated target then replays all later rated history under the same lock;
  -- an old completed game with no settlement remains explicitly unrated.
  update public.games
     set version = v_version + 1
   where id = p_game_id;

  if v_is_rated then
    perform private.replay_ratings(p_game_id, v_actor);
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- Rating-aware save_score (same public signature and access semantics as 001)
-- ---------------------------------------------------------------------------

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
  v_player_count integer;
  v_total bigint;
  v_next_version integer;
  v_after jsonb;
  v_member_ids uuid[];
  v_scores integer[];
  v_old_mmrs double precision[];
  v_calc jsonb;
  v_order bigint;
  v_row record;
  v_locked_mmr double precision;
  v_expected_mmr double precision;
begin
  -- Rating lock comes before request-ledger and game locks for every operation
  -- which can create or revise a settlement.
  perform private.lock_rating_state();
  if not private.claim_request(
    v_actor,
    p_request_id,
    'save_score',
    p_game_id::text || ':' || p_member_id::text || ':'
      || coalesce(p_score::text, 'null') || ':' || p_expected_version::text
  ) then
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
  if not exists (
    select 1
      from public.game_players gp
     where gp.game_id = p_game_id
       and gp.member_id = p_member_id
  ) then
    raise exception using errcode = 'P0001', message = '该成员不在本场对局中';
  end if;
  if not v_admin and (v_member is null or (p_member_id <> v_member and v_creator <> v_member)) then
    raise exception using errcode = 'P0001', message = '没有代填该成员成绩的权限';
  end if;

  update public.game_players
     set score = p_score, rank = null
   where game_id = p_game_id and member_id = p_member_id;

  select count(*) filter (where gp.score is not null),
         count(*),
         coalesce(sum(gp.score), 0)
    into v_count, v_player_count, v_total
    from public.game_players gp
   where gp.game_id = p_game_id;

  v_next_version := v_version + 1;
  if v_player_count = 4 and v_count = 4 and v_total = 100000 then
    with ranked as (
      select gp.member_id,
             row_number() over (
               order by gp.score desc, private.wind_order(gp.wind)
             )::integer as rank
        from public.game_players gp
       where gp.game_id = p_game_id
    )
    update public.game_players gp
       set rank = ranked.rank
      from ranked
     where gp.game_id = p_game_id and gp.member_id = ranked.member_id;

    -- Lock all four member rows in one deterministic order, then read one
    -- shared old-MMR vector before any balance is updated.
    for v_row in
      select m.id
        from public.game_players gp
        join public.members m on m.id = gp.member_id
       where gp.game_id = p_game_id
       order by m.id
    loop
      select m.mmr into v_locked_mmr
        from public.members m
       where m.id = v_row.id
       for update;

      select rsp.new_mmr
        into v_expected_mmr
        from public.rating_settlement_players rsp
        join public.rating_settlements rs on rs.id = rsp.settlement_id
       where rsp.member_id = v_row.id
         and rs.revision = (
           select max(previous.revision)
             from public.rating_settlements previous
            where previous.game_id = rs.game_id
         )
       order by rs.settlement_order desc, rs.revision desc
       limit 1;
      if not found then
        select m.mmr_baseline into v_expected_mmr
          from public.members m
         where m.id = v_row.id;
      end if;
      if v_locked_mmr is distinct from v_expected_mmr then
        raise exception using
          errcode = 'P0001',
          message = '当前 MMR 与不可变评级历史不一致，请先完成基线迁移';
      end if;
    end loop;

    select array_agg(gp.member_id order by gp.member_id),
           array_agg(gp.score order by gp.member_id),
           array_agg(m.mmr order by gp.member_id)
      into v_member_ids, v_scores, v_old_mmrs
      from public.game_players gp
      join public.members m on m.id = gp.member_id
     where gp.game_id = p_game_id;
    v_calc := private.calculate_rating(v_member_ids, v_scores, v_old_mmrs);
    v_order := private.allocate_settlement_order();
    select jsonb_object_agg(gp.member_id::text, gp.score order by gp.member_id)
      into v_after
      from public.game_players gp
     where gp.game_id = p_game_id;

    perform private.append_rating_settlement(
      p_game_id,
      v_order,
      1,
      null,
      v_actor,
      v_after,
      v_calc
    );

    for v_row in
      select value
        from jsonb_array_elements(v_calc -> 'players') as elements(value)
    loop
      update public.members
         set mmr = (v_row.value ->> 'new_mmr')::double precision
       where id = (v_row.value ->> 'member_id')::uuid;
    end loop;

    update public.games
       set status = 'completed', completed_at = now(), version = v_next_version
     where id = p_game_id;
  else
    update public.games
       set version = v_next_version
     where id = p_game_id;
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- One-MVCC snapshot with the rating JSON contract
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
-- Private transaction helpers
-- ---------------------------------------------------------------------------

create or replace function private.lock_rating_state()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  perform 1
    from private.rating_control
   where singleton
     and baseline_provenance = 'riichi-pt-mmr-v1-initial-1500'
     and baseline_cutover_version = 1
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = '评级控制状态缺失';
  end if;
end;
$$;

create or replace function private.allocate_settlement_order()
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_order bigint;
begin
  select next_settlement_order
    into v_order
    from private.rating_control
   where singleton
     and baseline_provenance = 'riichi-pt-mmr-v1-initial-1500'
     and baseline_cutover_version = 1
   for update;
  if not found or v_order is null or v_order <= 0 then
    raise exception using errcode = 'P0001', message = '评级结算顺序状态无效';
  end if;
  update private.rating_control
     set next_settlement_order = v_order + 1
   where singleton;
  return v_order;
end;
$$;

create or replace function private.append_rating_settlement(
  p_game_id uuid,
  p_settlement_order bigint,
  p_revision integer,
  p_source_game_id uuid,
  p_actor uuid,
  p_original_points jsonb,
  p_calculation jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_settlement_id uuid;
  v_player jsonb;
  v_player_count integer := 0;
begin
  if p_game_id is null or p_settlement_order is null or p_settlement_order <= 0
     or p_revision is null or p_revision <= 0
     or p_actor is null
     or p_original_points is null
     or jsonb_typeof(p_original_points) <> 'object'
     or p_calculation is null
     or jsonb_typeof(p_calculation) <> 'object'
     or jsonb_typeof(p_calculation -> 'players') <> 'array' then
    raise exception using errcode = 'P0001', message = '评级结算数据无效';
  end if;

  insert into public.rating_settlements(
    game_id,
    settlement_order,
    revision,
    rule_version,
    settled_at,
    source_game_id,
    original_points,
    calculation
  )
  values (
    p_game_id,
    p_settlement_order,
    p_revision,
    'riichi-pt-mmr-v1',
    clock_timestamp(),
    p_source_game_id,
    p_original_points,
    p_calculation
  )
  returning id into v_settlement_id;

  for v_player in
    select value
      from jsonb_array_elements(p_calculation -> 'players') as elements(value)
  loop
    v_player_count := v_player_count + 1;
    insert into public.rating_settlement_players(
      settlement_id,
      member_id,
      final_points,
      actual_uma,
      pt,
      old_mmr,
      mmr_delta,
      new_mmr,
      expected_uma,
      rank_probabilities
    )
    values (
      v_settlement_id,
      (v_player ->> 'member_id')::uuid,
      (v_player ->> 'final_points')::integer,
      (v_player ->> 'actual_uma')::double precision,
      (v_player ->> 'pt')::double precision,
      (v_player ->> 'old_mmr')::double precision,
      (v_player ->> 'mmr_delta')::double precision,
      (v_player ->> 'new_mmr')::double precision,
      (v_player ->> 'expected_uma')::double precision,
      v_player -> 'rank_probabilities'
    );
  end loop;

  if v_player_count <> 4 then
    raise exception using errcode = 'P0001', message = '评级结算必须包含四位成员';
  end if;

  insert into private.rating_settlement_audits(
    settlement_id,
    actor_auth_id,
    actor,
    source_corrected_game_id,
    created_at
  )
  values (
    v_settlement_id,
    p_actor,
    private.actor_label(p_actor),
    p_source_game_id,
    clock_timestamp()
  );

  return v_settlement_id;
end;
$$;

-- Rebuild every rated game from immutable member baselines in fixed order.
-- The caller must already hold the singleton rating lock and the target game
-- lock; this helper never edits an older settlement revision.
create or replace function private.replay_ratings(
  p_target_game_id uuid,
  p_actor uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_control record;
  v_member record;
  v_current record;
  v_player jsonb;
  v_member_ids uuid[];
  v_scores integer[];
  v_old_mmrs double precision[];
  v_calc jsonb;
  v_points jsonb;
  v_expected_mmr double precision;
  v_target_order bigint;
  v_seen_order bigint;
  v_changed boolean;
begin
  select * into v_control
    from private.rating_control
   where singleton
   for update;
  if not found
     or v_control.baseline_provenance <> 'riichi-pt-mmr-v1-initial-1500'
     or v_control.baseline_cutover_version <> 1 then
    raise exception using errcode = 'P0001', message = '评级基线可信状态缺失';
  end if;

  -- Before resetting balances for a replay, prove that the currently stored
  -- balances are exactly the latest immutable result (or the baseline for a
  -- member with no rated game).  This rejects foreign/manual MMR state rather
  -- than silently erasing it.
  for v_member in
    select m.id, m.mmr, m.mmr_baseline
      from public.members m
     order by m.id
  loop
    if v_member.mmr_baseline is null
       or v_member.mmr_baseline <> 1500.0
       or v_member.mmr_baseline = 'NaN'::double precision
       or v_member.mmr_baseline = 'Infinity'::double precision
       or v_member.mmr_baseline = '-Infinity'::double precision
       or v_member.mmr is null
       or v_member.mmr = 'NaN'::double precision
       or v_member.mmr = 'Infinity'::double precision
       or v_member.mmr = '-Infinity'::double precision then
      raise exception using errcode = 'P0001', message = '发现不受支持的既有 MMR 状态，请先完成基线迁移';
    end if;

    select rsp.new_mmr
      into v_expected_mmr
      from public.rating_settlement_players rsp
      join public.rating_settlements rs on rs.id = rsp.settlement_id
     where rsp.member_id = v_member.id
       and rs.revision = (
         select max(previous.revision)
           from public.rating_settlements previous
          where previous.game_id = rs.game_id
       )
     order by rs.settlement_order desc, rs.revision desc
     limit 1;
    if not found then
      v_expected_mmr := v_member.mmr_baseline;
    end if;
    if v_member.mmr is distinct from v_expected_mmr then
      raise exception using errcode = 'P0001', message = '当前 MMR 与不可变评级历史不一致，请先完成基线迁移';
    end if;
  end loop;

  select rs.settlement_order
    into v_target_order
    from public.rating_settlements rs
   where rs.game_id = p_target_game_id
     and rs.revision = (
       select max(previous.revision)
         from public.rating_settlements previous
        where previous.game_id = rs.game_id
     )
   limit 1;
  if not found or v_target_order is null then
    raise exception using errcode = 'P0001', message = '评级历史中找不到待更正对局';
  end if;

  -- Reset only after the trusted-balance checks above.  Every rated game is
  -- then replayed, including games whose players were indirect opponents of
  -- the corrected game.
  update public.members set mmr = mmr_baseline;
  v_seen_order := null;

  for v_current in
    select rs.game_id,
           rs.settlement_order,
           rs.revision,
           rs.rule_version,
           rs.original_points,
           rs.calculation
      from public.rating_settlements rs
     where rs.revision = (
       select max(previous.revision)
         from public.rating_settlements previous
        where previous.game_id = rs.game_id
     )
     order by rs.settlement_order, rs.game_id
  loop
    if v_current.rule_version <> 'riichi-pt-mmr-v1' then
      raise exception using errcode = 'P0001', message = '评级历史包含未知规则版本';
    end if;
    if v_seen_order is not null and v_current.settlement_order <= v_seen_order then
      raise exception using errcode = 'P0001', message = '评级结算顺序不唯一';
    end if;
    v_seen_order := v_current.settlement_order;

    select array_agg(gp.member_id order by gp.member_id),
           array_agg(gp.score order by gp.member_id),
           array_agg(m.mmr order by gp.member_id)
      into v_member_ids, v_scores, v_old_mmrs
      from public.game_players gp
      join public.members m on m.id = gp.member_id
     where gp.game_id = v_current.game_id;
    if coalesce(array_length(v_member_ids, 1), 0) <> 4 then
      raise exception using errcode = 'P0001', message = '评级历史对局成员数量无效';
    end if;

    select jsonb_object_agg(gp.member_id::text, gp.score order by gp.member_id)
      into v_points
      from public.game_players gp
     where gp.game_id = v_current.game_id;
    v_calc := private.calculate_rating(v_member_ids, v_scores, v_old_mmrs);
    v_changed := v_current.original_points is distinct from v_points
      or v_current.calculation is distinct from v_calc;

    if v_current.settlement_order < v_target_order and v_changed then
      raise exception using errcode = 'P0001', message = '更正点之前的评级历史不一致，请先完成审核迁移';
    end if;

    if v_current.settlement_order >= v_target_order
       and (v_current.game_id = p_target_game_id or v_changed) then
      perform private.append_rating_settlement(
        v_current.game_id,
        v_current.settlement_order,
        v_current.revision + 1,
        p_target_game_id,
        p_actor,
        v_points,
        v_calc
      );
      if v_current.game_id <> p_target_game_id then
        update public.games
           set version = version + 1
         where id = v_current.game_id;
      end if;
    end if;

    for v_player in
      select value
        from jsonb_array_elements(v_calc -> 'players') as elements(value)
    loop
      update public.members
         set mmr = (v_player ->> 'new_mmr')::double precision
       where id = (v_player ->> 'member_id')::uuid;
      if not found then
        raise exception using errcode = 'P0001', message = '评级结果包含未知成员';
      end if;
    end loop;
  end loop;
end;
$$;


-- Existing members receive the new system's trusted cutover baseline.  No
-- old game is converted merely because these columns now exist.
alter table public.members
  add column mmr double precision not null default 1500.0,
  add column mmr_baseline double precision not null default 1500.0;

alter table public.members
  add constraint members_mmr_finite
    check (
      mmr <> 'NaN'::double precision
      and mmr <> 'Infinity'::double precision
      and mmr <> '-Infinity'::double precision
    ),
  add constraint members_mmr_baseline_finite
    check (
      mmr_baseline = 1500.0
      and mmr_baseline <> 'NaN'::double precision
      and mmr_baseline <> 'Infinity'::double precision
      and mmr_baseline <> '-Infinity'::double precision
    );

-- The private singleton is both the global serialization row and the fixed
-- settlement-order counter.  baseline_provenance is a cutover marker: replay
-- is permitted only for this trusted initial-1500 state.
create table private.rating_control (
  singleton boolean primary key default true,
  next_settlement_order bigint not null default 1,
  baseline_provenance text not null,
  baseline_cutover_version integer not null default 1,
  initialized_at timestamptz not null default now(),
  constraint rating_control_singleton check (singleton),
  constraint rating_control_next_order check (next_settlement_order > 0),
  constraint rating_control_provenance check (
    baseline_provenance = 'riichi-pt-mmr-v1-initial-1500'
  ),
  constraint rating_control_cutover check (baseline_cutover_version = 1)
);

insert into private.rating_control(
  singleton,
  next_settlement_order,
  baseline_provenance,
  baseline_cutover_version
)
values (true, 1, 'riichi-pt-mmr-v1-initial-1500', 1);

-- One immutable row is appended for every settlement revision.  The latest
-- revision for a game is current; all lower revisions remain visible history.
create table public.rating_settlements (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete restrict,
  settlement_order bigint not null,
  revision integer not null,
  rule_version text not null,
  settled_at timestamptz not null default now(),
  source_game_id uuid references public.games(id) on delete restrict,
  original_points jsonb not null,
  calculation jsonb not null,
  constraint rating_settlements_order_positive check (settlement_order > 0),
  constraint rating_settlements_revision_positive check (revision > 0),
  constraint rating_settlements_rule check (rule_version = 'riichi-pt-mmr-v1'),
  constraint rating_settlements_original_object check (jsonb_typeof(original_points) = 'object'),
  constraint rating_settlements_calculation_object check (jsonb_typeof(calculation) = 'object'),
  constraint rating_settlements_game_revision_unique unique (game_id, revision)
);

create index rating_settlements_order_idx
  on public.rating_settlements(settlement_order, game_id, revision);

create unique index rating_settlements_initial_order_unique
  on public.rating_settlements(settlement_order)
  where revision = 1;

create table public.rating_settlement_players (
  settlement_id uuid not null references public.rating_settlements(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  final_points integer not null,
  actual_uma double precision not null,
  pt double precision not null,
  old_mmr double precision not null,
  mmr_delta double precision not null,
  new_mmr double precision not null,
  expected_uma double precision not null,
  rank_probabilities jsonb not null,
  primary key (settlement_id, member_id),
  constraint rating_players_points_multiple check (final_points % 100 = 0),
  constraint rating_players_uma_finite check (
    actual_uma <> 'NaN'::double precision
    and actual_uma <> 'Infinity'::double precision
    and actual_uma <> '-Infinity'::double precision
    and pt <> 'NaN'::double precision
    and pt <> 'Infinity'::double precision
    and pt <> '-Infinity'::double precision
    and expected_uma <> 'NaN'::double precision
    and expected_uma <> 'Infinity'::double precision
    and expected_uma <> '-Infinity'::double precision
  ),
  constraint rating_players_mmr_finite check (
    old_mmr <> 'NaN'::double precision
    and old_mmr <> 'Infinity'::double precision
    and old_mmr <> '-Infinity'::double precision
    and mmr_delta <> 'NaN'::double precision
    and mmr_delta <> 'Infinity'::double precision
    and mmr_delta <> '-Infinity'::double precision
    and new_mmr <> 'NaN'::double precision
    and new_mmr <> 'Infinity'::double precision
    and new_mmr <> '-Infinity'::double precision
  ),
  constraint rating_players_rank_probabilities_array check (
    jsonb_typeof(rank_probabilities) = 'array'
  )
);

create index rating_settlement_players_member_idx
  on public.rating_settlement_players(member_id, settlement_id);

-- Actor/source metadata stays server-private while the settlement ledger is a
-- read-only public model.
create table private.rating_settlement_audits (
  settlement_id uuid primary key references public.rating_settlements(id) on delete restrict,
  actor_auth_id uuid not null,
  actor text not null,
  source_corrected_game_id uuid references public.games(id) on delete restrict,
  created_at timestamptz not null default now()
);

revoke all on private.rating_control, private.rating_settlement_audits
  from public, anon, authenticated;

revoke all on public.rating_settlements, public.rating_settlement_players
  from public, anon, authenticated;

grant select on public.rating_settlements, public.rating_settlement_players
  to authenticated;

alter table public.rating_settlements enable row level security;
alter table public.rating_settlement_players enable row level security;

drop policy if exists rating_settlements_read on public.rating_settlements;
create policy rating_settlements_read
  on public.rating_settlements for select to authenticated using (true);

drop policy if exists rating_settlement_players_read on public.rating_settlement_players;
create policy rating_settlement_players_read
  on public.rating_settlement_players for select to authenticated using (true);

-- Baselines are trusted cutover state.  They are never changed by a later
-- replay or by a direct table write.
create or replace function private.prevent_rating_baseline_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if tg_op = 'UPDATE' and new.mmr_baseline is distinct from old.mmr_baseline then
    raise exception using
      errcode = 'P0001',
      message = 'MMR 基线不可修改，请先完成经过审核的基线迁移';
  end if;
  return new;
end;
$$;

create trigger members_rating_baseline_immutable
before update on public.members
for each row execute function private.prevent_rating_baseline_change();

create or replace function private.prevent_rating_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = '评级结算历史不可修改或删除';
end;
$$;

create trigger rating_settlements_immutable
before update or delete on public.rating_settlements
for each row execute function private.prevent_rating_ledger_mutation();

create trigger rating_settlement_players_immutable
before update or delete on public.rating_settlement_players
for each row execute function private.prevent_rating_ledger_mutation();

-- ---------------------------------------------------------------------------
-- Pure, private PT/MMR calculation
-- ---------------------------------------------------------------------------

-- The helper is intentionally independent of transaction state.  Its
-- remaining-set softmax subtracts the largest remaining logit at each
-- Plackett-Luce position; this is algebraically identical to
-- exp((R - meanR) / 400) while avoiding overflow for large finite MMR gaps.
create or replace function private.calculate_rating(
  p_member_ids uuid[],
  p_scores integer[],
  p_old_mmrs double precision[]
)
returns jsonb
language plpgsql
immutable
parallel safe
security definer
set search_path = pg_catalog, public, private
set extra_float_digits = 3
as $$
declare
  v_i integer;
  v_j integer;
  v_k integer;
  v_pos integer;
  v_n integer;
  v_total bigint := 0;
  v_group_low integer;
  v_group_count integer;
  v_group_high integer;
  v_rank_uma double precision;
  v_actual_uma double precision[] := array_fill(0.0::double precision, array[4]);
  v_offsets double precision[] := array_fill(0.0::double precision, array[4]);
  v_pt double precision[] := array_fill(0.0::double precision, array[4]);
  v_expected_uma double precision[] := array_fill(0.0::double precision, array[4]);
  v_f double precision[] := array_fill(0.0::double precision, array[4]);
  v_h double precision[] := array_fill(0.0::double precision, array[4]);
  v_v double precision[] := array_fill(0.0::double precision, array[4]);
  v_delta double precision[] := array_fill(0.0::double precision, array[4]);
  v_new_mmr double precision[] := array_fill(0.0::double precision, array[4]);
  v_rank_probabilities double precision[][] := array_fill(0.0::double precision, array[4, 4]);
  v_perm integer[];
  v_remaining integer[];
  v_candidate integer;
  v_selected integer;
  v_probability double precision;
  v_log_probability numeric;
  v_max_mmr double precision;
  v_logit numeric;
  v_selected_logit numeric;
  v_sum_exp double precision;
  v_mean_h double precision;
  v_opponent_sum numeric;
  v_g numeric;
  v_c double precision;
  v_sign double precision;
  v_result jsonb;
begin
  if coalesce(array_ndims(p_member_ids), 0) <> 1
     or coalesce(array_ndims(p_scores), 0) <> 1
     or coalesce(array_ndims(p_old_mmrs), 0) <> 1
     or array_length(p_member_ids, 1) <> 4
     or array_length(p_scores, 1) <> 4
     or array_length(p_old_mmrs, 1) <> 4 then
    raise exception using errcode = 'P0001', message = '评级必须包含四位成员';
  end if;

  v_n := array_length(p_member_ids, 1);
  for v_i in 1..v_n loop
    if p_member_ids[v_i] is null then
      raise exception using errcode = 'P0001', message = '评级成员不能为空';
    end if;
    for v_j in 1..v_n loop
      if v_j > v_i and p_member_ids[v_i] = p_member_ids[v_j] then
        raise exception using errcode = 'P0001', message = '评级成员必须互不相同';
      end if;
    end loop;

    if p_scores[v_i] is null or p_scores[v_i] % 100 <> 0 then
      raise exception using errcode = 'P0001', message = '点数必须是 100 的倍数';
    end if;
    v_total := v_total + p_scores[v_i]::bigint;

    if p_old_mmrs[v_i] is null
       or p_old_mmrs[v_i] = 'NaN'::double precision
       or p_old_mmrs[v_i] = 'Infinity'::double precision
       or p_old_mmrs[v_i] = '-Infinity'::double precision then
      raise exception using errcode = 'P0001', message = 'MMR 必须是有限数值';
    end if;
  end loop;

  if v_total <> 100000 then
    raise exception using errcode = 'P0001', message = '四人成绩合计必须为 100,000';
  end if;
  -- The common meanR term in exp((R - meanR) / 400) cancels from each
  -- remaining-set softmax. Numeric intermediates preserve tiny and very large
  -- finite inputs without PostgreSQL float subtraction/division underflow.

  -- Equal scores share the average of the occupied Uma positions.  Wind is
  -- intentionally absent from this calculation.
  for v_i in 1..4 loop
    v_group_low := 1;
    v_group_count := 0;
    for v_j in 1..4 loop
      if p_scores[v_j] > p_scores[v_i] then
        v_group_low := v_group_low + 1;
      end if;
      if p_scores[v_j] = p_scores[v_i] then
        v_group_count := v_group_count + 1;
      end if;
    end loop;
    v_group_high := v_group_low + v_group_count - 1;
    v_actual_uma[v_i] := 0.0;
    for v_k in v_group_low..v_group_high loop
      v_rank_uma := case v_k
        when 1 then 30.0
        when 2 then 10.0
        when 3 then -10.0
        when 4 then -30.0
        else 0.0
      end;
      v_actual_uma[v_i] := v_actual_uma[v_i] + v_rank_uma;
    end loop;
    v_actual_uma[v_i] := v_actual_uma[v_i] / v_group_count;
    v_offsets[v_i] := (p_scores[v_i]::double precision - 25000.0) / 1000.0;
    v_pt[v_i] := v_offsets[v_i] + v_actual_uma[v_i];
  end loop;

  -- Enumerate all 24 rankings and multiply the stable remaining-set choice
  -- probabilities.  The mean MMR cancels from each normalized choice but is
  -- retained in the equivalent logit expression for the rule definition.
  for v_i in 1..4 loop
    for v_j in 1..4 loop
      continue when v_j = v_i;
      for v_k in 1..4 loop
        continue when v_k = v_i or v_k = v_j;
        for v_candidate in 1..4 loop
          continue when v_candidate = v_i or v_candidate = v_j or v_candidate = v_k;
          v_perm := array[v_i, v_j, v_k, v_candidate];
          v_remaining := array[1, 2, 3, 4];
          v_log_probability := 0.0;

          for v_pos in 1..4 loop
            v_max_mmr := null;
            foreach v_selected in array v_remaining loop
              if v_max_mmr is null or p_old_mmrs[v_selected] > v_max_mmr then
                v_max_mmr := p_old_mmrs[v_selected];
              end if;
            end loop;

            v_sum_exp := 0.0;
            foreach v_selected in array v_remaining loop
              -- Round-trip text preserves the supplied float's precision;
              -- subtract and divide as numeric before evaluating a bounded exp.
              v_logit := (p_old_mmrs[v_selected]::text::numeric
                - v_max_mmr::text::numeric) / 400.0;
              if v_logit <= -700.0 then
                -- PostgreSQL may raise on extreme exp underflow.  This term
                -- is mathematically negligible and contributes zero.
                null;
              else
                v_sum_exp := v_sum_exp + exp(v_logit)::double precision;
              end if;
            end loop;

            v_selected := v_perm[v_pos];
            v_selected_logit := (p_old_mmrs[v_selected]::text::numeric
              - v_max_mmr::text::numeric) / 400.0;
            if v_sum_exp = 0.0 then
              raise exception using errcode = 'P0001', message = '评级概率计算失败';
            end if;
            if v_selected_logit <= -700.0 then
              v_log_probability := -1000;
            else
              v_log_probability := v_log_probability
                + v_selected_logit - ln(v_sum_exp)::numeric;
            end if;
            v_remaining := array_remove(v_remaining, v_selected);
          end loop;

          if v_log_probability <= -700.0 then
            v_probability := 0.0;
          else
            v_probability := exp(v_log_probability)::double precision;
          end if;

          for v_pos in 1..4 loop
            v_rank_probabilities[v_perm[v_pos]][v_pos] :=
              v_rank_probabilities[v_perm[v_pos]][v_pos] + v_probability;
          end loop;
        end loop;
      end loop;
    end loop;
  end loop;

  for v_i in 1..4 loop
    v_expected_uma[v_i] := 0.0;
    for v_pos in 1..4 loop
      v_rank_uma := case v_pos
        when 1 then 30.0
        when 2 then 10.0
        when 3 then -10.0
        when 4 then -30.0
        else 0.0
      end;
      v_expected_uma[v_i] := v_expected_uma[v_i]
        + v_rank_probabilities[v_i][v_pos] * v_rank_uma;
    end loop;
    v_f[v_i] := (v_actual_uma[v_i] - v_expected_uma[v_i])
      + 0.4 * v_offsets[v_i];
    if v_f[v_i] >= 0.0 then
      v_h[v_i] := v_f[v_i] * 0.85;
    else
      v_h[v_i] := v_f[v_i] * 1.15;
    end if;
    v_mean_h := coalesce(v_mean_h, 0.0) + v_h[v_i];
  end loop;
  v_mean_h := v_mean_h / 4.0;

  for v_i in 1..4 loop
    v_v[v_i] := v_h[v_i] - v_mean_h;
    if v_v[v_i] > 0.0 then
      v_sign := 1.0;
    elsif v_v[v_i] < 0.0 then
      v_sign := -1.0;
    else
      v_sign := 0.0;
    end if;
    v_opponent_sum := 0;
    for v_j in 1..4 loop
      if v_j <> v_i then
        v_opponent_sum := v_opponent_sum + p_old_mmrs[v_j]::text::numeric;
      end if;
    end loop;
    v_g := (v_opponent_sum / 3.0 - p_old_mmrs[v_i]::text::numeric) / 400.0;
    if v_sign = 0.0 then
      -- Avoid Infinity * 0 for extreme finite inputs; the defined product is
      -- zero when the centered performance sign is zero.
      v_c := 1.0;
    else
      v_c := greatest(0.5, least(1.5, 1.0 + 0.3 * v_g * v_sign::numeric))::double precision;
    end if;
    v_delta[v_i] := 0.75 * v_c * v_v[v_i];
    v_new_mmr[v_i] := p_old_mmrs[v_i] + v_delta[v_i];
    if v_new_mmr[v_i] is null
       or v_new_mmr[v_i] = 'NaN'::double precision
       or v_new_mmr[v_i] = 'Infinity'::double precision
       or v_new_mmr[v_i] = '-Infinity'::double precision then
      raise exception using errcode = 'P0001', message = '评级结果不是有限数值';
    end if;
  end loop;

  v_result := jsonb_build_object(
    'rule_version', 'riichi-pt-mmr-v1',
    'players', jsonb_build_array(
      jsonb_build_object(
        'member_id', p_member_ids[1]::text,
        'final_points', p_scores[1],
        'actual_uma', v_actual_uma[1],
        'pt', v_pt[1],
        'old_mmr', p_old_mmrs[1],
        'mmr_delta', v_delta[1],
        'new_mmr', v_new_mmr[1],
        'expected_uma', v_expected_uma[1],
        'rank_probabilities', jsonb_build_array(
          v_rank_probabilities[1][1], v_rank_probabilities[1][2],
          v_rank_probabilities[1][3], v_rank_probabilities[1][4]
        )
      ),
      jsonb_build_object(
        'member_id', p_member_ids[2]::text,
        'final_points', p_scores[2],
        'actual_uma', v_actual_uma[2],
        'pt', v_pt[2],
        'old_mmr', p_old_mmrs[2],
        'mmr_delta', v_delta[2],
        'new_mmr', v_new_mmr[2],
        'expected_uma', v_expected_uma[2],
        'rank_probabilities', jsonb_build_array(
          v_rank_probabilities[2][1], v_rank_probabilities[2][2],
          v_rank_probabilities[2][3], v_rank_probabilities[2][4]
        )
      ),
      jsonb_build_object(
        'member_id', p_member_ids[3]::text,
        'final_points', p_scores[3],
        'actual_uma', v_actual_uma[3],
        'pt', v_pt[3],
        'old_mmr', p_old_mmrs[3],
        'mmr_delta', v_delta[3],
        'new_mmr', v_new_mmr[3],
        'expected_uma', v_expected_uma[3],
        'rank_probabilities', jsonb_build_array(
          v_rank_probabilities[3][1], v_rank_probabilities[3][2],
          v_rank_probabilities[3][3], v_rank_probabilities[3][4]
        )
      ),
      jsonb_build_object(
        'member_id', p_member_ids[4]::text,
        'final_points', p_scores[4],
        'actual_uma', v_actual_uma[4],
        'pt', v_pt[4],
        'old_mmr', p_old_mmrs[4],
        'mmr_delta', v_delta[4],
        'new_mmr', v_new_mmr[4],
        'expected_uma', v_expected_uma[4],
        'rank_probabilities', jsonb_build_array(
          v_rank_probabilities[4][1], v_rank_probabilities[4][2],
          v_rank_probabilities[4][3], v_rank_probabilities[4][4]
        )
      )
    )
  );
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC/table permissions (kept after every object definition)
-- ---------------------------------------------------------------------------

revoke all on function public.club_snapshot() from public, anon, authenticated;
revoke all on function public.start_game(text, uuid) from public, anon, authenticated;
revoke all on function public.save_score(uuid, uuid, integer, integer, uuid)
  from public, anon, authenticated;
revoke all on function public.correct_scores(uuid, jsonb, integer, uuid)
  from public, anon, authenticated;
revoke all on function public.cancel_game(uuid, text, integer, uuid)
  from public, anon, authenticated;

grant execute on function public.club_snapshot() to authenticated;
grant execute on function public.start_game(text, uuid) to authenticated;
grant execute on function public.save_score(uuid, uuid, integer, integer, uuid)
  to authenticated;
grant execute on function public.correct_scores(uuid, jsonb, integer, uuid)
  to authenticated;
grant execute on function public.cancel_game(uuid, text, integer, uuid)
  to authenticated;

revoke all on function private.lock_rating_state() from public, anon, authenticated;
revoke all on function private.allocate_settlement_order() from public, anon, authenticated;
revoke all on function private.append_rating_settlement(
  uuid, bigint, integer, uuid, uuid, jsonb, jsonb
) from public, anon, authenticated;
revoke all on function private.replay_ratings(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.calculate_rating(uuid[], integer[], double precision[])
  from public, anon, authenticated;
revoke all on function private.prevent_rating_baseline_change()
  from public, anon, authenticated;
revoke all on function private.prevent_rating_ledger_mutation()
  from public, anon, authenticated;
