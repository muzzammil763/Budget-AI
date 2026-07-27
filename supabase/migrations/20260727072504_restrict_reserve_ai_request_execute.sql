-- DROP FUNCTION + CREATE FUNCTION in the prior migration reset
-- reserve_ai_request's grants to Postgres defaults, which include EXECUTE
-- for PUBLIC. Restrict it back to service_role only, matching the original
-- security posture (this function is security definer and must only be
-- reachable through the openai-responses edge function, not directly by
-- clients).
revoke all on function public.reserve_ai_request(uuid, uuid, uuid, text, bigint)
  from public, anon, authenticated;
