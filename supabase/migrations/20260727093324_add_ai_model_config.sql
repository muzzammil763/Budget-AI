-- Global, backend-controlled override for which OpenAI model the app uses.
-- Single-row config table: if active_model_id is set (and still a known
-- model client-side), the app uses it; otherwise it falls back to the
-- hardcoded default (gpt-5.4-nano). No app update needed to switch models.
create table public.ai_model_config (
  id smallint primary key default 1 check (id = 1),
  active_model_id text,
  updated_at timestamptz not null default now()
);

insert into public.ai_model_config (id, active_model_id) values (1, null);

alter table public.ai_model_config enable row level security;

create policy "Authenticated users can read the active model config"
  on public.ai_model_config
  for select
  to authenticated
  using (true);

revoke all on table public.ai_model_config from public, anon, authenticated;
grant select on table public.ai_model_config to authenticated;
grant all on table public.ai_model_config to service_role;

-- The in-app model picker (and its per-user sync) is being removed in favor
-- of the backend-driven override above, so this column is now dead weight.
alter table public.user_settings drop column model_id;
