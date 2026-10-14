import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

// RevenueCat calls this endpoint for every purchase, renewal, cancellation,
// billing issue, expiration and transfer. The event only says *that* something
// changed; the current state is read back from RevenueCat's REST API so retried
// or out-of-order events always converge on the latest subscription.

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// Entitlement identifiers configured in RevenueCat, highest tier first.
const tiers = ["pro", "plus", "lite"] as const;
type Tier = typeof tiers[number];

type RevenueCatEntitlement = {
  expires_date?: string | null;
  grace_period_expires_date?: string | null;
  product_identifier?: string | null;
  product_plan_identifier?: string | null;
};

type RevenueCatSubscription = {
  expires_date?: string | null;
  grace_period_expires_date?: string | null;
  billing_issues_detected_at?: string | null;
  unsubscribe_detected_at?: string | null;
  refunded_at?: string | null;
  store?: string | null;
  is_sandbox?: boolean | null;
  product_plan_identifier?: string | null;
};

export type RevenueCatSubscriber = {
  entitlements?: Record<string, RevenueCatEntitlement>;
  subscriptions?: Record<string, RevenueCatSubscription>;
};

export type SubscriptionRow = {
  tier: Tier;
  status: "active" | "grace" | "cancelled" | "billing_issue";
  product_id: string | null;
  period: "monthly" | "yearly" | null;
  expires_at: string | null;
  will_renew: boolean;
  store: string | null;
  environment: string;
};

type AdminClient = {
  from: (table: string) => {
    select: (columns: string) => {
      eq: (column: string, value: string) => {
        maybeSingle: () => Promise<{
          data: Record<string, unknown> | null;
          error: { message?: string } | null;
        }>;
      };
    };
    upsert: (
      row: Record<string, unknown>,
      options: { onConflict: string },
    ) => Promise<{ error: { message?: string; code?: string } | null }>;
    update: (row: Record<string, unknown>) => {
      eq: (
        column: string,
        value: string,
      ) => Promise<{ error: { message?: string } | null }>;
    };
  };
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return Response.json(body, { status });
}

function timingSafeEqual(a: string, b: string) {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let diff = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}

function isAuthorized(req: Request) {
  const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  if (!secret) return false;
  const header = req.headers.get("authorization") ?? "";
  return timingSafeEqual(header, secret) ||
    timingSafeEqual(header, `Bearer ${secret}`);
}

function isLive(date: string | null | undefined, now: number) {
  if (!date) return true;
  const time = Date.parse(date);
  return Number.isFinite(time) && time > now;
}

function periodFrom(...identifiers: (string | null | undefined)[]) {
  for (const identifier of identifiers) {
    const plan = identifier?.split(":").pop()?.toLowerCase() ?? "";
    if (plan.includes("year") || plan.includes("annual")) return "yearly";
    if (plan.includes("month")) return "monthly";
  }
  return null;
}

/** Highest active entitlement as a `user_subscriptions` row, or null. */
export function subscriptionFromSubscriber(
  subscriber: RevenueCatSubscriber,
  now = Date.now(),
): SubscriptionRow | null {
  for (const tier of tiers) {
    const entitlement = subscriber.entitlements?.[tier];
    if (!entitlement) continue;
    const inGrace = isLive(entitlement.grace_period_expires_date, now) &&
      Boolean(entitlement.grace_period_expires_date);
    if (!isLive(entitlement.expires_date, now) && !inGrace) continue;

    const productId = entitlement.product_identifier ?? null;
    const planId = entitlement.product_plan_identifier ?? null;
    const subscriptions = subscriber.subscriptions ?? {};
    const subscription = (planId && productId
      ? subscriptions[`${productId}:${planId}`]
      : undefined) ?? (productId ? subscriptions[productId] : undefined);

    const graceUntil = subscription?.grace_period_expires_date ??
      entitlement.grace_period_expires_date;
    const cancelled = Boolean(
      subscription?.unsubscribe_detected_at || subscription?.refunded_at,
    );
    let status: SubscriptionRow["status"] = "active";
    if (subscription?.billing_issues_detected_at) {
      status = graceUntil && isLive(graceUntil, now)
        ? "grace"
        : "billing_issue";
    } else if (cancelled) {
      status = "cancelled";
    }

    const expiresAt = entitlement.expires_date ?? null;
    return {
      tier,
      status,
      product_id: productId,
      period: periodFrom(
        planId,
        subscription?.product_plan_identifier,
        productId,
      ),
      // During grace the store keeps access past the paid period.
      expires_at: status === "grace" && graceUntil ? graceUntil : expiresAt,
      will_renew: !cancelled,
      store: subscription?.store ?? null,
      environment: subscription?.is_sandbox ? "sandbox" : "production",
    };
  }
  return null;
}

