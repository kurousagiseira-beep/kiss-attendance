-- Run in Supabase SQL editor. Create Auth users manually, then insert their UUIDs into profiles.
create table public.profiles(id uuid primary key references auth.users(id), name text not null, admin boolean not null default false);
create table public.attendance(user_id uuid references public.profiles(id), business_day date not null, started_at timestamptz not null, ended_at timestamptz, primary key(user_id,business_day), check(ended_at is null or ended_at>=started_at));
alter table public.profiles enable row level security;
alter table public.attendance enable row level security;
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles where id=auth.uid() and admin) $$;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy attendance_read on public.attendance for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy admin_update on public.attendance for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_insert on public.attendance for insert to authenticated with check(public.is_admin());
create function public.punch(kind text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); t timestamptz:=now(); d date:=((t at time zone 'Asia/Tokyo')-interval '18 hours')::date;
begin
if uid is null or not exists(select 1 from public.profiles where id=uid) then raise exception 'Unauthorized'; end if;
if kind='in' then insert into public.attendance(user_id,business_day,started_at) values(uid,d,t);
elsif kind='out' then update public.attendance set ended_at=t where user_id=uid and business_day=d and ended_at is null; if not found then raise exception 'No open attendance'; end if;
else raise exception 'Invalid action'; end if;
end $$;
revoke all on function public.punch(text) from public;
grant execute on function public.punch(text) to authenticated;
