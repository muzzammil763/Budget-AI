-- The connected project applied this bootstrap in three MCP transactions to
-- stay within the gateway timeout. Keeping the full bootstrap in the first
-- migration makes a fresh local Supabase database reach the identical schema.
create table public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null,
  request_count integer not null default 0 check (request_count >= 0),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  cached_input_tokens bigint not null default 0 check (cached_input_tokens >= 0),
  reserved_tokens bigint not null default 0 check (reserved_tokens >= 0),
  active_request_count integer not null default 0 check (active_request_count >= 0),
  failed_request_count integer not null default 0 check (failed_request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date)
);

create table public.ai_user_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  daily_request_limit integer not null default 50
    check (daily_request_limit between 1 and 10000),
  daily_token_limit bigint not null default 250000
    check (daily_token_limit between 1000 and 100000000),
  max_concurrent_requests integer not null default 2
    check (max_concurrent_requests between 1 and 10),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ai_request_log (
  request_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  client_turn_id uuid not null,
  usage_date date not null,
  model text not null,
  status text not null
    check (status in ('started', 'completed', 'failed', 'cancelled', 'abandoned')),
  reserved_tokens bigint not null default 0 check (reserved_tokens >= 0),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  cached_input_tokens bigint not null default 0 check (cached_input_tokens >= 0),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  error_code text,
  unique (user_id, client_turn_id)
);

create index ai_request_log_user_started_idx
  on public.ai_request_log (user_id, started_at desc);

alter table public.ai_usage_daily enable row level security;
alter table public.ai_user_limits enable row level security;
alter table public.ai_request_log enable row level security;

create policy "Users can read their own AI usage"
  on public.ai_usage_daily
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can read their own AI limits"
  on public.ai_user_limits
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.ai_usage_daily from public, anon, authenticated;
revoke all on table public.ai_user_limits from public, anon, authenticated;
revoke all on table public.ai_request_log from public, anon, authenticated;

grant select on table public.ai_usage_daily to authenticated;
grant select on table public.ai_user_limits to authenticated;
grant all on table public.ai_usage_daily to service_role;
grant all on table public.ai_user_limits to service_role;
grant all on table public.ai_request_log to service_role;

