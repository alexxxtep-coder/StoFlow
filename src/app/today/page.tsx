import { redirect } from "next/navigation";
import { requireMembership } from "@/lib/auth/context";
import { createLead } from "./actions";
import { AppShell, QueryError } from "@/components/app-shell";
import { formatInTimeZone } from "@/domain/timezone.mjs";

export default async function TodayPage() {
  const ctx = await requireMembership();
  if (!ctx.ok) redirect("/login");
  const [{ data: leads, error: leadError }, { count: openLeadCount, error: openLeadError }, { count: newLeadCount, error: newLeadError }, { data: orders, error: orderError }, { count: openOrders, error: openOrdersError }, { data: tasks, error: taskError }, { count: openParts, error: partsError }] = await Promise.all([
    ctx.supabase.from("leads").select("id,description,status,created_at,customers(name,normalized_phone)").eq("tenant_id", ctx.tenantId).order("created_at", { ascending: false }).limit(8),
    ctx.supabase.from("leads").select("id", { count: "exact", head: true }).eq("tenant_id", ctx.tenantId).not("status", "in", "(converted,lost)"),
    ctx.supabase.from("leads").select("id", { count: "exact", head: true }).eq("tenant_id", ctx.tenantId).eq("status", "new"),
    ctx.supabase.from("work_orders").select("id,order_number,status,complaint,created_at,customers(name),vehicles(make,model,plate)").eq("tenant_id", ctx.tenantId).not("status", "in", "(completed,cancelled)").order("created_at", { ascending: false }).limit(8),
    ctx.supabase.from("work_orders").select("id", { count: "exact", head: true }).eq("tenant_id", ctx.tenantId).not("status", "in", "(completed,cancelled)"),
    ctx.supabase.from("tasks").select("id,title,status,due_at,priority").eq("tenant_id", ctx.tenantId).eq("assignee_user_id", ctx.user.id).not("status", "in", "(done,cancelled)").order("due_at", { ascending: true }).limit(5),
    ctx.supabase.from("part_requests").select("id", { count: "exact", head: true }).eq("tenant_id", ctx.tenantId).not("status", "in", "(received,cancelled)")
  ]);
  const canReceive = ["owner", "admin", "service_manager", "service_advisor"].includes(String(ctx.role));
  const customerPhone = (value: unknown) => typeof value === "string" ? value : "";
  return <AppShell active="today" tenantName={ctx.tenant.name} role={ctx.role} currency={ctx.tenant.currency} timezone={ctx.tenant.timezone}>
    <div className="page-heading"><div><div className="eyebrow">ОПЕРАЦИОННЫЙ ПУЛЬС · {formatInTimeZone(new Date(), ctx.tenant.timezone, { weekday: "long", day: "numeric", month: "long" })}</div><h1>Сегодня</h1><p className="subtitle">Контроль потока работ, обращений и задач автосервиса.</p></div><div className="heading-actions"><a className="btn outline" href="/schedule">Открыть календарь</a><a className="btn" href="/work">Перейти к работе ↗</a></div></div>
    <div className="grid grid-4">
      <div className="panel metric-card"><span className="metric-icon">✉</span><div className="metric-label">НОВЫЕ ОБРАЩЕНИЯ</div><div className="metric-value">{newLeadCount ?? "—"}</div><div className="metric-foot">Ожидают обработки</div></div>
      <div className="panel metric-card teal"><span className="metric-icon">◉</span><div className="metric-label">АКТИВНЫЕ ЗАКАЗЫ</div><div className="metric-value">{openOrders ?? "—"}</div><div className="metric-foot">Не завершены и не отменены</div></div>
      <div className="panel metric-card amber"><span className="metric-icon">↗</span><div className="metric-label">ОТКРЫТЫЕ ОБРАЩЕНИЯ</div><div className="metric-value">{openLeadCount ?? "—"}</div><div className="metric-foot">Входящий поток клиентов</div></div>
      <div className="panel metric-card purple"><span className="metric-icon">⚙</span><div className="metric-label">ЗАЯВКИ НА ЗАПЧАСТИ</div><div className="metric-value">{openParts ?? "—"}</div><div className="metric-foot">В подборе или ожидании</div></div>
    </div>
    <div className="grid grid-2 section-gap">
      {canReceive ? <section className="panel" id="new-lead"><div className="panel-head"><div><div className="eyebrow">БЫСТРОЕ ДЕЙСТВИЕ</div><h2 className="panel-title" style={{marginTop:5}}>Новое обращение</h2></div><span className="tag blue">CRM</span></div><p className="subtitle">Клиент, автомобиль и обращение сохраняются одной атомарной операцией.</p><form action={createLead}>
        <label className="field">Имя клиента *<input name="customerName" required minLength={2} maxLength={120} placeholder="Имя и фамилия"/></label>
        <label className="field">Телефон *<input name="phone" required minLength={5} maxLength={40} placeholder="+375 29 123-45-67" inputMode="tel"/></label>
        <div className="form-grid"><label className="field">Марка<input name="vehicleMake" maxLength={60} placeholder="Skoda"/></label><label className="field">Модель<input name="vehicleModel" maxLength={80} placeholder="Octavia"/></label><label className="field">Госномер<input name="plate" maxLength={20}/></label><label className="field">VIN<input name="vin" maxLength={32}/></label></div>
        <label className="field">Источник<select name="source" defaultValue="phone"><option value="phone">Телефон</option><option value="messenger">Мессенджер</option><option value="website">Сайт</option><option value="walk_in">Лично</option><option value="other">Другое</option></select></label>
        <label className="field">Причина обращения *<textarea name="description" required minLength={3} maxLength={2000} placeholder="Опишите жалобу клиента или необходимую услугу"/></label>
        <button className="btn">Сохранить обращение</button>
      </form></section> : <section className="panel"><div className="eyebrow">МОИ ЗАДАЧИ</div><h2 className="panel-title" style={{marginTop:6}}>Личный список действий</h2><QueryError title="Задачи" error={taskError}/>{tasks?.length ? tasks.map((task:any)=><div className="list-row" key={task.id}><div className="list-row-main"><b>{task.title}</b><div className="cell-sub">{task.status} · {task.due_at ? formatInTimeZone(task.due_at, ctx.tenant.timezone, { dateStyle: "short", timeStyle: "short" }) : "Без срока"}</div></div><span className={`tag ${task.priority === "urgent" ? "red" : "blue"}`}>{task.priority}</span></div>) : <div className="empty-state">Активных задач нет.</div>}</section>}
      <section className="panel"><div className="panel-head"><div><div className="eyebrow">ПОСЛЕДНИЕ СОБЫТИЯ</div><h2 className="panel-title" style={{marginTop:5}}>Активные заказ-наряды</h2></div><a className="btn outline small" href="/work">Все заказы</a></div><QueryError title="Заказ-наряды" error={orderError}/>{orders?.length ? orders.map((o:any)=><div className="list-row" key={o.id}><div className="list-row-main"><a href={`/work/${o.id}`} className="cell-title">Заказ №{o.order_number}</a><div className="cell-sub">{o.customers?.name ?? "Клиент"} · {[o.vehicles?.make,o.vehicles?.model,o.vehicles?.plate].filter(Boolean).join(" ") || "Автомобиль не указан"}</div><div className="cell-sub">{o.complaint || "Жалоба не указана"}</div></div><span className="tag blue">{statusLabel(o.status)}</span></div>) : <div className="empty-state">Активных заказов пока нет.</div>}
        <div className="panel-head section-gap"><div><div className="eyebrow">ВХОДЯЩИЙ ПОТОК</div><h2 className="panel-title" style={{marginTop:5}}>Последние обращения</h2></div><span className="tag">{leads?.length ?? 0}</span></div><QueryError title="Обращения" error={leadError}/>{leads?.length ? leads.slice(0,5).map((lead:any)=><div className="list-row" key={lead.id}><div className="list-row-main"><b>{lead.customers?.name ?? "Клиент"}</b><div className="cell-sub">{customerPhone(lead.customers?.normalized_phone)} · {lead.description}</div></div><span className="tag amber">{statusLabel(lead.status)}</span></div>) : <div className="empty-state">Обращений пока нет.</div>}
      </section>
    </div>
    <QueryError title="Личные задачи" error={taskError}/><QueryError title="Счётчик обращений" error={openLeadError || newLeadError}/><QueryError title="Счётчик заказов" error={openOrdersError}/><QueryError title="Счётчик снабжения" error={partsError}/>
  </AppShell>;
}

function statusLabel(status: string) {
  const labels:Record<string,string>={new:"Новый",contacted:"Связались",booked:"Записан",converted:"Создан заказ",lost:"Потерян",unreachable:"Нет связи",accepted:"Принят",diagnostics:"Диагностика",awaiting_approval:"Согласование",awaiting_parts:"Ожидает детали",in_progress:"В работе",quality_check:"Контроль качества",ready:"Готов",completed:"Завершён",cancelled:"Отменён"};
  return labels[status] ?? status;
}
