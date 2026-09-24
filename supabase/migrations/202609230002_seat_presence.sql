-- Seat ownership is a short lease tied to one authenticated client session.
-- Legacy seat writes receive an unowned grace lease; only the owned RPCs can
-- renew a lease or release one on behalf of its current owner.
begin;

create table if not exists private.seat_presence (
  member_id uuid primary key
    references public.room_seats(member_id) on delete cascade on update cascade,
  owner_auth_id uuid references auth.users(id) on delete cascade,
  client_id uuid,
  expires_at timestamptz not null,
  constraint seat_presence_owner_pair check (
    (owner_auth_id is null and client_id is null)
    or (owner_auth_id is not null and client_id is not null)
  )
);

alter table private.seat_presence enable row level security;
revoke all on private.seat_presence from public, anon, authenticated;

-- Preserve all current seats for a brief upgrade grace period. Reruns never
-- replace ownership or expiry already recorded by an earlier execution.
insert into private.seat_presence(member_id, owner_auth_id, client_id, expires_at)
select rs.member_id, null, null, clock_timestamp() + interval '60 seconds'
  from public.room_seats rs
on conflict (member_id) do nothing;

create or replace function private.lock_seat_rooms()
returns text[]
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_room_id text;
  v_room_ids text[] := array[]::text[];
begin
  for v_room_id in select r.id from public.rooms r order by r.id loop
    perform private.lock_room(v_room_id);
    v_room_ids := array_append(v_room_ids, v_room_id);
  end loop;
  return v_room_ids;
end;
$$;

-- Call only after the room locks named by p_room_ids are held.
create or replace function private.sweep_seat_presence_locked(
  p_room_ids text[],
  p_as_of timestamptz
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_removed integer;
begin
  delete from public.room_seats rs
   where rs.room_id = any(p_room_ids)
     and not exists (
       select 1 from public.games g
        where g.room_id = rs.room_id and g.status = 'active'
     )
     and (
       not exists (
         select 1 from private.seat_presence sp
          where sp.member_id = rs.member_id
       )
       or exists (
         select 1 from private.seat_presence sp
          where sp.member_id = rs.member_id and sp.expires_at <= p_as_of
       )
     );
  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

create or replace function private.grant_legacy_seat_grace()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_seat_changed boolean;
begin
  if tg_op = 'INSERT' then
    v_seat_changed := true;
  else
    v_seat_changed := (new.room_id, new.wind) is distinct from (old.room_id, old.wind);
  end if;

  if v_seat_changed then
    insert into private.seat_presence(member_id, owner_auth_id, client_id, expires_at)
    values (new.member_id, null, null, clock_timestamp() + interval '60 seconds')
    on conflict (member_id) do update
      set owner_auth_id = null,
          client_id = null,
          expires_at = excluded.expires_at;
  end if;
  return new;
end;
$$;

drop trigger if exists room_seats_legacy_presence on public.room_seats;
create trigger room_seats_legacy_presence
after insert or update of room_id, wind on public.room_seats
for each row execute function private.grant_legacy_seat_grace();

-- Catch writes that committed between the initial backfill and trigger install.
insert into private.seat_presence(member_id, owner_auth_id, client_id, expires_at)
select rs.member_id, null, null, clock_timestamp() + interval '60 seconds'
  from public.room_seats rs
on conflict (member_id) do nothing;

create or replace function public.sit_down_owned(
  p_room_id text,
  p_wind text,
  p_client_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid;
  v_member uuid;
  v_wind text := private.require_wind(p_wind);
  v_source_room text;
  v_lock_room text;
  v_existing uuid;
begin
  v_member := private.require_member_actor();
  v_actor := auth.uid();
  if p_room_id is null then
    raise exception using errcode = 'P0001', message = '房间不存在';
  end if;
  if v_wind is null then
    raise exception using errcode = 'P0001', message = '无效的座位';
  end if;
  if p_client_id is null then
    raise exception using errcode = 'P0001', message = '客户端会话无效';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_member::text));
  select rs.room_id into v_source_room
    from public.room_seats rs where rs.member_id = v_member;

  for v_lock_room in
    select distinct room_id
      from unnest(array[p_room_id, v_source_room]) as involved(room_id)
     where room_id is not null
     order by room_id
  loop
    perform private.lock_room(v_lock_room);
  end loop;

  -- Clear expired or legacy-unleased seats only in the rooms this move holds.
  perform private.sweep_seat_presence_locked(
    array[p_room_id, v_source_room], clock_timestamp()
  );

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
  if v_existing is not null and v_existing <> v_member then
    raise exception using errcode = 'P0001', message = '该座位已被占用';
  end if;

  insert into public.room_seats(room_id, wind, member_id)
  values (p_room_id, v_wind, v_member)
  on conflict (member_id) do update
    set room_id = excluded.room_id,
        wind = excluded.wind,
        seated_at = clock_timestamp();

  -- The legacy-write trigger above may have installed a grace lease. Replace
  -- it after the seat write so this explicit action owns the resulting seat.
  insert into private.seat_presence(member_id, owner_auth_id, client_id, expires_at)
  values (v_member, v_actor, p_client_id, clock_timestamp() + interval '60 seconds')
  on conflict (member_id) do update
    set owner_auth_id = excluded.owner_auth_id,
        client_id = excluded.client_id,
        expires_at = excluded.expires_at;
