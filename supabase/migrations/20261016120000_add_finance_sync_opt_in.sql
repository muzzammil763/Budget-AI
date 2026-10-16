-- Finance cloud sync becomes opt-in. New accounts keep their entries on the
-- device until they turn Cloud Sync on in Budget Hub; accounts that already
-- existed keep syncing (they can turn it off, which stops future uploads).
alter table public.users
  add column if not exists finance_sync_enabled boolean not null default false;

-- Everyone who already has a settings row was syncing before this change.
update public.users set finance_sync_enabled = true;

-- Accounts that synced entries without ever writing a settings row.
insert into public.users (user_id, device_id, finance_sync_enabled)
select distinct entries.user_id, gen_random_uuid(), true
from public.finance_entries as entries
where not exists (
  select 1 from public.users as settings
  where settings.user_id = entries.user_id
)
on conflict (user_id) do update set finance_sync_enabled = true;
