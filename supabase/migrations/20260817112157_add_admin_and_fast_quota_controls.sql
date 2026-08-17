-- Administrative RBAC and server-enforced Fast Responses allowances.

create table public.app_user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'member'
    check (role in ('member', 'admin', 'superadmin')),
  updated_at timestamptz not null default now()
);

alter table public.app_user_roles enable row level security;
revoke all on table public.app_user_roles from public, anon, authenticated;
grant select on table public.app_user_roles to authenticated;
grant all on table public.app_user_roles to service_role;

create policy "Users can read their own application role"
  on public.app_user_roles for select to authenticated
  using ((select auth.uid()) = user_id);

insert into public.app_user_roles (user_id, role)
select id, 'superadmin'
from auth.users
where lower(email) = 'muzamilghafoor2004@icloud.com'
on conflict (user_id) do update
set role = 'superadmin', updated_at = now();

alter table public.ai_user_limits
  add column monthly_fast_request_limit integer not null default 100
    check (monthly_fast_request_limit >= 0);

alter table public.ai_usage_monthly
  add column fast_request_count integer not null default 0
    check (fast_request_count >= 0);

alter table public.ai_request_log
  add column service_tier text not null default 'default'
    check (service_tier in ('default', 'fast'));

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select role from public.app_user_roles where user_id = (select auth.uid())
  ), 'member');
$$;

revoke all on function public.current_app_role() from public, anon;
grant execute on function public.current_app_role() to authenticated;

