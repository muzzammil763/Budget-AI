-- Weekly Premium plans. Lite, Plus, and Pro gain a weekly Google Play base
-- plan. A weekly subscriber's allowance resets with each paid week instead of
-- on the 1st of the month, so one week's price never buys a month of AI:
--   Lite $0.99/wk   25 messages
--   Plus $2.49/wk   40 messages, 4 Fast
--   Pro  $3.99/wk   50 messages incl. 10 Deep analysis, 5 Fast
-- Monthly and yearly subscribers keep their calendar-month limits, and
-- ai_usage keeps counting every request per month for administration.

-- 1. Weekly limits per plan (null: the plan has no weekly option).
alter table public.plan_limits
  add column weekly_message_limit integer check (weekly_message_limit >= 0),
  add column weekly_token_limit bigint check (weekly_token_limit >= 0),
  add column weekly_fast_limit integer check (weekly_fast_limit >= 0),
  add column weekly_deep_limit integer check (weekly_deep_limit >= 0);

update public.plan_limits as p
set weekly_message_limit = v.messages,
    weekly_token_limit = v.tokens,
    weekly_fast_limit = v.fast,
    weekly_deep_limit = v.deep,
    updated_at = now()
from (values
  ('lite', 25, 125000::bigint, 0, 0),
  ('plus', 40, 200000::bigint, 4, 0),
  ('pro', 50, 250000::bigint, 5, 10)
) as v(tier, messages, tokens, fast, deep)
where p.tier = v.tier;

-- 2. Weekly subscriptions and the start of the current paid period.
alter table public.user_subscriptions
  drop constraint if exists user_subscriptions_period_check;
alter table public.user_subscriptions
  add constraint user_subscriptions_period_check
    check (period is null or period in ('weekly', 'monthly', 'yearly')),
  add column period_started_at timestamptz;

-- 3. When the user's current paid week began, or null unless they are on a
-- live weekly subscription for this tier. Without a purchase date from
-- RevenueCat the week is the seven days before it renews.
create or replace function public.ai_weekly_window_start(
  p_user_id uuid,
  p_tier text
)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when s.period_started_at is not null
         and s.period_started_at > now() - interval '8 days'
      then s.period_started_at
    when s.expires_at is not null
      then least(now(), s.expires_at - interval '7 days')
  end
  from public.user_subscriptions s
  join public.plan_limits p on p.tier = s.tier
  where s.user_id = p_user_id
    and s.tier = p_tier
    and s.period = 'weekly'
    and p.weekly_message_limit is not null
    and s.status in ('active', 'grace', 'cancelled', 'billing_issue')
    and (s.expires_at is null or s.expires_at > now());
$$;

revoke all on function public.ai_weekly_window_start(uuid, text)
  from public, anon, authenticated;
grant execute on function public.ai_weekly_window_start(uuid, text)
  to service_role;