end;
$$;

create or replace function public.touch_seat_presence(p_client_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid;
  v_member uuid;
  v_rooms text[];
begin
  v_actor := private.require_allowed_session();
  if p_client_id is null then
    raise exception using errcode = 'P0001', message = '客户端会话无效';
  end if;
  v_member := private.current_member_id();
  v_rooms := private.lock_seat_rooms();

  if v_member is not null then
    update private.seat_presence sp
       set expires_at = clock_timestamp() + interval '60 seconds'
     where sp.member_id = v_member
       and sp.owner_auth_id = v_actor
       and sp.client_id = p_client_id
       and sp.expires_at > clock_timestamp();
  end if;

  perform private.sweep_seat_presence_locked(v_rooms, clock_timestamp());
end;
$$;

create or replace function public.sweep_seat_presence()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_rooms text[];
begin
  perform private.require_allowed_session();
  v_rooms := private.lock_seat_rooms();
  return private.sweep_seat_presence_locked(v_rooms, clock_timestamp());
end;
$$;

create or replace function public.release_seat_presence(p_client_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid;
  v_member uuid;
  v_room_id text;
begin
  v_actor := private.require_allowed_session();
  if p_client_id is null then
    raise exception using errcode = 'P0001', message = '客户端会话无效';
  end if;
  v_member := private.current_member_id();
  if v_member is null then
    return;
  end if;

  -- Serialize with explicit moves before discovering and locking the current
  -- seat room. Ownership is checked again after that room lock is acquired.
  perform pg_advisory_xact_lock(hashtext(v_member::text));
  select rs.room_id into v_room_id
    from private.seat_presence sp
    join public.room_seats rs on rs.member_id = sp.member_id
   where sp.member_id = v_member
     and sp.owner_auth_id = v_actor
     and sp.client_id = p_client_id;
  if v_room_id is null then
    return;
  end if;
  perform private.lock_room(v_room_id);

  update private.seat_presence sp
     set expires_at = clock_timestamp()
   where sp.member_id = v_member
     and sp.owner_auth_id = v_actor
     and sp.client_id = p_client_id
     and exists (
       select 1 from public.room_seats rs
        where rs.member_id = sp.member_id and rs.room_id = v_room_id
     );
  if not found then
    return;
  end if;

  if not exists (
    select 1 from public.games g
     where g.room_id = v_room_id and g.status = 'active'
  ) then
    delete from public.room_seats rs
     where rs.room_id = v_room_id and rs.member_id = v_member;
  end if;
end;
$$;

create or replace function private.guard_active_game_seat_presence()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.status <> 'active' then
    return new;
  end if;
  perform private.lock_room(new.room_id);
  if exists (
    select 1
      from public.room_seats rs
      left join private.seat_presence sp on sp.member_id = rs.member_id
     where rs.room_id = new.room_id
       and (sp.member_id is null or sp.expires_at <= clock_timestamp())
  ) then
    raise exception using errcode = 'P0001', message = '有成员座位已失效，请刷新房间后重试';
  end if;
  return new;
end;
$$;

drop trigger if exists games_require_live_seat_presence on public.games;
create trigger games_require_live_seat_presence
before insert on public.games
for each row execute function private.guard_active_game_seat_presence();

create or replace function private.clear_pending_seats_after_game()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_room_id text;
begin
  -- Do not wait here: end-game RPCs already hold the game row, while starts
  -- take the room row first. A skipped cleanup is handled by the next sweep.
  select r.id into v_room_id
    from public.rooms r
   where r.id = new.room_id
   for update skip locked;
  if not found then
    return new;
  end if;

  delete from public.room_seats rs
   where rs.room_id = new.room_id
     and not exists (
       select 1 from public.games g
        where g.room_id = rs.room_id and g.status = 'active'
     )
     and (
       not exists (
         select 1 from private.seat_presence sp
          where sp.member_id = rs.member_id
       )
       or exists (
         select 1 from private.seat_presence sp
          where sp.member_id = rs.member_id
            and sp.expires_at <= clock_timestamp()
       )
     );
  return new;
end;
$$;

drop trigger if exists games_clear_pending_seats on public.games;
create trigger games_clear_pending_seats
after update of status on public.games
for each row
when (old.status = 'active' and new.status in ('completed', 'cancelled'))
execute function private.clear_pending_seats_after_game();

revoke all on function private.lock_seat_rooms() from public, anon, authenticated;
revoke all on function private.sweep_seat_presence_locked(text[], timestamptz) from public, anon, authenticated;
revoke all on function private.grant_legacy_seat_grace() from public, anon, authenticated;
revoke all on function private.guard_active_game_seat_presence() from public, anon, authenticated;
revoke all on function private.clear_pending_seats_after_game() from public, anon, authenticated;

revoke all on function public.sit_down_owned(text, text, uuid) from public, anon, authenticated;
revoke all on function public.touch_seat_presence(uuid) from public, anon, authenticated;
revoke all on function public.sweep_seat_presence() from public, anon, authenticated;
revoke all on function public.release_seat_presence(uuid) from public, anon, authenticated;
grant execute on function public.sit_down_owned(text, text, uuid) to authenticated;
grant execute on function public.touch_seat_presence(uuid) to authenticated;
grant execute on function public.sweep_seat_presence() to authenticated;
grant execute on function public.release_seat_presence(uuid) to authenticated;

commit;
