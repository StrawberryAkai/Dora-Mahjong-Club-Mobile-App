-- Apply after the existing club migrations. Replaces only sit_down; existing
-- authentication, execute grants, tables, and stored seats are preserved.
-- A single RPC moves a member atomically; never call leave_seat first.
begin;

create or replace function public.sit_down(p_room_id text, p_wind text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
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
end;
$$;

commit;
