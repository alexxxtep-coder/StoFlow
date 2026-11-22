import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { requireMembership } from "@/lib/auth/context";
import { AppShell, QueryError } from "@/components/app-shell";
import { formatInTimeZone } from "@/domain/timezone.mjs";
import { createVehicle } from "../actions";

export default async function CustomerDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ctx = await requireMembership();
  if (!ctx.ok) redirect("/login");

  const canSeePayments = ["owner", "admin", "service_manager", "service_advisor", "finance"].includes(String(ctx.role));
  const canEdit = ["owner", "admin", "service_manager", "service_advisor"].includes(String(ctx.role));

  const [{ data: customer, error }, { data: leads, error: leadError }, { data: orders, error: orderError }, { data: payments, error: paymentError }] = await Promise.all([
    ctx.supabase.from("customers").select("id,name,normalized_phone,email,notes,created_at,vehicles(id,make,model,model_year,plate,vin,engine,transmission)").eq("id", id).eq("tenant_id", ctx.tenantId).maybeSingle(),
    ctx.supabase.from("leads").select("id,description,status,created_at").eq("customer_id", id).eq("tenant_id", ctx.tenantId).order("created_at", { ascending: false }).limit(50),
    ctx.supabase.from("work_orders").select("id,order_number,status,complaint,created_at,vehicles(make,model,plate)").eq("customer_id", id).eq("tenant_id", ctx.tenantId).order("created_at", { ascending: false }).limit(100),
    canSeePayments
      ? ctx.supabase.from("payments").select("id,amount,currency,paid_at,payment_method,reference").eq("customer_id", id).eq("tenant_id", ctx.tenantId).order("paid_at", { ascending: false }).limit(100)
      : Promise.resolve({ data: [], error: null })
  ]);

  if (!customer) notFound();

  return <AppShell active="clients" tenantName={ctx.tenant.name} role={ctx.role} currency={ctx.tenant.currency} timezone={ctx.tenant.timezone}>
    <div className="page-heading">
      <div>
        <div className="eyebrow">CRM / КАРТОЧКА КЛИЕНТА</div>
        <h1>{customer.name}</h1>
        <p className="subtitle">{customer.normalized_phone} · {customer.email || "Email не указан"}</p>
        <div className="heading-actions">
          {customer.normalized_phone ? <a className="btn outline" href={`tel:${customer.normalized_phone}`}>Позвонить</a> : null}
          {customer.email ? <a className="btn outline" href={`mailto:${customer.email}`}>Написать email</a> : null}
        </div>
      </div>
      <Link className="btn outline" href="/clients">← К клиентам</Link>
    </div>

    <div className="grid grid-3">
      <div className="panel"><div className="metric-label">АВТОМОБИЛИ</div><div className="metric-value">{customer.vehicles?.length ?? 0}</div></div>
      <div className="panel"><div className="metric-label">ОБРАЩЕНИЯ</div><div className="metric-value">{leads?.length ?? "—"}</div></div>
      <div className="panel"><div className="metric-label">ЗАКАЗ-НАРЯДЫ</div><div className="metric-value">{orders?.length ?? "—"}</div></div>
    </div>

    {customer.notes ? <section className="panel section-gap"><div className="eyebrow">ЗАМЕТКИ CRM</div><p style={{ whiteSpace: "pre-wrap", lineHeight: 1.65, fontSize: 12 }}>{customer.notes}</p></section> : null}
    <QueryError title="Обращения клиента" error={leadError}/>
    <QueryError title="Заказы клиента" error={orderError}/>
    {canSeePayments ? <QueryError title="Оплаты клиента" error={paymentError}/> : null}

    <div className="grid grid-2 section-gap">
      <section className="panel">
        <div className="panel-head"><h2 className="panel-title">Автомобили клиента</h2><span className="tag">{customer.vehicles?.length ?? 0}</span></div>
        {customer.vehicles?.length ? customer.vehicles.map((vehicle: any) => <div className="list-row" key={vehicle.id}>
          <div className="list-row-main">
            <b>{[vehicle.make, vehicle.model, vehicle.model_year].filter(Boolean).join(" ") || "Автомобиль"}</b>
            <div className="cell-sub">{vehicle.plate || "Без госномера"} · VIN {vehicle.vin || "не указан"}</div>
            <div className="cell-sub">{[vehicle.engine, vehicle.transmission].filter(Boolean).join(" · ")}</div>
          </div>
        </div>) : <div className="empty-state">Автомобили не добавлены.</div>}
        {canEdit ? <form action={createVehicle} className="section-gap">
          <input type="hidden" name="customerId" value={id}/>
          <div className="eyebrow">ДОБАВИТЬ АВТОМОБИЛЬ</div>
          <div className="form-grid">
            <label className="field">Марка<input name="make" maxLength={60}/></label>
            <label className="field">Модель<input name="model" maxLength={80}/></label>
            <label className="field">Год<input name="year" type="number" min="1886" max="2100"/></label>
            <label className="field">Госномер<input name="plate" maxLength={20}/></label>
            <label className="field span-2">VIN<input name="vin" maxLength={32}/></label>
          </div>
          <button className="btn small">Сохранить автомобиль</button>
        </form> : null}
      </section>

      <section className="panel">
        <div className="panel-head"><h2 className="panel-title">История обращений</h2><span className="tag amber">{leads?.length ?? 0}</span></div>
        {leads?.length ? leads.map((lead: any) => <div className="list-row" key={lead.id}>
          <div className="list-row-main"><b>{lead.description}</b><div className="cell-sub">{formatInTimeZone(lead.created_at, ctx.tenant.timezone, { dateStyle: "short", timeStyle: "short" })}</div></div>
          <span className="tag amber">{lead.status}</span>
        </div>) : <div className="empty-state">Обращений нет.</div>}
      </section>
    </div>

    <section className="panel section-gap">
      <div className="panel-head"><h2 className="panel-title">Заказ-наряды клиента</h2><span className="tag">{orders?.length ?? 0}</span></div>
      {orders?.length ? <div className="table-wrap"><table><thead><tr><th>Заказ</th><th>Автомобиль</th><th>Описание</th><th>Статус</th><th>Дата</th></tr></thead><tbody>
        {orders.map((order: any) => <tr key={order.id}>
          <td><Link className="cell-title" href={`/work/${order.id}`}>№{order.order_number}</Link></td>
          <td>{[order.vehicles?.make, order.vehicles?.model, order.vehicles?.plate].filter(Boolean).join(" ") || "—"}</td>
          <td>{order.complaint || "—"}</td><td>{order.status}</td>
          <td>{formatInTimeZone(order.created_at, ctx.tenant.timezone, { dateStyle: "short" })}</td>
        </tr>)}
      </tbody></table></div> : <div className="empty-state">Заказов пока нет.</div>}
    </section>

    {canSeePayments ? <section className="panel section-gap">
      <div className="panel-head"><h2 className="panel-title">Поступления от клиента</h2><span className="tag green">{payments?.length ?? 0}</span></div>
      {payments?.length ? <div className="table-wrap"><table><thead><tr><th>Дата</th><th>Способ</th><th>Комментарий</th><th>Сумма</th></tr></thead><tbody>
        {payments.map((payment: any) => <tr key={payment.id}>
          <td>{formatInTimeZone(payment.paid_at, ctx.tenant.timezone, { dateStyle: "short" })}</td>
          <td>{payment.payment_method || "—"}</td><td>{payment.reference || "—"}</td>
          <td className="amount-positive">{money(Number(payment.amount), payment.currency)}</td>
        </tr>)}
      </tbody></table></div> : <div className="empty-state">Оплат пока нет.</div>}
    </section> : <section className="panel section-gap"><div className="eyebrow">ФИНАНСЫ</div><p className="cell-sub">История платежей доступна только финансовым и управляющим ролям.</p></section>}
  </AppShell>;
}

function money(value: number, currency: string) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency }).format(value);
}