create or replace function public.reserve_ai_request(
  p_user_id uuid,
  p_request_id uuid,
  p_client_turn_id uuid,
  p_model text,
  p_estimated_tokens bigint
)
returns table (
  allowed boolean,
  code text,
  request_id uuid,
  daily_request_limit integer,
  daily_token_limit bigint,
  remaining_requests integer,
  remaining_tokens bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
  v_usage public.ai_usage_daily%rowtype;
  v_enabled boolean := true;
  v_request_limit integer := 50;
  v_token_limit bigint := 250000;
  v_concurrent_limit integer := 2;
  v_estimate bigint := greatest(1, least(p_estimated_tokens, 100000));
  v_stale_count integer := 0;
  v_stale_reserved bigint := 0;
begin
  if p_user_id is null
    or p_request_id is null
    or p_client_turn_id is null
    or nullif(trim(p_model), '') is null then
    return query select false, 'invalid_request', p_request_id, 0, 0::bigint, 0, 0::bigint;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text || ':' || p_client_turn_id::text, 0)
  );

  if exists (
    select 1
    from public.ai_request_log log
    where log.user_id = p_user_id
      and log.client_turn_id = p_client_turn_id
  ) then
    return query select false, 'duplicate_request', p_request_id, 0, 0::bigint, 0, 0::bigint;
    return;
  end if;

  insert into public.ai_usage_daily (user_id, usage_date)
  values (p_user_id, v_today)
  on conflict (user_id, usage_date) do nothing;

  select *
  into v_usage
  from public.ai_usage_daily usage
  where usage.user_id = p_user_id
    and usage.usage_date = v_today
  for update;

  select
    coalesce(limits.enabled, true),
    coalesce(limits.daily_request_limit, 50),
    coalesce(limits.daily_token_limit, 250000),
    coalesce(limits.max_concurrent_requests, 2)
  into
    v_enabled,
    v_request_limit,
    v_token_limit,
    v_concurrent_limit
  from (select 1) seed
  left join public.ai_user_limits limits
    on limits.user_id = p_user_id;

  select
    count(*)::integer,
    coalesce(sum(log.reserved_tokens), 0)::bigint
  into v_stale_count, v_stale_reserved
  from public.ai_request_log log
  where log.user_id = p_user_id
    and log.usage_date = v_today
    and log.status = 'started'
    and log.started_at < now() - interval '15 minutes';

  if v_stale_count > 0 then
    update public.ai_request_log log
    set
      status = 'abandoned',
      completed_at = now(),
      error_code = 'stale_request'
    where log.user_id = p_user_id
      and log.usage_date = v_today
      and log.status = 'started'
      and log.started_at < now() - interval '15 minutes';

    update public.ai_usage_daily usage
    set
      active_request_count = greatest(0, usage.active_request_count - v_stale_count),
      reserved_tokens = greatest(0, usage.reserved_tokens - v_stale_reserved),
      failed_request_count = usage.failed_request_count + v_stale_count,
      updated_at = now()
    where usage.user_id = p_user_id
      and usage.usage_date = v_today
    returning * into v_usage;
  end if;

  if not v_enabled then
    return query
      select false, 'account_disabled', p_request_id, v_request_limit, v_token_limit,
        greatest(0, v_request_limit - v_usage.request_count),
        greatest(0::bigint, v_token_limit - v_usage.input_tokens - v_usage.output_tokens - v_usage.reserved_tokens);
    return;
  end if;

  if v_usage.request_count >= v_request_limit then
    return query
      select false, 'daily_request_limit', p_request_id, v_request_limit, v_token_limit,
        0, greatest(0::bigint, v_token_limit - v_usage.input_tokens - v_usage.output_tokens - v_usage.reserved_tokens);
    return;
  end if;

  if v_usage.input_tokens + v_usage.output_tokens + v_usage.reserved_tokens + v_estimate > v_token_limit then
    return query
      select false, 'daily_token_limit', p_request_id, v_request_limit, v_token_limit,
        greatest(0, v_request_limit - v_usage.request_count),
        greatest(0::bigint, v_token_limit - v_usage.input_tokens - v_usage.output_tokens - v_usage.reserved_tokens);
    return;
  end if;

  if v_usage.active_request_count >= v_concurrent_limit then
    return query
      select false, 'concurrent_request_limit', p_request_id, v_request_limit, v_token_limit,
        greatest(0, v_request_limit - v_usage.request_count),
        greatest(0::bigint, v_token_limit - v_usage.input_tokens - v_usage.output_tokens - v_usage.reserved_tokens);
    return;
  end if;

  update public.ai_usage_daily usage
  set
    request_count = usage.request_count + 1,
    reserved_tokens = usage.reserved_tokens + v_estimate,
    active_request_count = usage.active_request_count + 1,
    updated_at = now()
  where usage.user_id = p_user_id
    and usage.usage_date = v_today
  returning * into v_usage;

  insert into public.ai_request_log (
    request_id,
    user_id,
    client_turn_id,
    usage_date,
    model,
    status,
    reserved_tokens
  )
  values (
    p_request_id,
    p_user_id,
    p_client_turn_id,
    v_today,
    p_model,
    'started',
    v_estimate
  );

  return query
    select true, 'allowed', p_request_id, v_request_limit, v_token_limit,
      greatest(0, v_request_limit - v_usage.request_count),
      greatest(0::bigint, v_token_limit - v_usage.input_tokens - v_usage.output_tokens - v_usage.reserved_tokens);
end;
$$;

create or replace function public.finalize_ai_request(
  p_request_id uuid,
  p_status text,
  p_input_tokens bigint default 0,
  p_output_tokens bigint default 0,
  p_cached_input_tokens bigint default 0,
  p_error_code text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_log public.ai_request_log%rowtype;
  v_status text := case
    when p_status in ('completed', 'failed', 'cancelled') then p_status
    else 'failed'
  end;
begin
  select *
  into v_log
  from public.ai_request_log log
  where log.request_id = p_request_id
  for update;

  if not found or v_log.status <> 'started' then
    return false;
  end if;

  update public.ai_usage_daily usage
  set
    input_tokens = usage.input_tokens + greatest(0, p_input_tokens),
    output_tokens = usage.output_tokens + greatest(0, p_output_tokens),
    cached_input_tokens = usage.cached_input_tokens + greatest(0, p_cached_input_tokens),
    reserved_tokens = greatest(0, usage.reserved_tokens - v_log.reserved_tokens),
    active_request_count = greatest(0, usage.active_request_count - 1),
    failed_request_count = usage.failed_request_count
      + case when v_status = 'completed' then 0 else 1 end,
    updated_at = now()
  where usage.user_id = v_log.user_id
    and usage.usage_date = v_log.usage_date;

  update public.ai_request_log log
  set
    status = v_status,
    input_tokens = greatest(0, p_input_tokens),
    output_tokens = greatest(0, p_output_tokens),
    cached_input_tokens = greatest(0, p_cached_input_tokens),
    completed_at = now(),
    error_code = nullif(left(coalesce(p_error_code, ''), 120), '')
  where log.request_id = p_request_id;

  return true;
end;
$$;

revoke all on function public.reserve_ai_request(uuid, uuid, uuid, text, bigint)
  from public, anon, authenticated;
revoke all on function public.finalize_ai_request(uuid, text, bigint, bigint, bigint, text)
  from public, anon, authenticated;

grant execute on function public.reserve_ai_request(uuid, uuid, uuid, text, bigint)
  to service_role;
grant execute on function public.finalize_ai_request(uuid, text, bigint, bigint, bigint, text)
  to service_role;
