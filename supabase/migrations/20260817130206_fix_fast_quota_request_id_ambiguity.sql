-- Fast reservations enter the service-tier update branch. Qualify every
-- target column there so PL/pgSQL does not confuse the function's output
-- column `request_id` with ai_request_log.request_id.

create or replace function public.reserve_ai_request(
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
      update public.ai_usage_monthly as monthly_usage
      set fast_request_count = monthly_usage.fast_request_count + 1,
          updated_at = now()
      where monthly_usage.user_id = p_user_id
        and monthly_usage.usage_month =
          date_trunc('month', now() at time zone 'utc')::date;
      update public.ai_request_log as request_log
      set service_tier = 'fast'
      where request_log.request_id = p_request_id;
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
