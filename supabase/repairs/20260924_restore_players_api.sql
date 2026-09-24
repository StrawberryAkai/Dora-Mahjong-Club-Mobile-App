-- Restore the player-aware public API after an accidental 001 rerun.
-- This transaction backs up original function definitions and metadata, then
-- replaces only guarded functions. It does not alter business rows or replays.
BEGIN;

DO $preflight$
DECLARE
  v_missing text[];
BEGIN
  IF to_regnamespace('private') IS NULL THEN
    RAISE EXCEPTION 'Repair preflight failed: private schema is missing';
  END IF;

  SELECT array_agg(required.relation_name ORDER BY required.relation_name)
    INTO v_missing
    FROM (VALUES
      ('public.players'),
      ('public.members'),
      ('public.rooms'),
      ('public.room_seats'),
      ('public.games'),
      ('public.game_players'),
      ('public.score_audits'),
      ('public.events'),
      ('public.rating_settlements'),
      ('public.rating_settlement_players'),
      ('private.session_members'),
      ('private.administrators'),
      ('private.request_ledger'),
      ('private.rating_control'),
      ('private.rating_settlement_audits'),
      ('private.member_carryovers'),
      ('private.legacy_cutovers')
    ) AS required(relation_name)
   WHERE to_regclass(required.relation_name) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Repair preflight failed: missing required relations: %', array_to_string(v_missing, ', ');
  END IF;

  IF EXISTS (
    SELECT 1
      FROM (VALUES
        ('member_id', 'uuid', true, true),
        ('name', 'text', true, false),
        ('normalized_name', 'text', true, false),
        ('current_mmr', 'double precision', true, true),
        ('mmr_baseline', 'double precision', true, true),
        ('created_at', 'timestamp with time zone', false, true),
        ('mmr_rank', 'bigint', false, false),
        ('total_pt', 'double precision', false, true),
        ('pt_rank', 'bigint', false, false),
        ('history_highest_pt', 'double precision', false, true),
        ('history_highest_pt_rank', 'bigint', false, false),
        ('games_played', 'bigint', false, true),
        ('wins', 'bigint', false, true),
        ('win_rate', 'double precision', false, true)
      ) AS expected(column_name, type_name, must_be_not_null, must_have_default)
      LEFT JOIN pg_attribute a
        ON a.attrelid = 'public.players'::regclass
       AND a.attname = expected.column_name
       AND a.attnum > 0
       AND NOT a.attisdropped
      LEFT JOIN pg_attrdef d
        ON d.adrelid = a.attrelid
       AND d.adnum = a.attnum
     WHERE a.attnum IS NULL
        OR format_type(a.atttypid, a.atttypmod) IS DISTINCT FROM expected.type_name
        OR (expected.must_be_not_null AND NOT a.attnotnull)
        OR (expected.must_have_default AND d.oid IS NULL)
  ) THEN
    RAISE EXCEPTION 'Repair preflight failed: public.players does not match the canonical player schema or required defaults';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint c
      JOIN pg_attribute a
        ON a.attrelid = c.conrelid
       AND a.attnum = c.conkey[1]
     WHERE c.conrelid = 'public.players'::regclass
       AND c.contype = 'p'
       AND cardinality(c.conkey) = 1
       AND a.attname = 'member_id'
  ) THEN
    RAISE EXCEPTION 'Repair preflight failed: public.players.member_id is not the primary key';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute a
     WHERE a.attrelid = 'public.members'::regclass
       AND a.attname = 'id'
       AND a.atttypid = 'uuid'::regtype
       AND a.attnum > 0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_attribute a
     WHERE a.attrelid = 'public.members'::regclass
       AND a.attname = 'name'
       AND a.atttypid = 'text'::regtype
       AND a.attnum > 0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_attribute a
     WHERE a.attrelid = 'public.members'::regclass
       AND a.attname = 'normalized_name'
       AND a.atttypid = 'text'::regtype
       AND a.attnum > 0 AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION 'Repair preflight failed: public.members is not the expected empty 001 base table';
  END IF;

  IF EXISTS (SELECT 1 FROM public.members LIMIT 1) THEN
    RAISE EXCEPTION 'Repair preflight failed: public.members is not empty';
  END IF;

  SELECT array_agg(required.signature ORDER BY required.signature)
    INTO v_missing
    FROM (VALUES
      ('auth.uid()'),
      ('auth.jwt()'),
      ('private.current_actor_id()'),
      ('private.is_admin(uuid)'),
      ('private.require_allowed_session()'),
      ('private.require_member_actor()'),
      ('private.require_anonymous_actor()'),
      ('private.current_member_id()'),
      ('private.normalize_member_name(text)'),
      ('private.actor_label(uuid)'),
      ('private.raise_duplicate_name()'),
      ('private.require_wind(text)'),
      ('private.lock_room(text)'),
      ('private.wind_order(text)'),
      ('private.assert_score(integer)'),
      ('private.claim_request(uuid,uuid,text,text)'),
      ('private.lock_rating_state()'),
      ('private.allocate_settlement_order()'),
      ('private.append_rating_settlement(uuid,bigint,integer,uuid,uuid,jsonb,jsonb)'),
      ('private.replay_ratings(uuid,uuid)'),
      ('private.calculate_rating(uuid[],integer[],double precision[])'),
      ('private.refresh_player_statistics()'),
      ('public.start_game(text,uuid,uuid)')
    ) AS required(signature)
   WHERE to_regprocedure(required.signature) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Repair preflight failed: missing required functions: %', array_to_string(v_missing, ', ');
  END IF;
