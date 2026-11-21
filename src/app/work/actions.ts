"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/context";
import { assertOrderTransition } from "@/domain/order.mjs";
import { hasDecimalPrecision } from "@/domain/precision.mjs";

const OrderId = z.string().uuid();
export async function changeOrderStatus(formData: FormData) {
  const id = String(formData.get("orderId") ?? "");
  const status = String(formData.get("status") ?? "");
  if (!OrderId.safeParse(id).success) throw new Error("Некорректный заказ.");
  const allowed = ["accepted","diagnostics","awaiting_approval","awaiting_parts","in_progress","quality_check","ready","completed","cancelled"];
  if (!allowed.includes(status)) throw new Error("Недопустимый статус заказа.");
  const ctx = await requireMembership(); if (!ctx.ok) throw new Error("Нет доступа к рабочему пространству.");
  if (!["owner","admin","service_manager","service_advisor"].includes(String(ctx.role))) throw new Error("Недостаточно прав для изменения статуса.");
  const { data: current, error: readError } = await ctx.supabase.from("work_orders").select("status").eq("id", id).eq("tenant_id", ctx.tenantId).single();
  if (readError || !current) throw new Error("Заказ не найден в этом рабочем пространстве.");
  try { assertOrderTransition(String(current.status), status); }
  catch { throw new Error(`Нельзя изменить статус «${current.status}» на «${status}». Обновите страницу и проверьте текущий этап.`); }
  const update:Record<string,unknown>={status};
  if (status === "completed") update.completed_at = new Date().toISOString();
  if (status !== "completed") update.completed_at = null;
  const { error } = await ctx.supabase.from("work_orders").update(update).eq("id",id).eq("tenant_id",ctx.tenantId);
  if (error) throw new Error(error.message);
  revalidatePath("/work"); revalidatePath(`/work/${id}`); revalidatePath("/today"); revalidatePath("/archive"); revalidatePath("/money"); revalidatePath("/analytics");
}
export async function addOrderLine(formData: FormData) {
  const parsed = z.object({orderId:z.string().uuid(),type:z.enum(["labor","part","other"]),description:z.string().trim().min(2).max(240),quantity:z.coerce.number().positive().max(10000),price:z.coerce.number().min(0).max(100000000),cost:z.coerce.number().min(0).max(100000000)}).safeParse({orderId:formData.get("orderId"),type:formData.get("type"),description:formData.get("description"),quantity:formData.get("quantity"),price:formData.get("price")||0,cost:formData.get("cost")||0});
  if(!parsed.success) throw new Error("Проверьте строку заказ-наряда.");
  if(!hasDecimalPrecision(parsed.data.quantity,3)||!hasDecimalPrecision(parsed.data.price,2)||!hasDecimalPrecision(parsed.data.cost,2)) throw new Error("Количество допускает до 3 знаков, цены и себестоимость — до 2.");
  const ctx=await requireMembership(); if(!ctx.ok) throw new Error("Нет доступа.");
  if(!["owner","admin","service_manager","service_advisor"].includes(String(ctx.role))) throw new Error("Недостаточно прав для редактирования заказа.");
  const {data:order,error:oe}=await ctx.supabase.from("work_orders").select("id,status").eq("id",parsed.data.orderId).eq("tenant_id",ctx.tenantId).single();
  if(oe||!order) throw new Error("Заказ не найден.");
  if(["completed","cancelled"].includes(String(order.status))) throw new Error("Нельзя добавлять строки в завершённый или отменённый заказ.");
  const {error}=await ctx.supabase.rpc("add_work_order_line_with_financials",{p_tenant_id:ctx.tenantId,p_work_order_id:order.id,p_line_type:parsed.data.type,p_description:parsed.data.description,p_quantity:parsed.data.quantity,p_customer_unit_price:parsed.data.price,p_direct_unit_cost:parsed.data.cost});
  if(error) throw new Error(error.message);
  revalidatePath(`/work/${order.id}`); revalidatePath("/work");
}
export async function addWorkTask(formData: FormData) {
  const parsed=z.object({orderId:z.string().uuid(),title:z.string().trim().min(2).max(180),priority:z.enum(["low","normal","high","urgent"])}).safeParse({orderId:formData.get("orderId"),title:formData.get("title"),priority:formData.get("priority")});
  if(!parsed.success) throw new Error("Проверьте задачу.");
  const ctx=await requireMembership(); if(!ctx.ok) throw new Error("Нет доступа.");
  if(!["owner","admin","service_manager","service_advisor"].includes(String(ctx.role))) throw new Error("Недостаточно прав.");
  const {data:order,error:orderError}=await ctx.supabase.from("work_orders").select("id,status").eq("id",parsed.data.orderId).eq("tenant_id",ctx.tenantId).single();
  if(orderError||!order) throw new Error("Заказ не найден.");
  if(["completed","cancelled"].includes(String(order.status))) throw new Error("Нельзя добавлять задачи в завершённый или отменённый заказ.");
  const {error}=await ctx.supabase.from("tasks").insert({tenant_id:ctx.tenantId,work_order_id:parsed.data.orderId,title:parsed.data.title,priority:parsed.data.priority,assignee_user_id:null});
  if(error) throw new Error(error.message); revalidatePath(`/work/${parsed.data.orderId}`); revalidatePath("/work");
}
