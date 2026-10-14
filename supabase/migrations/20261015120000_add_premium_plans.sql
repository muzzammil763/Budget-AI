-- Budget AI Premium (Android). Each user resolves to a plan tier, and the
-- tier decides monthly AI messages, tokens, Fast replies, Deep analysis, and
-- the model. Subscriptions are written only by the revenuecat-webhook Edge
-- Function; clients can read their own row.
--
-- A "message" is one user turn: every request made while answering it
-- (tool rounds, automatic continuations) shares the client's user_turn_id
-- and counts once toward the monthly message limit.

-- 1. Plan limits, editable from the dashboard without an app update.
create table public.plan_limits (
  tier text primary key
    check (tier in ('free', 'lite', 'plus', 'pro', 'legacy')),
  monthly_message_limit integer not null check (monthly_message_limit >= 0),
  monthly_token_limit bigint not null check (monthly_token_limit >= 0),
  monthly_fast_limit integer not null default 0 check (monthly_fast_limit >= 0),
  monthly_deep_limit integer not null default 0 check (monthly_deep_limit >= 0),
  -- Null keeps the model the client asked for (legacy iOS behavior).
  model text,
  deep_model text,
  max_requests_per_message integer not null default 30
    check (max_requests_per_message between 1 and 50),
  updated_at timestamptz not null default now()
);

insert into public.plan_limits (
  tier, monthly_message_limit, monthly_token_limit, monthly_fast_limit,
  monthly_deep_limit, model, deep_model, max_requests_per_message
) values
  ('free', 1, 60000, 0, 0, 'gpt-5.6-luna', null, 30),
  ('lite', 150, 750000, 0, 0, 'gpt-5.6-luna', null, 30),
  ('plus', 200, 1000000, 20, 0, 'gpt-5.6-terra', null, 30),
  ('pro', 250, 1250000, 30, 50, 'gpt-5.6-terra', 'gpt-5.6-sol', 30),
  -- iOS has no paywall yet and keeps the previous default limits.
  ('legacy', 1000, 5000000, 100, 0, null, null, 30);

alter table public.plan_limits enable row level security;
create policy "Anyone signed in can read plan limits"
  on public.plan_limits for select to authenticated using (true);
revoke all on table public.plan_limits from public, anon, authenticated;
grant select on table public.plan_limits to authenticated;
grant all on table public.plan_limits to service_role;

-- 2. Subscriptions mirrored from RevenueCat.
create table public.user_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tier text not null check (tier in ('lite', 'plus', 'pro')),
  status text not null
    check (status in ('active', 'grace', 'cancelled', 'billing_issue', 'expired')),
  product_id text,
  period text check (period is null or period in ('monthly', 'yearly')),
  -- Null means it never expires (complimentary access).
  expires_at timestamptz,
  will_renew boolean not null default true,
  store text,
  environment text,
  last_event text,
  updated_at timestamptz not null default now()
);

alter table public.user_subscriptions enable row level security;
create policy "Users can read their subscription"
  on public.user_subscriptions for select to authenticated
  using ((select auth.uid()) = user_id);
revoke all on table public.user_subscriptions from public, anon, authenticated;
grant select on table public.user_subscriptions to authenticated;
grant all on table public.user_subscriptions to service_role;

-- 3. Message-level usage counters.
alter table public.ai_usage
  add column message_count integer not null default 0 check (message_count >= 0),
  add column deep_message_count integer not null default 0
    check (deep_message_count >= 0);

alter table public.ai_requests
  add column user_turn_id uuid,
  add column plan_tier text;

create index ai_requests_user_turn_idx
  on public.ai_requests (user_id, user_turn_id)
  where user_turn_id is not null;

-- 4. Admin overrides only replace plan limits when explicitly set.
alter table public.user_ai_limits
  add column quota_override boolean not null default false;

