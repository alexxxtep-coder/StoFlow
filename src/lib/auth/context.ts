import { createClient } from "@/lib/supabase/server";

export type AppRole =
  | "owner" | "admin" | "service_manager" | "service_advisor"
  | "mechanic" | "parts_manager" | "finance";

type TenantContext = { id: string; name: string; currency: string; timezone: string };
type MembershipContext = {
  ok: true;
  supabase: Awaited<ReturnType<typeof createClient>>;
  user: { id: string; email?: string };
  tenantId: string;
  role: AppRole;
  tenant: TenantContext;
};
type MembershipFailure = { ok: false; reason: "unauthenticated" | "no_membership" };

export async function requireMembership(): Promise<MembershipContext | MembershipFailure> {
  const supabase = await createClient();
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) return { ok: false, reason: "unauthenticated" };

  const { data: memberships, error } = await supabase
    .from("memberships")
    .select("tenant_id, role, tenants(id, name, currency, timezone)")
    .eq("user_id", user.id)
    .eq("is_active", true)
    .order("created_at", { ascending: true })
    .limit(1);

  if (error) throw new Error("Не удалось загрузить рабочее пространство");
  const membership = memberships?.[0];
  if (!membership) return { ok: false, reason: "no_membership" };

  // PostgREST may represent a relationship as an object or a one-item array,
  // depending on the generated schema relationship metadata.
  const relatedTenant = membership.tenants as TenantContext | TenantContext[] | null;
  const tenant = Array.isArray(relatedTenant) ? relatedTenant[0] : relatedTenant;
  if (!tenant?.id) return { ok: false, reason: "no_membership" };

  return {
    ok: true,
    supabase,
    user: { id: user.id, email: user.email ?? undefined },
    tenantId: membership.tenant_id as string,
    role: membership.role as AppRole,
    tenant: {
      id: tenant.id,
      name: tenant.name,
      currency: tenant.currency,
      timezone: tenant.timezone
    }
  };
}
