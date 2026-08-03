import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return Response.json(body, { status, headers: corsHeaders });
}

type AdminAuthClient = {
  auth: {
    admin: {
      deleteUser: (userId: string) => Promise<{
        error: { message?: string } | null;
      }>;
    };
  };
};

const authenticatedHandler = withSupabase(
  { auth: "user" },
  async (req, ctx) => {
    if (req.method !== "POST") {
      return jsonResponse(405, {
        code: "method_not_allowed",
        message: "Use POST.",
      });
    }

    const userId = ctx.userClaims?.id ?? ctx.jwtClaims?.sub;
    if (!userId) {
      return jsonResponse(401, {
        code: "unauthorized",
        message: "Sign in again to continue.",
      });
    }

    const adminClient = ctx.supabaseAdmin as unknown as AdminAuthClient;
    const { error } = await adminClient.auth.admin.deleteUser(userId);
    if (error) {
      console.error("Account deletion failed", error.message);
      return jsonResponse(500, {
        code: "account_deletion_failed",
        message: "The account could not be deleted.",
      });
    }

    return jsonResponse(200, { deleted: true });
  },
);

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return authenticatedHandler(req);
});
