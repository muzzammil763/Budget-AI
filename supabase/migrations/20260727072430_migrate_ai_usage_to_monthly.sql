-- Switch AI usage tracking and limits from daily to monthly buckets.
-- Single-user pre-production app: existing daily rows are summed into the
-- new monthly table and the old daily table is dropped outright rather than
-- kept around or migrated incrementally.

create table public.ai_usage_monthly (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_month date not null,
  request_count integer not null default 0 check (request_count >= 0),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  cached_input_tokens bigint not null default 0 check (cached_input_tokens >= 0),
  reserved_tokens bigint not null default 0 check (reserved_tokens >= 0),
  active_request_count integer not null default 0 check (active_request_count >= 0),
  failed_request_count integer not null default 0 check (failed_request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_month)
);

alter table public.ai_usage_monthly enable row level security;

create policy "Users can read their own AI usage"
  on public.ai_usage_monthly
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.ai_usage_monthly from public, anon, authenticated;
grant select on table public.ai_usage_monthly to authenticated;
grant all on table public.ai_usage_monthly to service_role;

insert into public.ai_usage_monthly (
  user_id, usage_month, request_count, input_tokens, output_tokens,
  cached_input_tokens, reserved_tokens, active_request_count,
  failed_request_count, updated_at
)
select
  user_id,
  date_trunc('month', usage_date)::date,
  sum(request_count),
  sum(input_tokens),
  sum(output_tokens),
  sum(cached_input_tokens),
  sum(reserved_tokens),
  sum(active_request_count),
  sum(failed_request_count),
  now()
from public.ai_usage_daily
group by user_id, date_trunc('month', usage_date);

drop table public.ai_usage_daily;

alter table public.ai_request_log rename column usage_date to usage_period;

-- ai_user_limits only ever holds per-user overrides; clearing it lets the
-- new monthly defaults below apply cleanly via the coalesce fallback in
-- reserve_ai_request instead of carrying over stale daily-era numbers.
delete from public.ai_user_limits;

alter table public.ai_user_limits
  rename column daily_request_limit to monthly_request_limit;
alter table public.ai_user_limits
  rename column daily_token_limit to monthly_token_limit;
alter table public.ai_user_limits
  alter column monthly_request_limit set default 1000;
alter table public.ai_user_limits
  alter column monthly_token_limit set default 5000000;

drop function if exists public.reserve_ai_request(uuid, uuid, uuid, text, bigint);

create function public.reserve_ai_request(
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
  monthly_request_limit integer,
  monthly_token_limit bigint,
  remaining_requests integer,
  remaining_tokens bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', now() at time zone 'utc')::date;
  v_usage public.ai_usage_monthly%rowtype;
  v_enabled boolean := true;
  v_request_limit integer := 1000;
  v_token_limit bigint := 5000000;
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

  insert into public.ai_usage_monthly (user_id, usage_month)
  values (p_user_id, v_month)
  on conflict (user_id, usage_month) do nothing;

  select *
  into v_usage
  from public.ai_usage_monthly usage
  where usage.user_id = p_user_id
    and usage.usage_month = v_month
  for update;

  select
    coalesce(limits.enabled, true),
    coalesce(limits.monthly_request_limit, 1000),
    coalesce(limits.monthly_token_limit, 5000000),
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
    and log.usage_period = v_month
    and log.status = 'started'
    and log.started_at < now() - interval '15 minutes';

  if v_stale_count > 0 then
    update public.ai_request_log log
    set
      status = 'abandoned',
      completed_at = now(),
      error_code = 'stale_request'
    where log.user_id = p_user_id
      and log.usage_period = v_month
      and log.status = 'started'
      and log.started_at < now() - interval '15 minutes';

    update public.ai_usage_monthly usage
    set
      active_request_count = greatest(0, usage.active_request_count - v_stale_count),
      reserved_tokens = greatest(0, usage.reserved_tokens - v_stale_reserved),
      failed_request_count = usage.failed_request_count + v_stale_count,
      updated_at = now()
    where usage.user_id = p_user_id
      and usage.usage_month = v_month
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
      select false, 'monthly_request_limit', p_request_id, v_request_limit, v_token_limit,
        0, greatest(0::bigint, v_token_limit - v_usage.input_tokens - v_usage.output_tokens - v_usage.reserved_tokens);
    return;
  end if;

  if v_usage.input_tokens + v_usage.output_tokens + v_usage.reserved_tokens + v_estimate > v_token_limit then
    return query
      select false, 'monthly_token_limit', p_request_id, v_request_limit, v_token_limit,
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

  update public.ai_usage_monthly usage
  set
    request_count = usage.request_count + 1,
    reserved_tokens = usage.reserved_tokens + v_estimate,
    active_request_count = usage.active_request_count + 1,
    updated_at = now()
  where usage.user_id = p_user_id
    and usage.usage_month = v_month
  returning * into v_usage;

  insert into public.ai_request_log (
    request_id,
    user_id,
    client_turn_id,
    usage_period,
    model,
    status,
    reserved_tokens
  )
  values (
    p_request_id,
    p_user_id,
    p_client_turn_id,
    v_month,
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

grant execute on function public.reserve_ai_request(uuid, uuid, uuid, text, bigint)
  to service_role;

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

  update public.ai_usage_monthly usage
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
    and usage.usage_month = v_log.usage_period;

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
