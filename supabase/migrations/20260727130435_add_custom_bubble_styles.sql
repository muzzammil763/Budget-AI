alter table public.user_settings
add column if not exists custom_bubble_styles jsonb not null default '[]'::jsonb
  check (jsonb_typeof(custom_bubble_styles) = 'array');