END;
$preflight$;

CREATE TABLE IF NOT EXISTS private.restore_players_api_20260924_backups (
  function_signature text PRIMARY KEY,
  function_oid oid NOT NULL,
  function_definition text NOT NULL,
  prosrc text NOT NULL,
  proowner oid NOT NULL,
  proacl aclitem[],
  proconfig text[],
  function_comment text,
  backed_up_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.restore_players_api_20260924_backups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.restore_players_api_20260924_backups
  FROM PUBLIC, anon, authenticated, service_role;

DO $repair$
DECLARE
  v_target record;
  v_oid oid;
  v_current_source text;
  v_normalized_source text;
  v_is_base boolean;
  v_is_desired boolean;
BEGIN
  FOR v_target IN
    SELECT *
      FROM (VALUES

('private.actor_label(uuid)', 'private.actor_label(p_actor uuid)', 'text', true, $repair_0_base$declare
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
    join public.members m on m.id = sm.member_id
   where sm.auth_user_id = p_actor;
  if v_label is not null then
    return v_label;
  end if;

  raise exception using errcode = 'P0001', message = '找不到操作人身份';
end;$repair_0_base$, $repair_0_desired$declare
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
end;$repair_0_desired$),
('public.create_member(text)', 'public.create_member(p_name text)', 'void', false, $repair_1_base$declare
  v_actor uuid := private.require_anonymous_actor();
  v_name text := btrim(coalesce(p_name, ''));
  v_normalized text := private.normalize_member_name(p_name);
  v_member uuid;
begin
  begin
    insert into public.members(name, normalized_name)
    values (v_name, v_normalized)
    returning id into v_member;
  exception when unique_violation then
    perform private.raise_duplicate_name();
  end;

  insert into private.session_members(auth_user_id, member_id, selected_at)
  values (v_actor, v_member, now())
  on conflict (auth_user_id) do update
    set member_id = excluded.member_id,
        selected_at = excluded.selected_at;
end;$repair_1_base$, $repair_1_desired$declare
  v_actor uuid := private.require_anonymous_actor();
  v_name text := btrim(coalesce(p_name, ''));
  v_normalized text := private.normalize_member_name(p_name);
  v_member uuid;
begin
  perform private.lock_rating_state();
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

  perform private.refresh_player_statistics();
end;$repair_1_desired$),
('public.select_member(uuid)', 'public.select_member(p_member_id uuid)', 'void', false, $repair_2_base$declare
  v_actor uuid := private.require_allowed_session();
begin
  if private.is_admin(v_actor) then
    raise exception using errcode = 'P0001', message = '管理员请使用独立账号';
  end if;
  if coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true' then
    raise exception using errcode = 'P0001', message = '此账号不能选择普通成员';
  end if;
  if not exists (select 1 from public.members m where m.id = p_member_id) then
    raise exception using errcode = 'P0001', message = '成员不存在';
  end if;

  insert into private.session_members(auth_user_id, member_id, selected_at)
  values (v_actor, p_member_id, now())
  on conflict (auth_user_id) do update
    set member_id = excluded.member_id,
        selected_at = excluded.selected_at;
end;$repair_2_base$, $repair_2_desired$declare
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
end;$repair_2_desired$),
('public.club_snapshot()', 'public.club_snapshot()', 'jsonb', true, $repair_3_base$declare
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
        'id', m.id::text,
        'name', m.name
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
end;$repair_3_base$, $repair_3_desired$declare
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
    'member_baseline_schema_version', 1,
    'event_schema_version', 1,
    'rating_schema_version', 1,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.member_id::text,
        'name', m.name,
        'mmr', m.current_mmr,
        'mmr_baseline', m.mmr_baseline,
        'current_stats', to_jsonb(m),
        'legacy_stats', (select c.source from private.member_carryovers c where c.member_id = m.member_id)
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
          join public.players m on m.member_id = gp.member_id
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
end;$repair_3_desired$),
('public.save_score(uuid,uuid,integer,integer,uuid)', 'public.save_score(p_game_id uuid, p_member_id uuid, p_score integer, p_expected_version integer, p_request_id uuid)', 'void', false, $repair_4_base$declare
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
end;$repair_4_base$, $repair_4_desired$declare
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
      select m.member_id as id
        from public.game_players gp
        join public.players m on m.member_id = gp.member_id
       where gp.game_id = p_game_id
       order by m.member_id
    loop
      select m.current_mmr into v_locked_mmr
        from public.players m
       where m.member_id = v_row.id
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
          from public.players m
         where m.member_id = v_row.id;
      end if;
      if v_locked_mmr is distinct from v_expected_mmr then
        raise exception using
          errcode = 'P0001',
          message = '当前 MMR 与不可变评级历史不一致，请先完成基线迁移';
      end if;
    end loop;

    select array_agg(gp.member_id order by gp.member_id),
           array_agg(gp.score order by gp.member_id),
           array_agg(m.current_mmr order by gp.member_id)
      into v_member_ids, v_scores, v_old_mmrs
      from public.game_players gp
      join public.players m on m.member_id = gp.member_id
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
      update public.players
         set current_mmr = (v_row.value ->> 'new_mmr')::double precision
       where member_id = (v_row.value ->> 'member_id')::uuid;
    end loop;

    update public.games
       set status = 'completed', completed_at = now(), version = v_next_version
     where id = p_game_id;
    perform private.refresh_player_statistics();
  else
    update public.games
       set version = v_next_version
     where id = p_game_id;
  end if;
end;$repair_4_desired$),
('public.correct_scores(uuid,jsonb,integer,uuid)', 'public.correct_scores(p_game_id uuid, p_scores jsonb, p_expected_version integer, p_request_id uuid)', 'void', false, $repair_5_base$declare
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
end;$repair_5_base$, $repair_5_desired$declare
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
    perform private.refresh_player_statistics();
  end if;
end;$repair_5_desired$),
('public.cancel_game(uuid,text,integer,uuid)', 'public.cancel_game(p_game_id uuid, p_reason text, p_expected_version integer, p_request_id uuid)', 'void', false, $repair_6_base$declare
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
end;$repair_6_base$, $repair_6_desired$declare
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
end;$repair_6_desired$),
('public.sit_down(text,text)', 'public.sit_down(p_room_id text, p_wind text)', 'void', false, $repair_7_base$declare
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
end;$repair_7_base$, $repair_7_desired$declare
  v_member uuid := private.require_member_actor();
  v_wind text := private.require_wind(p_wind);
  v_source_room text;
  v_lock_room text;
  v_existing uuid;
begin
  if p_room_id is null then
    raise exception using errcode = 'P0001', message = '房间不存在';
  end if;
  if v_wind is null then
    raise exception using errcode = 'P0001', message = '无效的座位';
  end if;

  -- Serialize moves for one member, including requests from different devices.
  perform pg_advisory_xact_lock(hashtext(v_member::text));
  select rs.room_id into v_source_room
    from public.room_seats rs where rs.member_id = v_member;

  -- Lock both rooms in a fixed order before locking any seat rows. This also
  -- serializes moves with starts/leaves and avoids opposite-direction deadlocks.
  for v_lock_room in
    select distinct room_id
      from unnest(array[p_room_id, v_source_room]) as involved(room_id)
     where room_id is not null
     order by room_id
  loop
    perform private.lock_room(v_lock_room);
  end loop;

  -- An administrator may have cleared the old seat while we waited for a room.
  -- Re-read after the parent locks; a removed seat becomes a normal new sit.
  select rs.room_id into v_source_room
    from public.room_seats rs where rs.member_id = v_member for update;

  if exists (
    select 1 from public.games g
     where g.room_id in (p_room_id, v_source_room) and g.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = '对局进行中，暂不能调整座位';
  end if;

  select rs.member_id into v_existing
    from public.room_seats rs
   where rs.room_id = p_room_id and rs.wind = v_wind
   for update;
  if v_existing = v_member then
    return;
  end if;
  if v_existing is not null then
    raise exception using errcode = 'P0001', message = '该座位已被占用';
  end if;

  -- Updating the member's unique row releases the old seat only when the new
  -- seat is accepted. Errors roll back the whole statement/transaction.
  insert into public.room_seats(room_id, wind, member_id)
  values (p_room_id, v_wind, v_member)
  on conflict (member_id) do update
    set room_id = excluded.room_id,
        wind = excluded.wind,
        seated_at = now();
end;$repair_7_desired$),
('public.leave_seat(text,uuid)', 'public.leave_seat(p_room_id text, p_member_id uuid DEFAULT NULL)', 'void', false, $repair_8_base$declare
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
end;$repair_8_base$, $repair_8_desired$declare
  v_actor uuid := private.require_allowed_session();
  v_admin boolean := private.is_admin(v_actor);
  v_member uuid;
  v_target uuid;
begin
  if v_admin then
    if p_member_id is null then
      raise exception using errcode = 'P0001', message = '管理员清理座位时必须指定成员';
    end if;
    v_target := p_member_id;
  else
    if coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true' then
      raise exception using errcode = 'P0001', message = '此账号不能操作座位';
    end if;
    v_member := private.require_member_actor();
    v_target := coalesce(p_member_id, v_member);
  end if;

  perform private.lock_room(p_room_id);
  if exists (
    select 1 from public.games g
     where g.room_id = p_room_id and g.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = '对局进行中，暂不能离座';
  end if;

  -- The presence lease is deleted by its existing FK cascade. An old
  -- heartbeat cannot recreate the removed seat or its lease.
  delete from public.room_seats
   where room_id = p_room_id and member_id = v_target;
end;$repair_8_desired$),
('public.start_game(text,uuid)', 'public.start_game(p_room_id text, p_request_id uuid)', 'void', false, $repair_9_base$declare
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
end;$repair_9_base$, $repair_9_desired$begin
  perform public.start_game(
    p_room_id => p_room_id,
    p_request_id => p_request_id,
    p_event_id => null::uuid
  );
end;$repair_9_desired$)

      ) AS target(identity_signature, ddl_signature, return_type, is_stable, base_source, desired_source)
  LOOP
    v_oid := to_regprocedure(v_target.identity_signature);
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'Repair stopped: target function % is missing', v_target.identity_signature;
    END IF;

    SELECT p.prosrc
      INTO v_current_source
      FROM pg_proc p
     WHERE p.oid = v_oid;
    v_normalized_source := regexp_replace(v_current_source, '[[:space:]]', '', 'g');
    v_is_base := v_normalized_source = regexp_replace(v_target.base_source, '[[:space:]]', '', 'g');
    v_is_desired := v_normalized_source = regexp_replace(v_target.desired_source, '[[:space:]]', '', 'g');

    IF NOT v_is_base AND NOT v_is_desired THEN
      RAISE EXCEPTION 'Repair stopped: % has an unrecognized body; no function was accepted for replacement', v_target.identity_signature;
    END IF;

    INSERT INTO private.restore_players_api_20260924_backups (
      function_signature, function_oid, function_definition, prosrc,
      proowner, proacl, proconfig, function_comment
    )
    SELECT v_target.identity_signature,
           p.oid,
           pg_get_functiondef(p.oid),
           p.prosrc,
           p.proowner,
           p.proacl,
           p.proconfig,
           obj_description(p.oid, 'pg_proc')
      FROM pg_proc p
     WHERE p.oid = v_oid
    ON CONFLICT (function_signature) DO NOTHING;

    IF v_is_base THEN
      EXECUTE format(
        'CREATE OR REPLACE FUNCTION %s RETURNS %s LANGUAGE plpgsql %s SECURITY DEFINER SET search_path = pg_catalog, public, private AS %L',
        v_target.ddl_signature,
        v_target.return_type,
        CASE WHEN v_target.is_stable THEN 'STABLE' ELSE 'VOLATILE' END,
        v_target.desired_source
      );
    END IF;
  END LOOP;
END;
$repair$;

COMMIT;