async function fetchSubscriber(
  userId: string,
): Promise<RevenueCatSubscriber | null> {
  const key = Deno.env.get("REVENUECAT_SECRET_KEY") ?? "";
  if (!key) throw new Error("REVENUECAT_SECRET_KEY is not set");
  const response = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
    { headers: { authorization: `Bearer ${key}` } },
  );
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`RevenueCat subscriber lookup failed: ${response.status}`);
  }
  const body = await response.json() as { subscriber?: RevenueCatSubscriber };
  return body.subscriber ?? null;
}

/** Budget AI user ids (Supabase UUIDs) mentioned by a webhook event. */
export function userIdsFromEvent(event: Record<string, unknown>) {
  const candidates: unknown[] = [
    event.app_user_id,
    event.original_app_user_id,
    ...(Array.isArray(event.aliases) ? event.aliases : []),
    ...(Array.isArray(event.transferred_from) ? event.transferred_from : []),
    ...(Array.isArray(event.transferred_to) ? event.transferred_to : []),
  ];
  return [
    ...new Set(
      candidates.filter((id): id is string =>
        typeof id === "string" && uuidPattern.test(id)
      ).map((id) => id.toLowerCase()),
    ),
  ];
}

async function syncUser(
  admin: AdminClient,
  userId: string,
  eventType: string,
) {
  const subscriber = await fetchSubscriber(userId);
  const row = subscriber ? subscriptionFromSubscriber(subscriber) : null;
  const table = admin.from("user_subscriptions");

  if (row) {
    const { error } = await table.upsert({
      user_id: userId,
      ...row,
      last_event: eventType,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
    // 23503: the Budget AI account was deleted; nothing left to update.
    if (error && error.code !== "23503") {
      throw new Error(error.message ?? "upsert failed");
    }
    return;
  }

  // Nothing active in the store. Complimentary access granted by hand
  // (store = 'complimentary') is not RevenueCat's to revoke.
  const { data, error } = await table.select("store").eq("user_id", userId)
    .maybeSingle();
  if (error) throw new Error(error.message ?? "lookup failed");
  if (!data || data.store === "complimentary") return;
  const { error: updateError } = await admin.from("user_subscriptions")
    .update({
      status: "expired",
      will_renew: false,
      last_event: eventType,
      updated_at: new Date().toISOString(),
    }).eq("user_id", userId);
  if (updateError) throw new Error(updateError.message ?? "update failed");
}

const handler = withSupabase({ auth: "none" }, async (req, ctx) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { code: "method_not_allowed" });
  }
  if (!isAuthorized(req)) {
    return jsonResponse(401, { code: "unauthorized" });
  }

  let event: Record<string, unknown>;
  try {
    const body = await req.json() as { event?: Record<string, unknown> };
    event = body.event ?? {};
  } catch {
    return jsonResponse(400, { code: "invalid_json" });
  }

  const eventType = typeof event.type === "string" ? event.type : "UNKNOWN";
  if (eventType === "TEST") return jsonResponse(200, { ok: true });

  const userIds = userIdsFromEvent(event);
  const admin = ctx.supabaseAdmin as unknown as AdminClient;
  try {
    for (const userId of userIds) {
      await syncUser(admin, userId, eventType);
    }
  } catch (error) {
    // A non-2xx response makes RevenueCat retry the event later.
    console.error("RevenueCat sync failed", eventType, String(error));
    return jsonResponse(500, { code: "sync_failed" });
  }
  return jsonResponse(200, { ok: true, users: userIds.length });
});

if (import.meta.main) {
  Deno.serve(handler);
}
