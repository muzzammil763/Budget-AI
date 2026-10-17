-- Five free AI messages a month, and lower Premium prices balanced by fewer
-- messages so each fully used plan keeps at least its previous profit:
--   Lite $1.99 / $19.99   100 messages (Swift AI)
--   Plus $6.99 / $64.99   150 messages, 15 Fast (Smart AI)
--   Pro  $9.99 / $94.99   160 messages incl. 30 Deep analysis, 20 Fast
-- Token limits keep the ~5K tokens per message budget. Prices live in Google
-- Play; these rows are the server-side limits.

update public.plan_limits as p
set monthly_message_limit = v.messages,
    monthly_token_limit = v.tokens,
    monthly_fast_limit = v.fast,
    monthly_deep_limit = v.deep,
    updated_at = now()
from (values
  ('free', 5, 60000::bigint, 0, 0),
  ('lite', 100, 500000::bigint, 0, 0),
  ('plus', 150, 750000::bigint, 15, 0),
  ('pro', 160, 800000::bigint, 20, 30)
) as v(tier, messages, tokens, fast, deep)
where p.tier = v.tier;
