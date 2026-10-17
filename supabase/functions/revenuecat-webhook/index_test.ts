import { assertEquals } from "jsr:@std/assert@1";
import { subscriptionFromSubscriber, userIdsFromEvent } from "./index.ts";

const now = Date.parse("2026-10-14T00:00:00Z");
const future = "2026-11-14T00:00:00Z";
const past = "2026-09-14T00:00:00Z";

Deno.test("picks the highest active entitlement", () => {
  const row = subscriptionFromSubscriber({
    entitlements: {
      lite: {
        expires_date: future,
        product_identifier: "budget_ai_lite",
        product_plan_identifier: "monthly",
      },
      plus: {
        expires_date: future,
        product_identifier: "budget_ai_plus",
        product_plan_identifier: "yearly",
      },
    },
    subscriptions: {
      "budget_ai_plus:yearly": { store: "play_store", is_sandbox: true },
    },
  }, now);
  assertEquals(row?.tier, "plus");
  assertEquals(row?.period, "yearly");
  assertEquals(row?.status, "active");
  assertEquals(row?.environment, "sandbox");
  assertEquals(row?.will_renew, true);
});

Deno.test("expired entitlements produce no row", () => {
  assertEquals(
    subscriptionFromSubscriber({
      entitlements: {
        pro: { expires_date: past, product_identifier: "budget_ai_pro" },
      },
    }, now),
    null,
  );
});

Deno.test("cancelled and grace states", () => {
  const cancelled = subscriptionFromSubscriber({
    entitlements: {
      pro: {
        expires_date: future,
        product_identifier: "budget_ai_pro:monthly",
      },
    },
    subscriptions: {
      "budget_ai_pro:monthly": { unsubscribe_detected_at: past },
    },
  }, now);
  assertEquals(cancelled?.status, "cancelled");
  assertEquals(cancelled?.period, "monthly");
  assertEquals(cancelled?.will_renew, false);

  const grace = subscriptionFromSubscriber({
    entitlements: {
      lite: {
        expires_date: past,
        grace_period_expires_date: future,
        product_identifier: "budget_ai_lite",
      },
    },
    subscriptions: {
      budget_ai_lite: {
        billing_issues_detected_at: past,
        grace_period_expires_date: future,
      },
    },
  }, now);
  assertEquals(grace?.status, "grace");
  assertEquals(grace?.expires_at, future);
});

Deno.test("only UUID app user ids are synced", () => {
  const id = "3F2504E0-4F89-41D3-9A0C-0305E82C3301";
  assertEquals(
    userIdsFromEvent({
      app_user_id: "$RCAnonymousID:abc",
      original_app_user_id: id,
      transferred_to: [id.toLowerCase()],
    }),
    [id.toLowerCase()],
  );
});

Deno.test("weekly plans record when the paid week began", () => {
  const started = "2026-10-12T09:30:00Z";
  const row = subscriptionFromSubscriber({
    entitlements: {
      plus: {
        expires_date: "2026-10-19T09:30:00Z",
        product_identifier: "budget_ai_plus",
        product_plan_identifier: "weekly",
      },
    },
    subscriptions: {
      "budget_ai_plus:weekly": { purchase_date: started },
    },
  }, now);
  assertEquals(row?.tier, "plus");
  assertEquals(row?.period, "weekly");
  assertEquals(row?.period_started_at, started);
});