create or replace function public.admin_list_users()
returns table (
  user_id uuid,
  email text,
  role text,
  ai_enabled boolean,
  request_count integer,
  monthly_request_limit integer,
  tokens_used bigint,
  monthly_token_limit bigint,
  fast_request_count integer,
  monthly_fast_request_limit integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.current_app_role() not in ('admin', 'superadmin') then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  return query
  select
    users.id,
    users.email::text,
    coalesce(nullif(roles.role, ''), 'member'),
    coalesce(limits.enabled, true),
    coalesce(usage.request_count, 0),
    coalesce(limits.monthly_request_limit, 1000),
    coalesce(usage.input_tokens + usage.output_tokens, 0::bigint),
    coalesce(limits.monthly_token_limit, 5000000::bigint),
    coalesce(usage.fast_request_count, 0),
    coalesce(limits.monthly_fast_request_limit, 100)
  from auth.users users
  left join public.app_user_roles roles on roles.user_id = users.id
  left join public.ai_user_limits limits on limits.user_id = users.id
  left join public.ai_usage_monthly usage
    on usage.user_id = users.id
   and usage.usage_month = date_trunc('month', now() at time zone 'utc')::date
  order by lower(users.email), users.id;
end;
$$;

revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

create or replace function public.admin_update_user(
  p_user_id uuid,
  p_enabled boolean default null,
  p_monthly_request_limit integer default null,
  p_monthly_token_limit bigint default null,
  p_monthly_fast_request_limit integer default null,
  p_role text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_actor_role text := public.current_app_role();
  v_target_role text;
begin
  if v_actor is null or v_actor_role not in ('admin', 'superadmin') then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;

  select coalesce(nullif(role, ''), 'member') into v_target_role
  from public.app_user_roles where user_id = p_user_id;
  v_target_role := coalesce(v_target_role, 'member');

  if v_actor_role = 'admin' and v_target_role = 'superadmin' then
    raise exception 'superadmin_required' using errcode = '42501';
  end if;

  if p_role is not null then
    if v_actor_role <> 'superadmin' then
      raise exception 'superadmin_required' using errcode = '42501';
    end if;
    if p_role not in ('member', 'admin', 'superadmin') then
      raise exception 'invalid_role' using errcode = '22023';
    end if;
    if v_actor = p_user_id and v_target_role = 'superadmin'
       and p_role <> 'superadmin' then
      raise exception 'cannot_demote_self' using errcode = '42501';
    end if;
    insert into public.app_user_roles (user_id, role, updated_at)
    values (p_user_id, p_role, now())
    on conflict (user_id) do update
    set role = excluded.role, updated_at = excluded.updated_at;
  end if;

  if p_enabled is not null or p_monthly_request_limit is not null
     or p_monthly_token_limit is not null
     or p_monthly_fast_request_limit is not null then
    if (p_monthly_request_limit is not null
        and p_monthly_request_limit not between 1 and 10000)
       or (p_monthly_token_limit is not null
        and p_monthly_token_limit not between 1000 and 100000000)
       or (p_monthly_fast_request_limit is not null
        and p_monthly_fast_request_limit not between 0 and 10000) then
      raise exception 'invalid_limit' using errcode = '22023';
    end if;
    insert into public.ai_user_limits (
      user_id, enabled, monthly_request_limit, monthly_token_limit,
      monthly_fast_request_limit
    ) values (
      p_user_id, coalesce(p_enabled, true),
      coalesce(p_monthly_request_limit, 1000),
      coalesce(p_monthly_token_limit, 5000000),
      coalesce(p_monthly_fast_request_limit, 100)
    )
    on conflict (user_id) do update set
      enabled = coalesce(p_enabled, public.ai_user_limits.enabled),
      monthly_request_limit = coalesce(
        p_monthly_request_limit, public.ai_user_limits.monthly_request_limit),
      monthly_token_limit = coalesce(
        p_monthly_token_limit, public.ai_user_limits.monthly_token_limit),
      monthly_fast_request_limit = coalesce(
        p_monthly_fast_request_limit,
        public.ai_user_limits.monthly_fast_request_limit),
      updated_at = now();
  end if;
  return true;
end;
$$;

revoke all on function public.admin_update_user(uuid, boolean, integer, bigint, integer, text)
  from public, anon;
grant execute on function public.admin_update_user(uuid, boolean, integer, bigint, integer, text)
  to authenticated;

create function public.reserve_ai_request(
  p_user_id uuid,
  p_request_id uuid,
  p_client_turn_id uuid,
  p_model text,
  p_estimated_tokens bigint,
  p_requested_service_tier text
)
returns table (
  allowed boolean,
  code text,
  request_id uuid,
  monthly_request_limit integer,
  monthly_token_limit bigint,
  remaining_requests integer,
  remaining_tokens bigint,
  effective_service_tier text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base record;
  v_fast_used integer := 0;
  v_fast_limit integer := 100;
  v_effective text := 'default';
begin
  select * into v_base from public.reserve_ai_request(
    p_user_id, p_request_id, p_client_turn_id, p_model, p_estimated_tokens
  );

  if v_base.allowed and p_requested_service_tier = 'fast' then
    select coalesce(usage.fast_request_count, 0),
           coalesce(limits.monthly_fast_request_limit, 100)
      into v_fast_used, v_fast_limit
    from (select 1) seed
    left join public.ai_usage_monthly usage
      on usage.user_id = p_user_id
     and usage.usage_month = date_trunc('month', now() at time zone 'utc')::date
    left join public.ai_user_limits limits on limits.user_id = p_user_id;
    if v_fast_used < v_fast_limit then
      v_effective := 'fast';
      update public.ai_usage_monthly
      set fast_request_count = fast_request_count + 1, updated_at = now()
      where user_id = p_user_id
        and usage_month = date_trunc('month', now() at time zone 'utc')::date;
      update public.ai_request_log set service_tier = 'fast'
      where request_id = p_request_id;
    end if;
  end if;

  return query select v_base.allowed, v_base.code, v_base.request_id,
    v_base.monthly_request_limit, v_base.monthly_token_limit,
    v_base.remaining_requests, v_base.remaining_tokens, v_effective;
end;
$$;

revoke all on function public.reserve_ai_request(uuid, uuid, uuid, text, bigint, text)
  from public, anon, authenticated;
grant execute on function public.reserve_ai_request(uuid, uuid, uuid, text, bigint, text)
  to service_role;