-- 4. Messages, tokens (finished plus still reserved), Fast and Deep messages
-- since a point in time, read from the request log.
create or replace function public.ai_window_usage(
  p_user_id uuid,
  p_since timestamptz,
  p_deep_model text
)
returns table (messages integer, tokens bigint, fast integer, deep integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(distinct r.user_turn_id)::integer,
    coalesce(sum(case when r.status = 'started' then r.reserved_tokens
                      else r.input_tokens + r.output_tokens end), 0)::bigint,
    (count(distinct r.user_turn_id) filter (where r.service_tier = 'fast'))::integer,
    (count(distinct r.user_turn_id)
       filter (where p_deep_model is not null and r.model = p_deep_model))::integer
  from public.ai_requests r
  where r.user_id = p_user_id
    and r.started_at >= p_since;
$$;

revoke all on function public.ai_window_usage(uuid, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.ai_window_usage(uuid, timestamptz, text)
  to service_role;

-- 5. Reserve one AI request against the monthly or weekly allowance.
create or replace function public.reserve_ai_message_request(
  p_user_id uuid,
  p_request_id uuid,
  p_client_turn_id uuid,
  p_user_turn_id uuid,
  p_platform text,
  p_requested_model text,
  p_estimated_tokens bigint,
  p_requested_service_tier text,
  p_deep boolean
)
returns table (
  allowed boolean,
  code text,
  plan_tier text,
  model text,
  effective_service_tier text,
  monthly_message_limit integer,
  remaining_messages integer,
  remaining_tokens bigint,
  remaining_deep integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', now() at time zone 'utc')::date;
  v_turn uuid := coalesce(p_user_turn_id, p_client_turn_id);
  v_estimate bigint := greatest(1, least(coalesce(p_estimated_tokens, 1), 100000));
  v_tier text;
  v_plan public.plan_limits%rowtype;
  v_usage public.ai_usage%rowtype;
  v_enabled boolean := true;
  v_override boolean := false;
  v_concurrent integer := 2;
  v_message_limit integer;
  v_token_limit bigint;
  v_fast_limit integer;
  v_deep_limit integer;
  v_override_messages integer;
  v_override_tokens bigint;
  v_override_fast integer;
  v_turn_requests integer := 0;
  v_turn_fast boolean := false;
  v_turn_deep boolean := false;
  v_new_message boolean;
  v_model text;
  v_tier_effective text := 'default';
  v_deep_turn boolean := false;
  v_limit_code text;
  v_stale_count integer := 0;
  v_stale_reserved bigint := 0;
  v_remaining_tokens bigint;
  -- Weekly subscribers count usage in their paid week instead of the month.
  v_window_start timestamptz;
  v_used_messages integer;
  v_used_tokens bigint;
  v_used_fast integer;
  v_used_deep integer;
begin
  if p_user_id is null or p_request_id is null or p_client_turn_id is null then
    return query select false, 'invalid_request', null::text, null::text,
      'default'::text, 0, 0, 0::bigint, 0;
    return;
  end if;

  -- One lock per user so message counting cannot race.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 0)
  );

  if exists (
    select 1 from public.ai_requests r
    where r.user_id = p_user_id and r.client_turn_id = p_client_turn_id
  ) then
    return query select false, 'duplicate_request', null::text, null::text,
      'default'::text, 0, 0, 0::bigint, 0;
    return;
  end if;

  v_tier := public.resolve_ai_plan(p_user_id, p_platform);
  select * into v_plan from public.plan_limits where tier = v_tier;

  select coalesce(l.enabled, true), coalesce(l.quota_override, false),
         coalesce(l.max_concurrent_requests, 2),
         l.monthly_request_limit, l.monthly_token_limit, l.monthly_fast_request_limit
    into v_enabled, v_override, v_concurrent,
         v_override_messages, v_override_tokens, v_override_fast
  from (select 1) seed
  left join public.user_ai_limits l on l.user_id = p_user_id;

  v_message_limit := case when v_override then v_override_messages
                          else v_plan.monthly_message_limit end;
  v_token_limit := case when v_override then v_override_tokens
                        else v_plan.monthly_token_limit end;
  v_fast_limit := case when v_override then v_override_fast
                       else v_plan.monthly_fast_limit end;
  v_deep_limit := v_plan.monthly_deep_limit;

  if not v_override then
    v_window_start := public.ai_weekly_window_start(p_user_id, v_tier);
  end if;
  if v_window_start is not null then
    v_message_limit := v_plan.weekly_message_limit;
    v_token_limit := v_plan.weekly_token_limit;
    v_fast_limit := v_plan.weekly_fast_limit;
    v_deep_limit := v_plan.weekly_deep_limit;
  end if;

  insert into public.ai_usage (user_id, usage_month)
  values (p_user_id, v_month)
  on conflict (user_id, usage_month) do nothing;

  select * into v_usage from public.ai_usage u
  where u.user_id = p_user_id and u.usage_month = v_month
  for update;

  select count(*)::integer, coalesce(sum(r.reserved_tokens), 0)::bigint
    into v_stale_count, v_stale_reserved
  from public.ai_requests r
  where r.user_id = p_user_id and r.usage_period = v_month
    and r.status = 'started' and r.started_at < now() - interval '15 minutes';

  if v_stale_count > 0 then
    update public.ai_requests r
    set status = 'abandoned', completed_at = now(), error_code = 'stale_request'
    where r.user_id = p_user_id and r.usage_period = v_month
      and r.status = 'started' and r.started_at < now() - interval '15 minutes';

    update public.ai_usage u
    set active_request_count = greatest(0, u.active_request_count - v_stale_count),
        reserved_tokens = greatest(0, u.reserved_tokens - v_stale_reserved),
        failed_request_count = u.failed_request_count + v_stale_count,
        updated_at = now()
    where u.user_id = p_user_id and u.usage_month = v_month
    returning * into v_usage;
  end if;

  if v_window_start is not null then
    select w.messages, w.tokens, w.fast, w.deep
      into v_used_messages, v_used_tokens, v_used_fast, v_used_deep
    from public.ai_window_usage(p_user_id, v_window_start, v_plan.deep_model) w;
  else
    v_used_messages := v_usage.message_count;
    v_used_tokens := v_usage.input_tokens + v_usage.output_tokens
      + v_usage.reserved_tokens;
    v_used_fast := v_usage.fast_request_count;
    v_used_deep := v_usage.deep_message_count;
  end if;

  v_remaining_tokens := greatest(0::bigint, v_token_limit - v_used_tokens);
  v_limit_code := case when v_tier = 'free' then 'premium_required'
                       else 'plan_limit_reached' end;

  if not v_enabled then
    return query select false, 'account_disabled', v_tier, null::text, 'default'::text,
      v_message_limit, greatest(0, v_message_limit - v_used_messages),
      v_remaining_tokens, greatest(0, v_deep_limit - v_used_deep);
    return;
  end if;

  select count(*)::integer,
         coalesce(bool_or(r.service_tier = 'fast'), false),
         coalesce(bool_or(r.model = v_plan.deep_model), false)
    into v_turn_requests, v_turn_fast, v_turn_deep
  from public.ai_requests r
  where r.user_id = p_user_id and r.user_turn_id = v_turn
    and r.usage_period = v_month;
  v_new_message := v_turn_requests = 0;

  if v_new_message and v_used_messages >= v_message_limit then
    return query select false, v_limit_code, v_tier, null::text, 'default'::text,
      v_message_limit, 0, v_remaining_tokens,
      greatest(0, v_deep_limit - v_used_deep);
    return;
  end if;

  if not v_new_message and v_turn_requests >= v_plan.max_requests_per_message then
    return query select false, 'message_round_limit', v_tier, null::text,
      'default'::text, v_message_limit,
      greatest(0, v_message_limit - v_used_messages), v_remaining_tokens,
      greatest(0, v_deep_limit - v_used_deep);
    return;
  end if;

  if v_used_tokens + v_estimate > v_token_limit then
    return query select false, v_limit_code, v_tier, null::text, 'default'::text,
      v_message_limit, greatest(0, v_message_limit - v_used_messages),
      v_remaining_tokens, greatest(0, v_deep_limit - v_used_deep);
    return;
  end if;

  if v_usage.active_request_count >= v_concurrent then
    return query select false, 'concurrent_request_limit', v_tier, null::text,
      'default'::text, v_message_limit,
      greatest(0, v_message_limit - v_used_messages), v_remaining_tokens,
      greatest(0, v_deep_limit - v_used_deep);
    return;
  end if;

  -- Model: the plan's model; Deep analysis switches a whole message to the
  -- plan's deep model while the monthly allowance lasts.
  v_model := coalesce(v_plan.model, nullif(trim(p_requested_model), ''));
  if v_plan.deep_model is not null then
    if v_turn_deep then
      v_model := v_plan.deep_model;
    elsif v_new_message and coalesce(p_deep, false)
          and v_used_deep < v_deep_limit then
      v_model := v_plan.deep_model;
      v_deep_turn := true;
    end if;
  end if;
  if v_model is null then
    return query select false, 'invalid_request', v_tier, null::text,
      'default'::text, 0, 0, 0::bigint, 0;
    return;
  end if;

  -- Fast is decided per message and kept for its continuations.
  if v_turn_fast then
    v_tier_effective := 'fast';
  elsif v_new_message and p_requested_service_tier = 'fast'
        and v_used_fast < v_fast_limit then
    v_tier_effective := 'fast';
  end if;

  update public.ai_usage u
  set request_count = u.request_count + 1,
      message_count = u.message_count + case when v_new_message then 1 else 0 end,
      deep_message_count = u.deep_message_count + case when v_deep_turn then 1 else 0 end,
      fast_request_count = u.fast_request_count
        + case when v_new_message and v_tier_effective = 'fast' then 1 else 0 end,
      reserved_tokens = u.reserved_tokens + v_estimate,
      active_request_count = u.active_request_count + 1,
      updated_at = now()
  where u.user_id = p_user_id and u.usage_month = v_month
  returning * into v_usage;

  insert into public.ai_requests (
    request_id, user_id, client_turn_id, user_turn_id, usage_period, model,
    status, reserved_tokens, service_tier, plan_tier
  ) values (
    p_request_id, p_user_id, p_client_turn_id, v_turn, v_month, v_model,
    'started', v_estimate, v_tier_effective, v_tier
  );

  return query select true, 'allowed', v_tier, v_model, v_tier_effective,
    v_message_limit,
    greatest(0, v_message_limit - v_used_messages
      - case when v_new_message then 1 else 0 end),
    greatest(0::bigint, v_token_limit - v_used_tokens - v_estimate),
    greatest(0, v_deep_limit - v_used_deep
      - case when v_deep_turn then 1 else 0 end);
end;
$$;

revoke all on function public.reserve_ai_message_request(
  uuid, uuid, uuid, uuid, text, text, bigint, text, boolean
) from public, anon, authenticated;
grant execute on function public.reserve_ai_message_request(
  uuid, uuid, uuid, uuid, text, text, bigint, text, boolean
) to service_role;


-- 6. Voice transcription check, weekly-aware.
create or replace function public.can_start_ai_message(p_user_id uuid, p_platform text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', now() at time zone 'utc')::date;
  v_tier text := public.resolve_ai_plan(p_user_id, p_platform);
  v_plan public.plan_limits%rowtype;
  v_enabled boolean := true;
  v_override boolean := false;
  v_override_messages integer;
  v_window_start timestamptz;
  v_limit integer;
  v_used integer := 0;
begin
  select * into v_plan from public.plan_limits where tier = v_tier;
  select coalesce(l.enabled, true), coalesce(l.quota_override, false),
         l.monthly_request_limit
    into v_enabled, v_override, v_override_messages
  from (select 1) seed
  left join public.user_ai_limits l on l.user_id = p_user_id;
  if not v_enabled then return 'account_disabled'; end if;

  if not v_override then
    v_window_start := public.ai_weekly_window_start(p_user_id, v_tier);
  end if;

  if v_window_start is not null then
    v_limit := v_plan.weekly_message_limit;
    select w.messages into v_used
    from public.ai_window_usage(p_user_id, v_window_start, v_plan.deep_model) w;
  else
    v_limit := case when v_override then v_override_messages
                    else v_plan.monthly_message_limit end;
    select coalesce(u.message_count, 0) into v_used
    from (select 1) seed
    left join public.ai_usage u
      on u.user_id = p_user_id and u.usage_month = v_month;
  end if;

  if v_used >= v_limit then
    return case when v_tier = 'free' then 'premium_required'
                else 'plan_limit_reached' end;
  end if;
  return 'allowed';
end;
$$;

revoke all on function public.can_start_ai_message(uuid, text) from public, anon, authenticated;
grant execute on function public.can_start_ai_message(uuid, text) to service_role;

-- 7. The app's plan and usage, now with the usage window and when it resets.
drop function if exists public.get_my_ai_plan(text);
create function public.get_my_ai_plan(p_platform text)
returns table (
  plan_tier text,
  enabled boolean,
  status text,
  period text,
  expires_at timestamptz,
  will_renew boolean,
  messages_used integer,
  message_limit integer,
  tokens_used bigint,
  token_limit bigint,
  fast_used integer,
  fast_limit integer,
  deep_used integer,
  deep_limit integer,
  usage_window text,
  resets_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_month date := date_trunc('month', now() at time zone 'utc')::date;
  v_tier text;
  v_plan public.plan_limits%rowtype;
  v_override boolean := false;
  v_window_start timestamptz;
  v_messages integer;
  v_tokens bigint;
  v_fast integer;
  v_deep integer;
begin
  if v_user is null then
    return;
  end if;
  v_tier := public.resolve_ai_plan(v_user, p_platform);
  select * into v_plan from public.plan_limits where tier = v_tier;
  select coalesce(l.quota_override, false) into v_override
  from (select 1) seed
  left join public.user_ai_limits l on l.user_id = v_user;
  if not v_override then
    v_window_start := public.ai_weekly_window_start(v_user, v_tier);
  end if;

  if v_window_start is not null then
    select w.messages, w.tokens, w.fast, w.deep
      into v_messages, v_tokens, v_fast, v_deep
    from public.ai_window_usage(v_user, v_window_start, v_plan.deep_model) w;

    return query
    select v_tier,
           coalesce(l.enabled, true),
           s.status,
           s.period,
           s.expires_at,
           coalesce(s.will_renew, false),
           v_messages,
           v_plan.weekly_message_limit,
           v_tokens,
           v_plan.weekly_token_limit,
           v_fast,
           v_plan.weekly_fast_limit,
           v_deep,
           v_plan.weekly_deep_limit,
           'week'::text,
           v_window_start + interval '7 days'
    from (select 1) seed
    left join public.user_ai_limits l on l.user_id = v_user
    left join public.user_subscriptions s on s.user_id = v_user;
    return;
  end if;

  return query
  select v_tier,
         coalesce(l.enabled, true),
         s.status,
         s.period,
         s.expires_at,
         coalesce(s.will_renew, false),
         coalesce(u.message_count, 0),
         case when coalesce(l.quota_override, false)
              then l.monthly_request_limit else v_plan.monthly_message_limit end,
         (coalesce(u.input_tokens, 0) + coalesce(u.output_tokens, 0))::bigint,
         case when coalesce(l.quota_override, false)
              then l.monthly_token_limit else v_plan.monthly_token_limit end,
         coalesce(u.fast_request_count, 0),
         case when coalesce(l.quota_override, false)
              then l.monthly_fast_request_limit else v_plan.monthly_fast_limit end,
         coalesce(u.deep_message_count, 0),
         v_plan.monthly_deep_limit,
         'month'::text,
         ((v_month + interval '1 month')::timestamp at time zone 'utc')
  from (select 1) seed
  left join public.user_ai_limits l on l.user_id = v_user
  left join public.ai_usage u on u.user_id = v_user and u.usage_month = v_month
  left join public.user_subscriptions s on s.user_id = v_user;
end;
$$;

revoke all on function public.get_my_ai_plan(text) from public, anon;
grant execute on function public.get_my_ai_plan(text) to authenticated;
