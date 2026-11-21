import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireMembership } from "@/lib/auth/context";

export default async function Home() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const ctx = await requireMembership();
  if (!ctx.ok && ctx.reason === "no_membership") redirect("/onboarding");
  if (!ctx.ok) redirect("/login");
  redirect("/today");
}
