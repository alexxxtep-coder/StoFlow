"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/context";
import { hasDecimalPrecision } from "@/domain/precision.mjs";

const RequestSchema = z.object({
  orderId: z.string().uuid(), description: z.string().trim().min(2).max(240),
  oem: z.string().trim().max(80).optional().default(""), quantity: z.coerce.number().positive().max(1000)
});

export async function createPartRequest(formData: FormData) {
  const parsed = RequestSchema.safeParse({
    orderId: formData.get("orderId"), description: formData.get("description"),
    oem: formData.get("oem") || "", quantity: formData.get("quantity") || 1
  });
  if (!parsed.success) throw new Error("Проверьте данные заявки на деталь.");
  if (!hasDecimalPrecision(parsed.data.quantity,3)) throw new Error("Количество детали допускает не более трёх знаков после запятой.");
  const ctx = await requireMembership();
  if (!ctx.ok) throw new Error("Нет активного рабочего пространства.");
  const { data: order, error: orderError } = await ctx.supabase.from("work_orders")
    .select("id, vehicle_id, status").eq("id", parsed.data.orderId).eq("tenant_id", ctx.tenantId).single();
  if (orderError || !order) throw new Error("Заказ не найден или нет доступа.");
  if (["completed", "cancelled"].includes(String(order.status))) throw new Error("Нельзя создавать заявку на деталь для завершённого или отменённого заказа.");
  const { error } = await ctx.supabase.from("part_requests").insert({
    tenant_id: ctx.tenantId, work_order_id: order.id, vehicle_id: order.vehicle_id,
    description: parsed.data.description, oem_number: parsed.data.oem || null, quantity: parsed.data.quantity
  });
  if (error) throw new Error(error.message);
  revalidatePath("/supply");
}

const OfferSchema = z.object({
  requestId: z.string().uuid(), supplier: z.string().trim().min(2).max(120),
  title: z.string().trim().min(2).max(160), brand: z.string().trim().max(80).optional().default(""),
  sku: z.string().trim().max(80).optional().default(""),
  price: z.string().trim().optional().default(""), availability: z.enum(["unknown","in_stock","limited","backorder","out_of_stock"]),
  fitment: z.enum(["unverified","confirmed","probable","not_fit"])
});

export async function addManualOffer(formData: FormData) {
  const parsed = OfferSchema.safeParse({
    requestId: formData.get("requestId"), supplier: formData.get("supplier"), title: formData.get("title"),
    brand: formData.get("brand") || "", sku: formData.get("sku") || "", price: formData.get("price") || "",
    availability: formData.get("availability"), fitment: formData.get("fitment")
  });
  if (!parsed.success) throw new Error("Проверьте данные предложения.");
  const price = parsed.data.price ? parsed.data.price.replace(",", ".") : null;
  if (price !== null && !/^\d{1,12}(\.\d{1,2})?$/.test(price)) throw new Error("Введите цену в формате 125.50 без отрицательных значений.");
  const ctx = await requireMembership();
  if (!ctx.ok) throw new Error("Нет активного рабочего пространства.");
  const { error } = await ctx.supabase.rpc("add_manual_supplier_offer", {
    p_tenant_id: ctx.tenantId, p_part_request_id: parsed.data.requestId,
    p_supplier_name: parsed.data.supplier, p_title: parsed.data.title,
    p_brand: parsed.data.brand || null, p_sku: parsed.data.sku || null,
    p_purchase_price: price, p_currency: ctx.tenant.currency,
    p_availability: parsed.data.availability, p_eta_at: null, p_fitment_status: parsed.data.fitment
  });
  if (error) throw new Error(error.message);
  revalidatePath("/supply");
}

export async function orderSelectedOffer(formData: FormData) {
  const offerId = String(formData.get("offerId") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(offerId)) throw new Error("Некорректное предложение.");
  const ctx = await requireMembership();
  if (!ctx.ok) throw new Error("Нет активного рабочего пространства.");
  const { error } = await ctx.supabase.rpc("create_purchase_from_offer", {
    p_tenant_id: ctx.tenantId, p_offer_id: offerId
  });
  if (error) throw new Error(error.message);
  revalidatePath("/supply");
}