update public.user_ai_limits
set quota_override = true
where (monthly_request_limit, monthly_token_limit, monthly_fast_request_limit)
  is distinct from (1000, 5000000, 100);

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
  v_sets_quota boolean := p_monthly_request_limit is not null
    or p_monthly_token_limit is not null
    or p_monthly_fast_request_limit is not null;
begin
  if v_actor is null or v_actor_role not in ('admin', 'superadmin') then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;

  select coalesce(nullif(role, ''), 'member') into v_target_role
  from public.user_roles where user_id = p_user_id;
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
    insert into public.user_roles (user_id, role, updated_at)
    values (p_user_id, p_role, now())
    on conflict (user_id) do update
    set role = excluded.role, updated_at = excluded.updated_at;
  end if;

  if p_enabled is not null or v_sets_quota then
    if (p_monthly_request_limit is not null
        and p_monthly_request_limit not between 1 and 10000)
       or (p_monthly_token_limit is not null
        and p_monthly_token_limit not between 1000 and 100000000)
       or (p_monthly_fast_request_limit is not null
        and p_monthly_fast_request_limit not between 0 and 10000) then
      raise exception 'invalid_limit' using errcode = '22023';
    end if;
    insert into public.user_ai_limits (
      user_id, enabled, monthly_request_limit, monthly_token_limit,
      monthly_fast_request_limit, quota_override
    ) values (
      p_user_id, coalesce(p_enabled, true),
      coalesce(p_monthly_request_limit, 1000),
      coalesce(p_monthly_token_limit, 5000000),
      coalesce(p_monthly_fast_request_limit, 100),
      v_sets_quota
    )
    on conflict (user_id) do update set
      enabled = coalesce(p_enabled, public.user_ai_limits.enabled),
      monthly_request_limit = coalesce(
        p_monthly_request_limit, public.user_ai_limits.monthly_request_limit),
      monthly_token_limit = coalesce(
        p_monthly_token_limit, public.user_ai_limits.monthly_token_limit),
      monthly_fast_request_limit = coalesce(
        p_monthly_fast_request_limit,
        public.user_ai_limits.monthly_fast_request_limit),
      quota_override = public.user_ai_limits.quota_override or v_sets_quota,
      updated_at = now();
  end if;
  return true;
end;
$$;

