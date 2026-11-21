import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createWorkspace } from "./actions";
export default async function OnboardingPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();if(!user)redirect("/login");
  const {data:memberships}=await supabase.from("memberships").select("id").eq("user_id",user.id).eq("is_active",true).limit(1);if(memberships?.length)redirect("/today");
  const params=await searchParams;
  return <main className="auth-page"><section className="auth-card"><div className="auth-brand">STO.Flow<small>WORKSHOP OPERATIONS · 6.0</small></div><h1>Создайте пространство СТО</h1><p className="subtitle">Организация станет изолированным рабочим пространством. Вы получите роль владельца.</p>{params.error?<div className="error">Не удалось создать пространство. Проверьте название и попробуйте ещё раз.</div>:null}<form action={createWorkspace}><label className="field">Название автосервиса<input name="name" required minLength={2} maxLength={120} placeholder="Например, Автосервис Центр"/></label><button className="btn">Создать рабочее пространство</button></form></section></main>;
}
