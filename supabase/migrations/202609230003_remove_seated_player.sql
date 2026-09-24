-- Identified members may clear an absent player's seat before a game starts.
-- Keep the existing RPC signature and administrator behavior. Room locking
-- serializes removal with seating and game start; game history is untouched.
begin;

create or replace function public.leave_seat(
  p_room_id text,
  p_member_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
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
end;
$$;

revoke all on function public.leave_seat(text, uuid) from public, anon, authenticated;
grant execute on function public.leave_seat(text, uuid) to authenticated;

commit;
