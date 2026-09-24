-- Use the canonical players table in the APIs of the imported production club.
-- New installations already use players in migrations 001-003 and have no
-- imported carryovers. This upgrade preserves imported balances and statistics.
DO $players_api$
DECLARE
  v_target record;
  v_oid oid;
  v_hash text;
  v_missing text[];
BEGIN
  IF to_regclass('private.member_carryovers') IS NULL THEN
    RETURN;
  END IF;

  SELECT array_agg(required.signature ORDER BY required.signature)
    INTO v_missing
    FROM (VALUES
      ('private.require_allowed_session()'),
      ('private.require_anonymous_actor()'),
      ('private.current_member_id()'),
      ('private.is_admin(uuid)'),
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
    RAISE EXCEPTION 'Players API dependencies are missing: %', array_to_string(v_missing, ', ');
  END IF;

  -- Store function definitions only. No player, score, or balance rows are changed.
  CREATE TABLE IF NOT EXISTS private.player_api_definition_backups (
    function_signature text PRIMARY KEY,
    function_definition text NOT NULL,
    proowner oid NOT NULL,
    proacl aclitem[],
    backed_up_at timestamptz NOT NULL DEFAULT clock_timestamp()
  );
  ALTER TABLE private.player_api_definition_backups ENABLE ROW LEVEL SECURITY;
  REVOKE ALL ON TABLE private.player_api_definition_backups
    FROM PUBLIC, anon, authenticated, service_role;

  FOR v_target IN
    SELECT * FROM (VALUES
('private.actor_label(uuid)', 'private.actor_label(p_actor uuid)', 'text', true, 'e024970f87cc267be86adc3bcd56b967', '6da8f04c61166924b4227785878e436b', $repair_0$declare
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
end;$repair_0$),
('public.create_member(text)', 'public.create_member(p_name text)', 'void', false, '709d54508c3993f43a5a4c8516be7ac0', '6b43e34fe43bf9ee7d355a64ec4ae2db', $repair_1$declare
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
end;$repair_1$),
('public.select_member(uuid)', 'public.select_member(p_member_id uuid)', 'void', false, '56de5f9f09a502dda93c953af707e866', 'b0002735ff2e47d8961346ba4be4e60e', $repair_2$declare
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
end;$repair_2$),
('public.club_snapshot()', 'public.club_snapshot()', 'jsonb', true, 'bdaf038016fcf8fd38a1f86f5cadf164', '354781a6947136e6dcc5c3a50d08c5e8', $repair_3$declare
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
end;$repair_3$),
('public.save_score(uuid,uuid,integer,integer,uuid)', 'public.save_score(p_game_id uuid, p_member_id uuid, p_score integer, p_expected_version integer, p_request_id uuid)', 'void', false, '407fac18b6b53e178f5cfce254ed920b', '0c0db56420e1600979332c642d7be93a', $repair_4$declare
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
end;$repair_4$),
('public.correct_scores(uuid,jsonb,integer,uuid)', 'public.correct_scores(p_game_id uuid, p_scores jsonb, p_expected_version integer, p_request_id uuid)', 'void', false, 'b09809f403ed4c57ece5c2f1dffd9d5f', '8db2add92628732d4ee2499c89d90405', $repair_5$declare
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
end;$repair_5$),
('public.cancel_game(uuid,text,integer,uuid)', 'public.cancel_game(p_game_id uuid, p_reason text, p_expected_version integer, p_request_id uuid)', 'void', false, '73b41f928ad624730229598c10870872', 'ffd3a4d39af167d1ee2101e7d3b61643', $repair_6$declare
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
end;$repair_6$),
('public.start_game(text,uuid)', 'public.start_game(p_room_id text, p_request_id uuid)', 'void', false, 'aff972f9f6b1833a6a80506fbf1e6b44', 'fb47e4a5896af0555c98c34d09b5d67f', $repair_9$begin
  perform public.start_game(
    p_room_id => p_room_id,
    p_request_id => p_request_id,
    p_event_id => null::uuid
  );
end;$repair_9$)
    ) AS target(identity_signature, ddl_signature, return_type, is_stable,
                original_hash, desired_hash, source)
  LOOP
    v_oid := to_regprocedure(v_target.identity_signature);
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'Players API function is missing: %', v_target.identity_signature;
    END IF;
    SELECT md5(regexp_replace(p.prosrc, '[[:space:]]', '', 'g'))
      INTO v_hash FROM pg_proc p WHERE p.oid = v_oid;
    IF v_hash NOT IN (v_target.original_hash, v_target.desired_hash) THEN
      RAISE EXCEPTION 'Unrecognized function definition: %; review before replacing it',
        v_target.identity_signature;
    END IF;

    INSERT INTO private.player_api_definition_backups (
      function_signature, function_definition, proowner, proacl
    )
    SELECT v_target.identity_signature, pg_get_functiondef(p.oid), p.proowner, p.proacl
      FROM pg_proc p WHERE p.oid = v_oid
    ON CONFLICT (function_signature) DO NOTHING;

    IF v_hash <> v_target.desired_hash THEN
      EXECUTE format(
        'CREATE OR REPLACE FUNCTION %s RETURNS %s LANGUAGE plpgsql %s SECURITY DEFINER SET search_path = pg_catalog, public, private AS %L',
        v_target.ddl_signature, v_target.return_type,
        CASE WHEN v_target.is_stable THEN 'STABLE' ELSE 'VOLATILE' END,
        v_target.source
      );
    END IF;
  END LOOP;
END;
$players_api$;
