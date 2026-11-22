import { redirect } from "next/navigation";
import { requireMembership } from "@/lib/auth/context";
import { AppShell, QueryError } from "@/components/app-shell";
import { calculateOrderFinancialState } from "@/domain/order.mjs";

export default async function AnalyticsPage() {
  const ctx = await requireMembership();
  if (!ctx.ok) redirect("/login");

  const canSeePayments = ["owner", "admin", "service_manager", "service_advisor", "finance"].includes(String(ctx.role));
  const canSeeExpenses = ["owner", "admin", "service_manager", "finance"].includes(String(ctx.role));
  const canSeeOrderEconomics = ["owner", "admin", "service_manager", "service_advisor", "parts_manager", "finance"].includes(String(ctx.role));

  const [ordersResult, paymentsResult, expensesResult, linesResult] = await Promise.all([
    ctx.supabase.from("work_orders").select("id,status,created_at,completed_at").eq("tenant_id", ctx.tenantId).order("created_at", { ascending: false }).limit(500),
    canSeePayments
      ? ctx.supabase.from("payments").select("amount,paid_at").eq("tenant_id", ctx.tenantId).order("paid_at", { ascending: false }).limit(500)
      : Promise.resolve({ data: [], error: null }),
    canSeeExpenses
      ? ctx.supabase.from("expenses").select("amount,expense_date,category").eq("tenant_id", ctx.tenantId).order("expense_date", { ascending: false }).limit(500)
      : Promise.resolve({ data: [], error: null }),
    canSeeOrderEconomics
      ? ctx.supabase.from("work_order_lines").select("id,work_order_id,quantity,work_order_line_financials(customer_unit_price,direct_unit_cost)").eq("tenant_id", ctx.tenantId).limit(1000)
      : Promise.resolve({ data: [], error: null })
  ]);

  const orders = ordersResult.data ?? [];
  const payments = paymentsResult.data ?? [];
  const expenses = expensesResult.data ?? [];
  const lines = linesResult.data ?? [];
  const active = orders.filter((order: any) => !["completed", "cancelled"].includes(order.status)).length;
  const totalIn = payments.reduce((sum: number, payment: any) => sum + Number(payment.amount || 0), 0);
  const totalOut = expenses.reduce((sum: number, expense: any) => sum + Number(expense.amount || 0), 0);
  const one = (value: any) => Array.isArray(value) ? value[0] : value;
  const missingPrices = lines.some((line: any) => !one(line.work_order_line_financials));
  const estimated = missingPrices ? null : calculateOrderFinancialState(
    lines.map((line: any) => ({ quantity: line.quantity, unitPrice: one(line.work_order_line_financials)?.customer_unit_price }))
  ).totalMinor / 100;
  const statuses: Record<string, number> = {};
  orders.forEach((order: any) => { statuses[order.status] = (statuses[order.status] || 0) + 1; });

  return <AppShell active="analytics" tenantName={ctx.tenant.name} role={ctx.role} currency={ctx.tenant.currency} timezone={ctx.tenant.timezone}>
    <div className="page-heading"><div><div className="eyebrow">УПРАВЛЕНЧЕСКАЯ ОТЧЁТНОСТЬ</div><h1>Аналитика</h1><p className="subtitle">Сводные показатели по загруженным данным организации. Показатели ограничены последними выборками запросов.</p></div></div><nav className="work-tabs finance-tabs" aria-label="Разделы финансов"><a href="/money">Деньги и оплаты</a><a href="/analytics" className="active" aria-current="page">Аналитика</a></nav>
    <QueryError title="Заказы" error={ordersResult.error}/>
    {canSeePayments ? <QueryError title="Поступления" error={paymentsResult.error}/> : null}
    {canSeeExpenses ? <QueryError title="Расходы" error={expensesResult.error}/> : null}
    {canSeeOrderEconomics ? <QueryError title="Экономика заказов" error={linesResult.error}/> : null}
    <div className="grid grid-4">
      <div className="panel metric-card"><div className="metric-label">ЗАКАЗОВ В ВЫБОРКЕ</div><div className="metric-value">{ordersResult.data?.length ?? "—"}</div></div>
      <div className="panel metric-card teal"><div className="metric-label">АКТИВНЫЕ ЗАКАЗЫ</div><div className="metric-value">{ordersResult.error ? "—" : active}</div></div>
      {canSeePayments ? <div className="panel metric-card amber"><div className="metric-label">ПОСТУПЛЕНИЯ · ПОСЛЕДНИЕ 500</div><div className="metric-value" style={{fontSize:22}}>{money(totalIn, ctx.tenant.currency)}</div></div> : null}
      {canSeeExpenses ? <div className="panel metric-card purple"><div className="metric-label">РАСХОДЫ · ПОСЛЕДНИЕ 500</div><div className="metric-value" style={{fontSize:22}}>{money(totalOut, ctx.tenant.currency)}</div></div> : null}
    </div>
    <div className="grid grid-2 section-gap">
      <section className="panel"><div className="panel-head"><h2 className="panel-title">Заказы по статусам</h2></div>{Object.entries(statuses).length ? Object.entries(statuses).map(([key, value]) => <div className="list-row" key={key}><b>{statusName(key)}</b><span className="tag blue">{value}</span></div>) : <div className="empty-state">Нет данных.</div>}</section>
      {canSeeOrderEconomics || canSeePayments || canSeeExpenses ? <section className="panel"><div className="panel-head"><h2 className="panel-title">Экономические показатели</h2></div>
        {canSeeOrderEconomics ? <div className="list-row"><span>Сумма строк заказ-нарядов по розничным ценам</span><b>{estimated === null ? "Проверить данные" : money(estimated, ctx.tenant.currency)}</b></div> : null}
        {canSeePayments ? <div className="list-row"><span>Поступления (последние 500)</span><b className="amount-positive">{money(totalIn, ctx.tenant.currency)}</b></div> : null}
        {canSeeExpenses ? <div className="list-row"><span>Расходы (последние 500)</span><b className="amount-negative">{money(totalOut, ctx.tenant.currency)}</b></div> : null}
        <div className="notice">Это управленческие показатели по ограниченной выборке, а не бухгалтерская отчётность и не расчёт чистой прибыли.</div>
      </section> : null}
    </div>
  </AppShell>;
}

function money(value: number, currency: string) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency, maximumFractionDigits: 2 }).format(value);
}
function statusName(status: string) {
  const labels: Record<string, string> = { new: "Новый", accepted: "Принят", diagnostics: "Диагностика", awaiting_approval: "Согласование", awaiting_parts: "Ожидает детали", in_progress: "В работе", quality_check: "Контроль качества", ready: "Готов", completed: "Завершён", cancelled: "Отменён" };
  return labels[status] ?? status;
}
