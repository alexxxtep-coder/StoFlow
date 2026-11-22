import { redirect } from "next/navigation";
import { requireMembership } from "@/lib/auth/context";
import { AppShell, QueryError } from "@/components/app-shell";
import { formatInTimeZone } from "@/domain/timezone.mjs";

const stages = [
  { key: "new", label: "Новые", reference: 12 },
  { key: "planned", label: "Запланированы", reference: 10 },
  { key: "in_progress", label: "В работе", reference: 6 },
  { key: "waiting", label: "Ожидание", reference: 8 },
  { key: "blocked", label: "Заблокированы", reference: 4 },
] as const;

export default async function FlowPage() {
  const ctx = await requireMembership();
  if (!ctx.ok) redirect("/login");

  const { data: tasks, error } = await ctx.supabase
    .from("tasks")
    .select("id,title,status,priority,due_at,updated_at,work_order_id")
    .eq("tenant_id", ctx.tenantId)
    .not("status", "in", "(done,cancelled)")
    .order("updated_at", { ascending: true })
    .limit(500);

  const rows = tasks ?? [];
  const counts = Object.fromEntries(stages.map(stage => [stage.key, rows.filter(task => task.status === stage.key).length]));
  const overdue = rows.filter(task => task.due_at && new Date(task.due_at).getTime() < Date.now());
  const blocked = rows.filter(task => task.status === "blocked");
  const stale = rows.filter(task => task.status !== "done" && Date.now() - new Date(task.updated_at).getTime() > 24 * 60 * 60 * 1000);

  return <AppShell active="flow" tenantName={ctx.tenant.name} role={ctx.role} currency={ctx.tenant.currency} timezone={ctx.tenant.timezone}>
    <div className="page-heading"><div><div className="eyebrow">УПРАВЛЕНИЕ · WIP</div><h1>Поток и WIP</h1><p className="subtitle">Загрузка незавершённой работы, узкие места и задачи, требующие внимания.</p></div></div>
    <QueryError title="Загрузка задач" error={error}/>
    <div className="notice">Сейчас отображается фактическая загрузка из Supabase. Контрольные значения ниже взяты из эталона 5.7 и служат ориентирами: они пока не сохраняются в настройках организации и не блокируют переходы между статусами.</div>
    <div className="grid grid-3 section-gap">
      <div className="panel metric-card"><div className="metric-label">АКТИВНАЯ WIP-НАГРУЗКА</div><div className="metric-value">{rows.length}</div><div className="metric-foot">Задачи, не закрытые сотрудниками</div></div>
      <div className="panel metric-card amber"><div className="metric-label">ПРОСРОЧЕНО</div><div className="metric-value">{overdue.length}</div><div className="metric-foot">Срок задачи уже наступил</div></div>
      <div className="panel metric-card purple"><div className="metric-label">ЗАБЛОКИРОВАНО / ЗАСТОЯЛОСЬ</div><div className="metric-value">{blocked.length + stale.filter(task => task.status !== "blocked").length}</div><div className="metric-foot">Блокировка или отсутствие обновлений более 24 часов</div></div>
    </div>
    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">ЗАГРУЗКА ПО ЭТАПАМ</div><h2 className="panel-title">Незавершённая работа</h2></div><span className="tag">{rows.length} задач</span></div>
      {stages.map(stage => {
        const count = counts[stage.key] ?? 0;
        const percent = Math.min(100, Math.round(count / stage.reference * 100));
        const over = count > stage.reference;
        return <div className="wip-stage" key={stage.key}>
          <div className="wip-stage-head"><b>{stage.label}</b><span className={over ? "amount-negative" : ""}>{count} / {stage.reference} <small>ориентир</small></span></div>
          <div className="wip-track"><span className={over ? "over" : ""} style={{ width: percent + "%" }}/></div>
        </div>;
      })}
    </section>
    <section className="panel section-gap">
      <div className="panel-head"><div><div className="eyebrow">ТОЧКИ ВНИМАНИЯ</div><h2 className="panel-title">Застоявшиеся и заблокированные задачи</h2></div><a className="btn outline small" href="/tasks">Все задачи ↗</a></div>
      {blocked.length || stale.length || overdue.length ? <div className="table-wrap"><table><thead><tr><th>Задача</th><th>Состояние</th><th>Обновлена</th><th>Срок</th></tr></thead><tbody>{rows.filter(task => task.status === "blocked" || overdue.includes(task) || stale.includes(task)).slice(0, 30).map(task => <tr key={task.id}><td className="cell-title">{task.title}</td><td><span className={`tag ${task.status === "blocked" ? "red" : overdue.includes(task) ? "amber" : ""}`}>{task.status === "blocked" ? "Заблокирована" : overdue.includes(task) ? "Просрочена" : "Без обновлений > 24 ч"}</span></td><td>{formatInTimeZone(task.updated_at,ctx.tenant.timezone,{dateStyle:"short",timeStyle:"short"})}</td><td>{task.due_at ? formatInTimeZone(task.due_at,ctx.tenant.timezone,{dateStyle:"short",timeStyle:"short"}) : "—"}</td></tr>)}</tbody></table></div> : <div className="empty-state">Нет просроченных, заблокированных или застоявшихся задач.</div>}
    </section>
  </AppShell>;
}
