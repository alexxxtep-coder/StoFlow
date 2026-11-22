import Link from "next/link";
import { redirect } from "next/navigation";
import { requireMembership } from "@/lib/auth/context";
import { convertLeadToOrder } from "@/app/today/actions";
import { changeOrderStatus } from "./actions";
import { AppShell, QueryError } from "@/components/app-shell";
import { formatInTimeZone } from "@/domain/timezone.mjs";

const TABS = [
  ["inbox", "Обращения"],
  ["orders", "Заказ-наряды"],
  ["tasks", "Задачи"],
] as const;

const COLUMNS = [
  { status: "new", title: "Новые" },
  { status: "accepted", title: "Приняты" },
  { status: "diagnostics", title: "Диагностика" },
  { status: "awaiting_approval", title: "Согласование" },
  { status: "awaiting_parts", title: "Ждут запчасти" },
  { status: "in_progress", title: "В работе" },
  { status: "quality_check", title: "Контроль качества" },
  { status: "ready", title: "Готовы к выдаче" },
] as const;

const NEXT: Record<string, string[]> = {
  new: ["accepted", "cancelled"],
  accepted: ["diagnostics", "awaiting_approval", "awaiting_parts", "in_progress", "cancelled"],
  diagnostics: ["awaiting_approval", "awaiting_parts", "in_progress", "cancelled"],
  awaiting_approval: ["awaiting_parts", "in_progress", "cancelled"],
  awaiting_parts: ["in_progress", "cancelled"],
  in_progress: ["awaiting_approval", "awaiting_parts", "quality_check", "cancelled"],
  quality_check: ["in_progress", "ready"],
  ready: ["completed", "in_progress"],
};

const LABELS: Record<string, string> = {
  new: "Новый", accepted: "Принят", diagnostics: "Диагностика",
  awaiting_approval: "Согласование", awaiting_parts: "Ожидает детали",
  in_progress: "В работе", quality_check: "Контроль качества",
  ready: "Готов к выдаче", completed: "Выдан", cancelled: "Отменён",
};

