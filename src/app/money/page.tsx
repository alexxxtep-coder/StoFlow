import { redirect } from "next/navigation";
import { requireMembership } from "@/lib/auth/context";
import { AppShell, QueryError } from "@/components/app-shell";
import { createExpense, createPayment } from "./actions";
import { calculateOrderFinancialState, sumMoneyMinor } from "@/domain/order.mjs";
import { dateOnlyInTimeZone, formatDateOnly, formatInTimeZone } from "@/domain/timezone.mjs";

type Relation<T> = T | T[] | null;
const one = <T,>(value: Relation<T>): T | null => Array.isArray(value) ? value[0] ?? null : value;
const money = (value: number, currency: string) => new Intl.NumberFormat("ru-RU", {
  style: "currency", currency, maximumFractionDigits: 2
}).format(value);

export default async function MoneyPage() {
  const ctx = await requireMembership();
  if (!ctx.ok) redirect("/login");

  const canSeeFinance = ["owner", "admin", "service_manager", "service_advisor", "finance"].includes(String(ctx.role));
  const canSeeExpenses = ["owner", "admin", "service_manager", "finance"].includes(String(ctx.role));
  const canPayment = ["owner", "admin", "service_manager", "service_advisor", "finance"].includes(String(ctx.role));
  // Keep the UI's permissions identical to the server action and the database policy.
  const canExpense = ["owner", "admin", "finance"].includes(String(ctx.role));

  const [paymentsResult, expensesResult, customersResult, ordersResult, closedOrdersResult] = await Promise.all([
    canSeeFinance
      ? ctx.supabase.from("payments").select("id,amount,currency,payment_method,reference,paid_at,customers(name)").eq("tenant_id", ctx.tenantId).order("paid_at", { ascending: false }).limit(100)
      : Promise.resolve({ data: [], error: null }),
    canSeeExpenses
      ? ctx.supabase.from("expenses").select("id,category,description,amount,currency,expense_date").eq("tenant_id", ctx.tenantId).order("expense_date", { ascending: false }).limit(100)
      : Promise.resolve({ data: [], error: null }),
    canPayment
      ? ctx.supabase.from("customers").select("id,name,normalized_phone").eq("tenant_id", ctx.tenantId).order("name").limit(500)
      : Promise.resolve({ data: [], error: null }),
    canPayment
      ? ctx.supabase.from("work_orders").select("id,order_number,status,customer_id,customers(name)").eq("tenant_id", ctx.tenantId).neq("status", "cancelled").order("created_at", { ascending: false }).limit(300)
      : Promise.resolve({ data: [], error: null }),
    canSeeFinance
      ? ctx.supabase.from("work_orders").select("id,order_number,status,created_at,completed_at,customers(name),work_order_lines(quantity,work_order_line_financials(customer_unit_price)),payment_allocations(amount)").eq("tenant_id", ctx.tenantId).eq("status", "completed").order("completed_at", { ascending: false }).limit(300)
      : Promise.resolve({ data: [], error: null })
  ]);

  const payments = paymentsResult.data ?? [];
  const expenses = expensesResult.data ?? [];
  const customers = customersResult.data ?? [];
  const orders = ordersResult.data ?? [];
  const closedOrders = closedOrdersResult.data ?? [];
  const income = payments.reduce((sum: number, item: any) => sum + Number(item.amount || 0), 0);
  const out = expenses.reduce((sum: number, item: any) => sum + Number(item.amount || 0), 0);

  return <AppShell active="money" tenantName={ctx.tenant.name} role={ctx.role} currency={ctx.tenant.currency} timezone={ctx.tenant.timezone}>
    <div className="page-heading"><div><div className="eyebrow">ФИНАНСОВЫЙ КОНТУР</div><h1>Финансы</h1><p className="subtitle">Поступления, расходы и финансовая история завершённых заказ-нарядов.</p></div></div><nav className="work-tabs finance-tabs" aria-label="Разделы финансов"><a href="/money" className="active" aria-current="page">Деньги и оплаты</a><a href="/analytics">Аналитика</a></nav>

    {canSeeFinance ? <>
      <div className={`grid ${canSeeExpenses ? "grid-3" : "grid-2"}`}>
        <div className="panel metric-card teal"><div className="metric-label">ЗАРЕГИСТРИРОВАННЫЕ ОПЛАТЫ</div><div className="metric-value">{money(income, ctx.tenant.currency)}</div><div className="metric-foot">Последние {payments.length} платежей (лимит 100)</div></div>
        {canSeeExpenses ? <>
          <div className="panel metric-card amber"><div className="metric-label">ЗАРЕГИСТРИРОВАННЫЕ РАСХОДЫ</div><div className="metric-value">{money(out, ctx.tenant.currency)}</div><div className="metric-foot">Последние {expenses.length} расходов (лимит 100)</div></div>
          <div className="panel metric-card purple"><div className="metric-label">РАЗНИЦА ПО ВЫБРАННЫМ ЗАПИСЯМ</div><div className="metric-value">{money(income - out, ctx.tenant.currency)}</div><div className="metric-foot">Не является расчётом чистой прибыли</div></div>
        </> : <div className="panel metric-card"><div className="metric-label">ЗАВЕРШЁННЫЕ ЗАКАЗЫ</div><div className="metric-value">{closedOrders.length}</div><div className="metric-foot">Последние 300 завершённых заказ-нарядов</div></div>}
      </div>
      <QueryError title="Платежи" error={paymentsResult.error}/>
      {canSeeExpenses ? <QueryError title="Расходы" error={expensesResult.error}/> : null}
      <QueryError title="Завершённые заказы" error={closedOrdersResult.error}/>
    </> : <div className="panel"><div className="empty-state">У вашей роли нет доступа к финансовым данным.</div></div>}

    <div className="grid grid-2 section-gap">
      {canPayment ? <section className="panel"><div className="eyebrow">КАССА</div><h2 className="panel-title" style={{ marginTop: 6 }}>Зарегистрировать оплату</h2><QueryError title="Клиенты" error={customersResult.error}/><QueryError title="Заказы для распределения оплаты" error={ordersResult.error}/><form action={createPayment}>
        <label className="field">Клиент<select name="customerId" required defaultValue=""><option value="" disabled>Выберите клиента</option>{customers.map((customer: any) => <option key={customer.id} value={customer.id}>{customer.name} · {customer.normalized_phone}</option>)}</select></label>
        <label className="field">Заказ-наряд (необязательно)<select name="workOrderId" defaultValue=""><option value="">Не распределять на заказ</option>{orders.map((order: any) => <option key={order.id} value={order.id}>№{order.order_number} · {one(order.customers)?.name ?? "Клиент"} · {order.status === "completed" ? "Выдан" : order.status}</option>)}</select></label>
        <label className="field">Сумма<input name="amount" type="number" min="0.01" step="0.01" required/></label>
        <label className="field">Способ оплаты<select name="method"><option value="cash">Наличные</option><option value="card">Карта</option><option value="bank_transfer">Банковский перевод</option><option value="other">Другое</option></select></label>
        <label className="field">Комментарий / референс<input name="reference" maxLength={160}/></label>
        <button className="btn">Сохранить оплату</button>
      </form><p className="cell-sub">Если выбран заказ, сервер проверит его остаток и не позволит распределить больше неоплаченной суммы.</p></section> : null}

      {canExpense ? <section className="panel"><div className="eyebrow">УЧЁТ ЗАТРАТ</div><h2 className="panel-title" style={{ marginTop: 6 }}>Добавить расход</h2><form action={createExpense}>
        <label className="field">Категория<input name="category" required minLength={2} maxLength={80} placeholder="Например, аренда"/></label>
        <label className="field">Описание<input name="description" maxLength={240}/></label>
        <label className="field">Заказ-наряд (необязательно)<select name="workOrderId" defaultValue=""><option value="">Не распределять на заказ</option>{orders.map((order: any) => <option key={order.id} value={order.id}>№{order.order_number} · {one(order.customers)?.name ?? "Клиент"}</option>)}</select></label>
        <label className="field">Сумма<input name="amount" type="number" min="0.01" step="0.01" required/></label>
        <label className="field">Дата<input name="date" type="date" required defaultValue={dateOnlyInTimeZone(new Date(), ctx.tenant.timezone)}/></label>
        <button className="btn">Сохранить расход</button>
      </form></section> : null}
    </div>

    {canSeeFinance ? <>
      <section className="panel section-gap"><div className="panel-head"><div><div className="eyebrow">ЗАКРЫТЫЙ ЦИКЛ</div><h2 className="panel-title" style={{ marginTop: 5 }}>Выданные автомобили · финансовая история</h2><p className="subtitle">Завершённые заказ-наряды не исчезают после выдачи. Здесь сохраняются сумма работ, полученная оплата и остаток.</p></div><span className="tag green">{closedOrders.length}</span></div>
        {closedOrders.length ? <div className="table-wrap"><table><thead><tr><th>Заказ / клиент</th><th>Дата выдачи</th><th>Начислено</th><th>Оплачено</th><th>Остаток</th><th></th></tr></thead><tbody>{closedOrders.map((order: any) => {
          const lines = (order.work_order_lines ?? []) as any[];
          const hasIncompletePricing = lines.some((line: any) => !one(line.work_order_line_financials));
          const allocations = (order.payment_allocations ?? []) as any[];
          const financial = hasIncompletePricing ? null : calculateOrderFinancialState(
            lines.map((line: any) => ({ quantity: line.quantity, unitPrice: one(line.work_order_line_financials)?.customer_unit_price })),
            allocations
          );
          const paid = sumMoneyMinor(allocations.map((allocation: any) => allocation.amount || 0)) / 100;
          const balance = financial ? financial.balanceMinor / 100 : null;
          return <tr key={order.id}><td><a className="cell-title" href={`/work/${order.id}`}>№{order.order_number}</a><div className="cell-sub">{one(order.customers)?.name ?? "Клиент"}</div></td><td>{order.completed_at ? formatInTimeZone(order.completed_at,ctx.tenant.timezone,{dateStyle:"short"}) : formatInTimeZone(order.created_at,ctx.tenant.timezone,{dateStyle:"short"})}</td><td><b>{financial ? money(financial.totalMinor / 100, ctx.tenant.currency) : "Проверить строки"}</b></td><td className="amount-positive">{money(paid, ctx.tenant.currency)}</td><td className={balance !== null && balance > 0 ? "amount-negative" : "amount-positive"}>{balance === null ? "—" : money(balance, ctx.tenant.currency)}</td><td><a className="btn outline small" href={`/work/${order.id}`}>Открыть</a></td></tr>;
        })}</tbody></table></div> : <div className="empty-state">Выданных автомобилей пока нет. После завершения заказ-наряд останется в этом реестре.</div>}
      </section>

      <div className="grid grid-2 section-gap">
        <section className="panel"><div className="panel-head"><h2 className="panel-title">Последние оплаты</h2><span className="tag green">{payments.length}</span></div>{payments.length ? <div className="table-wrap"><table><thead><tr><th>Клиент</th><th>Дата</th><th>Способ</th><th>Сумма</th></tr></thead><tbody>{payments.map((payment: any) => <tr key={payment.id}><td className="cell-title">{one(payment.customers)?.name ?? "Клиент"}</td><td>{formatInTimeZone(payment.paid_at,ctx.tenant.timezone,{dateStyle:"short"})}</td><td>{payment.payment_method || "—"}</td><td className="amount-positive">{money(Number(payment.amount), payment.currency)}</td></tr>)}</tbody></table></div> : <div className="empty-state">Оплат пока нет.</div>}</section>
        {canSeeExpenses ? <section className="panel"><div className="panel-head"><h2 className="panel-title">Последние расходы</h2><span className="tag amber">{expenses.length}</span></div>{expenses.length ? <div className="table-wrap"><table><thead><tr><th>Категория</th><th>Описание</th><th>Дата</th><th>Сумма</th></tr></thead><tbody>{expenses.map((expense: any) => <tr key={expense.id}><td className="cell-title">{expense.category}</td><td>{expense.description || "—"}</td><td>{formatDateOnly(expense.expense_date)}</td><td className="amount-negative">{money(Number(expense.amount), expense.currency)}</td></tr>)}</tbody></table></div> : <div className="empty-state">Расходов пока нет.</div>}</section> : null}
      </div>
    </> : null}
  </AppShell>;
}
