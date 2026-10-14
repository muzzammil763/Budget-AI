-- In-app reports of AI replies (Google Play AI-generated content policy).
-- Users can only insert their own reports; they cannot read, edit, or delete
-- them. Review reports in the Supabase dashboard with the service role.
create table public.ai_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  reason text not null
    check (reason in ('inaccurate', 'harmful', 'inappropriate', 'other')),
  note text not null default '' check (char_length(note) <= 1000),
  reply_text text not null check (char_length(reply_text) between 1 and 8000),
  model_id text check (model_id is null or char_length(model_id) <= 80),
  app_version text check (app_version is null or char_length(app_version) <= 40),
  status text not null default 'open'
    check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now()
);

create index ai_reports_created_idx on public.ai_reports (created_at desc);

alter table public.ai_reports enable row level security;

create policy "Users can report AI replies"
  on public.ai_reports for insert to authenticated
  with check ((select auth.uid()) = user_id);

revoke all on table public.ai_reports from public, anon, authenticated;
grant insert on table public.ai_reports to authenticated;
grant all on table public.ai_reports to service_role;
