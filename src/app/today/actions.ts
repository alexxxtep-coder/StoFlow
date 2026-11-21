"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/context";
import { normalizePhone } from "@/domain/phone.mjs";

const LeadSchema = z.object({
  customerName: z.string().trim().min(2).max(120),
  phone: z.string().trim().min(5).max(40),
  vehicleMake: z.string().trim().max(60).optional().default(""),
  vehicleModel: z.string().trim().max(80).optional().default(""),
  plate: z.string().trim().max(20).optional().default(""),
  vin: z.string().trim().max(32).optional().default(""),
  description: z.string().trim().min(3).max(2000),
  source: z.enum(["phone", "messenger", "website", "walk_in", "other"])
});

export async function createLead(formData: FormData) {
  const parsed = LeadSchema.safeParse({
    customerName: formData.get("customerName"),
    phone: formData.get("phone"),
    vehicleMake: formData.get("vehicleMake") || "",
    vehicleModel: formData.get("vehicleModel") || "",
    plate: formData.get("plate") || "",
    vin: formData.get("vin") || "",
    description: formData.get("description"),
    source: formData.get("source")
  });
  if (!parsed.success) throw new Error("Проверьте поля обращения.");

  const normalizedPhone = normalizePhone(parsed.data.phone).normalized;
  const ctx = await requireMembership();
  if (!ctx.ok) throw new Error("Нет активного рабочего пространства.");
  if (!["owner","admin","service_manager","service_advisor"].includes(String(ctx.role))) throw new Error("У вашей роли нет права создавать обращения.");

  const { error } = await ctx.supabase.rpc("create_lead_with_context", {
    p_tenant_id: ctx.tenantId,
    p_customer_name: parsed.data.customerName,
    p_phone: normalizedPhone,
    p_vehicle_make: parsed.data.vehicleMake || null,
    p_vehicle_model: parsed.data.vehicleModel || null,
    p_plate: parsed.data.plate || null,
    p_vin: parsed.data.vin || null,
    p_description: parsed.data.description,
    p_source: parsed.data.source
  });
  if (error) throw new Error(error.message);
  revalidatePath("/today");
}

export async function convertLeadToOrder(formData: FormData) {
  const leadId = String(formData.get("leadId") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(leadId)) throw new Error("Некорректное обращение.");
  const ctx = await requireMembership();
  if (!ctx.ok) throw new Error("Нет активного рабочего пространства.");
  const { error } = await ctx.supabase.rpc("create_work_order_from_lead", {
    p_tenant_id: ctx.tenantId,
    p_lead_id: leadId,
    p_complaint: null,
    p_planned_finish_at: null
  });
  if (error) throw new Error(error.message);
  revalidatePath("/today");
  revalidatePath("/work");
}
