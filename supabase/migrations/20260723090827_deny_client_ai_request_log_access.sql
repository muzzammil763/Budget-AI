create policy "Clients cannot access AI request logs"
  on public.ai_request_log
  for all
  to authenticated
  using (false)
  with check (false);