-- 5. Which plan a user is on right now.
create or replace function public.resolve_ai_plan(p_user_id uuid, p_platform text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (
      select 1 from public.user_roles r
      where r.user_id = p_user_id and r.role in ('admin', 'superadmin')
    ) then 'pro'
    when s.tier is not null then s.tier
    when p_platform = 'ios' then 'legacy'
    else 'free'
  end
  from (select 1) seed
  left join public.user_subscriptions s
    on s.user_id = p_user_id
   and s.status in ('active', 'grace', 'cancelled', 'billing_issue')
   and (s.expires_at is null or s.expires_at > now());
$$;

revoke all on function public.resolve_ai_plan(uuid, text) from public, anon, authenticated;
grant execute on function public.resolve_ai_plan(uuid, text) to service_role;

-- 6. Reserve one AI request against the user's plan.
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

  v_remaining_tokens := greatest(0::bigint,
    v_token_limit - v_usage.input_tokens - v_usage.output_tokens - v_usage.reserved_tokens);
  v_limit_code := case when v_tier = 'free' then 'premium_required'
                       else 'plan_limit_reached' end;

  if not v_enabled then
    return query select false, 'account_disabled', v_tier, null::text, 'default'::text,
      v_message_limit, greatest(0, v_message_limit - v_usage.message_count),
      v_remaining_tokens, greatest(0, v_deep_limit - v_usage.deep_message_count);
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

  if v_new_message and v_usage.message_count >= v_message_limit then
    return query select false, v_limit_code, v_tier, null::text, 'default'::text,
      v_message_limit, 0, v_remaining_tokens,
      greatest(0, v_deep_limit - v_usage.deep_message_count);
    return;
  end if;

  if not v_new_message and v_turn_requests >= v_plan.max_requests_per_message then
    return query select false, 'message_round_limit', v_tier, null::text,
      'default'::text, v_message_limit,
      greatest(0, v_message_limit - v_usage.message_count), v_remaining_tokens,
      greatest(0, v_deep_limit - v_usage.deep_message_count);
    return;
  end if;

  if v_usage.input_tokens + v_usage.output_tokens + v_usage.reserved_tokens
     + v_estimate > v_token_limit then
    return query select false, v_limit_code, v_tier, null::text, 'default'::text,
      v_message_limit, greatest(0, v_message_limit - v_usage.message_count),
      v_remaining_tokens, greatest(0, v_deep_limit - v_usage.deep_message_count);
    return;
  end if;

  if v_usage.active_request_count >= v_concurrent then
    return query select false, 'concurrent_request_limit', v_tier, null::text,
      'default'::text, v_message_limit,
      greatest(0, v_message_limit - v_usage.message_count), v_remaining_tokens,
      greatest(0, v_deep_limit - v_usage.deep_message_count);
    return;
  end if;

  -- Model: the plan's model; Deep analysis switches a whole message to the
  -- plan's deep model while the monthly allowance lasts.
  v_model := coalesce(v_plan.model, nullif(trim(p_requested_model), ''));
  if v_plan.deep_model is not null then
    if v_turn_deep then
      v_model := v_plan.deep_model;
    elsif v_new_message and coalesce(p_deep, false)
          and v_usage.deep_message_count < v_deep_limit then
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
        and v_usage.fast_request_count < v_fast_limit then
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
    v_message_limit, greatest(0, v_message_limit - v_usage.message_count),
    greatest(0::bigint, v_token_limit - v_usage.input_tokens
      - v_usage.output_tokens - v_usage.reserved_tokens),
    greatest(0, v_deep_limit - v_usage.deep_message_count);
end;
$$;

revoke all on function public.reserve_ai_message_request(
  uuid, uuid, uuid, uuid, text, text, bigint, text, boolean
) from public, anon, authenticated;
grant execute on function public.reserve_ai_message_request(
  uuid, uuid, uuid, uuid, text, text, bigint, text, boolean
) to service_role;

-- 7. Whether a user may start a new AI message (used before voice
-- transcription, which happens before the chat request).
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
  v_used integer := 0;
begin
  select * into v_plan from public.plan_limits where tier = v_tier;
  select coalesce(l.enabled, true), coalesce(l.quota_override, false),
         l.monthly_request_limit
    into v_enabled, v_override, v_override_messages
  from (select 1) seed
  left join public.user_ai_limits l on l.user_id = p_user_id;
  if not v_enabled then return 'account_disabled'; end if;

  select coalesce(u.message_count, 0) into v_used
  from (select 1) seed
  left join public.ai_usage u
    on u.user_id = p_user_id and u.usage_month = v_month;

  if v_used >= (case when v_override then v_override_messages
                     else v_plan.monthly_message_limit end) then
    return case when v_tier = 'free' then 'premium_required'
                else 'plan_limit_reached' end;
  end if;
  return 'allowed';
end;
$$;

revoke all on function public.can_start_ai_message(uuid, text) from public, anon, authenticated;
grant execute on function public.can_start_ai_message(uuid, text) to service_role;

-- 8. The signed-in user's plan and this month's usage, for the app's
-- paywall, Budget Hub, and usage sheet.
create or replace function public.get_my_ai_plan(p_platform text)
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
  deep_limit integer
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
begin
  if v_user is null then
    return;
  end if;
  v_tier := public.resolve_ai_plan(v_user, p_platform);
  select * into v_plan from public.plan_limits where tier = v_tier;

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
         v_plan.monthly_deep_limit
  from (select 1) seed
  left join public.user_ai_limits l on l.user_id = v_user
  left join public.ai_usage u on u.user_id = v_user and u.usage_month = v_month
  left join public.user_subscriptions s on s.user_id = v_user;
end;
$$;

revoke all on function public.get_my_ai_plan(text) from public, anon;
grant execute on function public.get_my_ai_plan(text) to authenticated;
