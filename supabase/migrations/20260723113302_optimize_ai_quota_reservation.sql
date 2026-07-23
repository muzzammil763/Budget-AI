-- reserve_ai_request checks this exact subset on every AI request to release
-- abandoned reservations. Keep the active subset small and ordered for the
-- stale timestamp predicate.
create index if not exists ai_request_log_active_user_day_started_idx
  on public.ai_request_log (user_id, usage_date, started_at)
  where status = 'started';