export default async function WorkPage({ searchParams }: {
  searchParams?: Promise<{ tab?: string }>;
}) {
  const ctx = await requireMembership();
  if (!ctx.ok) redirect("/login");
  const params = await searchParams;
  const requestedTab = params?.tab ?? "orders";
  const tab = TABS.some(([key]) => key === requestedTab) ? requestedTab : "orders";
  const canManage = ["owner", "admin", "service_manager", "service_advisor"].includes(String(ctx.role));

  const [{ data: orders, error: orderError }, { data: leads, error: leadError }, { data: tasks, error: taskError }] = await Promise.all([
    ctx.supabase.from("work_orders").select("id,order_number,status,complaint,created_at,planned_finish_at,customers(name),vehicles(make,model,plate)").eq("tenant_id",ctx.tenantId).not("status","in","(completed,cancelled)").order("created_at",{ascending:false}).limit(150),
    ctx.supabase.from("leads").select("id,description,status,created_at,customers(name,normalized_phone)").eq("tenant_id",ctx.tenantId).not("status","in","(converted,lost)").order("created_at",{ascending:false}).limit(100),
    ctx.supabase.from("tasks").select("id,title,status,priority,due_at,work_order_id").eq("tenant_id",ctx.tenantId).not("status","in","(done,cancelled)").order("due_at",{ascending:true}).limit(100)
  ]);

  return <AppShell active="work" tenantName={ctx.tenant.name} role={ctx.role} currency={ctx.tenant.currency} timezone={ctx.tenant.timezone}>
    <div className="page-heading">
      <div><div className="eyebrow">ЕДИНЫЙ РАБОЧИЙ ПОТОК</div><h1>Работа</h1><p className="subtitle">Обращения, заказ-наряды и задачи — в одном разделе, как в рабочем процессе STO.Flow 5.7.</p></div>
      <div className="heading-actions">
        {tab === "inbox" ? <Link className="btn" href="/today#new-lead">＋ Новое обращение</Link> : null}
        {tab === "orders" ? <Link className="btn" href="/today#new-lead">＋ Новый заказ через обращение</Link> : null}
        {tab === "tasks" ? <Link className="btn outline" href="/tasks">Открыть WIP-панель</Link> : null}
      </div>
    </div>
    <div className="work-tabs" role="tablist" aria-label="Разделы работы">
      {TABS.map(([key,label]) => <Link key={key} href={key === "orders" ? "/work" : `/work?tab=${key}`} className={tab === key ? "active" : ""} role="tab" aria-selected={tab === key}>{label}<span>{key === "orders" ? orders?.length ?? 0 : key === "inbox" ? leads?.length ?? 0 : tasks?.length ?? 0}</span></Link>)}
    </div>
    <div className="grid grid-3 work-metrics">
      <div className="panel metric-card"><div className="metric-label">АКТИВНЫЕ ЗАКАЗЫ</div><div className="metric-value">{orders?.length ?? "—"}</div><div className="metric-foot">Текущие заказ-наряды</div></div>
      <div className="panel metric-card amber"><div className="metric-label">ОБРАЩЕНИЯ</div><div className="metric-value">{leads?.length ?? "—"}</div><div className="metric-foot">Ожидают следующего шага</div></div>
      <div className="panel metric-card teal"><div className="metric-label">АКТИВНЫЕ ЗАДАЧИ</div><div className="metric-value">{tasks?.length ?? "—"}</div><div className="metric-foot">Не завершены и не отменены</div></div>
    </div>

    {tab === "orders" ? <section className="work-board-wrap section-gap">
      <QueryError title="Заказ-наряды" error={orderError}/>
      <div className="work-board">{COLUMNS.map(column => {
        const rows = (orders ?? []).filter((order:any) => order.status === column.status);
        return <div className="work-column" key={column.status}>
          <div className="work-column-head"><b>{column.title}</b><span>{rows.length}</span></div>
          {rows.length ? rows.map((order:any) => <article className="work-order-card" key={order.id}>
            <div className="work-order-card-top"><Link href={`/work/${order.id}`}>№{order.order_number}</Link><span className="tag blue">{LABELS[order.status] ?? order.status}</span></div>
            <b>{order.customers?.name ?? "Клиент не указан"}</b>
            <div className="cell-sub">{[order.vehicles?.make,order.vehicles?.model].filter(Boolean).join(" ") || "Автомобиль не указан"}{order.vehicles?.plate ? ` · ${order.vehicles.plate}` : ""}</div>
            <p>{order.complaint || "Жалоба не указана"}</p>
            <div className="work-order-card-foot"><small>{order.planned_finish_at ? `Срок: ${formatInTimeZone(order.planned_finish_at,ctx.tenant.timezone,{dateStyle:"short"})}` : "Срок не задан"}</small><Link href={`/work/${order.id}`}>Открыть ↗</Link></div>
            {canManage && (NEXT[order.status]?.length ?? 0) > 0 ? <form action={changeOrderStatus} className="work-status-form"><input type="hidden" name="orderId" value={order.id}/><select name="status" defaultValue={NEXT[order.status][0]} aria-label="Следующий статус">{NEXT[order.status].map(next => <option key={next} value={next}>{LABELS[next] ?? next}</option>)}</select><button className="btn outline small">Перевести</button></form> : null}
          </article>) : <div className="work-column-empty">Нет заказов</div>}
        </div>;
      })}</div>
    </section> : null}

    {tab === "inbox" ? <section className="panel section-gap">
      <div className="panel-head"><div><div className="eyebrow">ВХОДЯЩИЙ ПОТОК</div><h2 className="panel-title">Обращения клиентов</h2></div><span className="tag amber">{leads?.length ?? 0}</span></div>
      <QueryError title="Обращения" error={leadError}/>
      {leads?.length ? leads.map((lead:any)=><div className="list-row" key={lead.id}><div className="list-row-main"><b>{lead.customers?.name ?? "Клиент"}</b><div className="cell-sub">{lead.customers?.normalized_phone ?? "Телефон не указан"} · {LABELS[lead.status] ?? lead.status}</div><div className="cell-sub">{lead.description}</div></div>{canManage ? <form action={convertLeadToOrder}><input type="hidden" name="leadId" value={lead.id}/><button className="btn small">Создать заказ ↗</button></form> : <span className="tag">{LABELS[lead.status] ?? lead.status}</span>}</div>) : <div className="empty-state">Нет необработанных обращений.</div>}
    </section> : null}

    {tab === "tasks" ? <section className="panel section-gap">
      <div className="panel-head"><div><div className="eyebrow">ИСПОЛНЕНИЕ</div><h2 className="panel-title">Задачи команды</h2></div><span className="tag">{tasks?.length ?? 0}</span></div>
      <QueryError title="Задачи" error={taskError}/>
      {tasks?.length ? <div className="table-wrap"><table><thead><tr><th>Задача</th><th>Заказ</th><th>Приоритет</th><th>Статус</th><th>Срок</th></tr></thead><tbody>{tasks.map((task:any)=><tr key={task.id}><td className="cell-title">{task.title}</td><td>{task.work_order_id ? <Link href={`/work/${task.work_order_id}`}>Открыть заказ ↗</Link> : "—"}</td><td><span className={`tag ${task.priority === "urgent" ? "red" : task.priority === "high" ? "amber" : ""}`}>{task.priority}</span></td><td>{task.status}</td><td>{task.due_at ? formatInTimeZone(task.due_at,ctx.tenant.timezone,{dateStyle:"short",timeStyle:"short"}) : "Без срока"}</td></tr>)}</tbody></table></div> : <div className="empty-state">Открытых задач нет.</div>}
    </section> : null}
  </AppShell>;
}
