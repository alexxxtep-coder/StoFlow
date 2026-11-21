"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/context";
import { normalizePhone } from "@/domain/phone.mjs";
export async function createCustomer(formData:FormData){
 const parsed=z.object({name:z.string().trim().min(2).max(120),phone:z.string().trim().min(5).max(40),email:z.string().trim().email().optional().or(z.literal("")),notes:z.string().trim().max(1000).optional()}).safeParse({name:formData.get("name"),phone:formData.get("phone"),email:formData.get("email")||"",notes:formData.get("notes")||""});
 if(!parsed.success) throw new Error("Проверьте имя, телефон и email клиента."); const normalizedPhone=normalizePhone(parsed.data.phone).normalized;
 const ctx=await requireMembership(); if(!ctx.ok) throw new Error("Нет доступа к рабочему пространству."); if(!["owner","admin","service_manager","service_advisor"].includes(String(ctx.role))) throw new Error("Недостаточно прав.");
 const {error}=await ctx.supabase.from("customers").insert({tenant_id:ctx.tenantId,name:parsed.data.name,normalized_phone:normalizedPhone,email:parsed.data.email||null,notes:parsed.data.notes||null,created_by:ctx.user.id}); if(error) throw new Error(error.message); revalidatePath("/clients");
}
export async function createVehicle(formData:FormData){
 const parsed=z.object({customerId:z.string().uuid(),make:z.string().trim().max(60).optional(),model:z.string().trim().max(80).optional(),plate:z.string().trim().max(20).optional(),vin:z.string().trim().max(32).optional(),year:z.coerce.number().int().min(1886).max(2100).optional()}).safeParse({customerId:formData.get("customerId"),make:formData.get("make")||"",model:formData.get("model")||"",plate:formData.get("plate")||"",vin:formData.get("vin")||"",year:formData.get("year")||undefined});
 if(!parsed.success) throw new Error("Проверьте данные автомобиля."); const ctx=await requireMembership(); if(!ctx.ok) throw new Error("Нет доступа."); if(!["owner","admin","service_manager","service_advisor"].includes(String(ctx.role))) throw new Error("Недостаточно прав.");
 const {error:ce}=await ctx.supabase.from("customers").select("id").eq("id",parsed.data.customerId).eq("tenant_id",ctx.tenantId).single(); if(ce) throw new Error("Клиент не найден в этом рабочем пространстве.");
 const {error}=await ctx.supabase.from("vehicles").insert({tenant_id:ctx.tenantId,customer_id:parsed.data.customerId,make:parsed.data.make||null,model:parsed.data.model||null,plate:parsed.data.plate||null,vin:parsed.data.vin||null,model_year:parsed.data.year??null,vehicle_identity_source:"manual",identity_confidence:"unverified"}); if(error) throw new Error(error.message); revalidatePath("/clients");
}
