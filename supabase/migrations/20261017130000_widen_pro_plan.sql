-- Pro sat only ten messages above Plus. Pro becomes $11.99 / $109.99 with
-- 200 messages (incl. 40 Deep analysis) and 20 Fast, so the plans step
-- 100 → 150 → 200 and a fully used Pro still earns more than the original
-- $12.99 plan.

update public.plan_limits
set monthly_message_limit = 200,
    monthly_token_limit = 1000000,
    monthly_fast_limit = 20,
    monthly_deep_limit = 40,
    updated_at = now()
where tier = 'pro';
