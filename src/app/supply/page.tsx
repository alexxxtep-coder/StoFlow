import Link from "next/link";
import { redirect } from "next/navigation";
import { requireMembership } from "@/lib/auth/context";
import { AppShell, QueryError } from "@/components/app-shell";
import { addManualOffer, createPartRequest, orderSelectedOffer } from "./actions";
import { formatInTimeZone } from "@/domain/timezone.mjs";

type SearchParams = Promise<{ order?: string }>;

export default async function SupplyPage({ searchParams }: { searchParams: SearchParams }) {
  const ctx = await requireMembership();
  if (!ctx.ok) redirect("/login");
  const params = await searchParams;
  const requestedOrderId = params.order && /^[0-9a-f-]{36}$/i.test(params.order) ? params.order : "";

  const [{ data: orders, error: orderError }, { data: requests, error: requestError }, { data: offers, error: offerError }, { data: purchases, error: purchaseError }] = await Promise.all([
    ctx.supabase.from("work_orders").select("id,order_number,status,customers(name),vehicles(make,model)").eq("tenant_id", ctx.tenantId).not("status", "in", "(completed,cancelled)").order("created_at", { ascending: false }),
    ctx.supabase.from("part_requests").select("id,work_order_id,description,oem_number,quantity,status,created_at,work_orders(id,order_number)").eq("tenant_id", ctx.tenantId).order("created_at", { ascending: false }).limit(80),
    ctx.supabase.from("supplier_offers").select("id,part_request_id,title,brand,sku,purchase_price,currency,availability,eta_at,fitment_status,source_type,observed_at,status,suppliers(name)").eq("tenant_id", ctx.tenantId).order("observed_at", { ascending: false }),
    ctx.supabase.from("purchases").select("id,part_request_id,status,ordered_at,expected_at,suppliers(name)").eq("tenant_id", ctx.tenantId).order("created_at", { ascending: false })
  ]);

  const canManage = ["owner", "admin", "service_manager", "parts_manager"].includes(String(ctx.role));
  const canRequest = ["owner", "admin", "service_manager", "service_advisor", "mechanic"].includes(String(ctx.role));
  const selectedOrder = orders?.find((order: any) => order.id === requestedOrderId);

  return <AppShell active="supply" tenantName={ctx.tenant.name} role={ctx.role} currency={ctx.tenant.currency} timezone={ctx.tenant.timezone}>
    <div className="page-heading"><div><div className="eyebrow">PARTS.FINDER · СНАБЖЕНИЕ</div><h1>Запчасти и поставки</h1><p className="subtitle">Потребность из заказ-наряда, ручное сравнение предложений, закупка и приёмка.</p></div></div>
    <div className="notice">Реальные каталоги и API поставщиков не подключены. Предложения ниже — ручной ввод сотрудников с источником и временем фиксации. Проверяйте цену и применимость перед закупкой.</div>
    <QueryError title="Заказ-наряды" error={orderError}/><QueryError title="Заявки на детали" error={requestError}/><QueryError title="Предложения поставщиков" error={offerError}/><QueryError title="Закупки" error={purchaseError}/>

    <section className="panel">
      <div className="eyebrow">НОВАЯ ПОТРЕБНОСТЬ</div><h2 className="panel-title" style={{ marginTop: 5 }}>Запросить деталь для заказа</h2>
      {selectedOrder ? <div className="notice" style={{ marginTop: 10 }}>Контекст заказа: <Link href={`/work/${selectedOrder.id}`}>№{selectedOrder.order_number}</Link> · {one(selectedOrder.customers)?.name ?? "Клиент"} · {[one(selectedOrder.vehicles)?.make, one(selectedOrder.vehicles)?.model].filter(Boolean).join(" ")}</div> : null}
      {canRequest && orders?.length ? <form action={createPartRequest} className="form-grid">
        <label className="field">Заказ<select name="orderId" required defaultValue={selectedOrder?.id ?? ""}><option value="" disabled>Выберите заказ</option>{orders.map((order: any) => <option key={order.id} value={order.id}>№{order.order_number} · {order.customers?.name}</option>)}</select></label>
        <label className="field">Наименование детали<input name="description" required minLength={2} maxLength={240} placeholder="Передний ступичный подшипник"/></label>
        <label className="field">OEM / артикул<input name="oem" maxLength={80}/></label>
        <label className="field">Количество<input name="quantity" type="number" min="0.001" step="0.001" defaultValue="1" required/></label>
        <div className="span-2"><button className="btn">Создать заявку</button></div>
      </form> : <div className="empty-state">{canRequest ? "Сначала создайте активный заказ-наряд." : "Создание заявок недоступно для вашей роли."}</div>}
    </section>

    <section className="section-gap">
      <div className="panel-head"><div><div className="eyebrow">СРАВНЕНИЕ ПРЕДЛОЖЕНИЙ</div><h2 className="panel-title" style={{ marginTop: 5 }}>Заявки и предложения</h2></div><span className="tag">{requests?.length ?? 0}</span></div>
      {requests?.length ? requests.map((request: any) => {
        const relatedOffers = (offers ?? []).filter((offer: any) => offer.part_request_id === request.id);
        const purchase = (purchases ?? []).find((item: any) => item.part_request_id === request.id);
        return <article className="panel section-gap" key={request.id}>
          <div className="panel-head"><div><div className="eyebrow">ЗАКАЗ {request.work_orders?.order_number ? `№${request.work_orders.order_number}` : "—"} · {request.status}</div><h3 className="panel-title" style={{ marginTop: 5 }}>{request.description}</h3><div className="cell-sub">OEM: {request.oem_number || "не указан"} · Количество: {request.quantity}</div></div>{purchase ? <span className="tag green">Закупка {purchase.status}</span> : null}</div>
          {request.work_orders?.id ? <div className="cell-sub"><Link href={`/work/${request.work_orders.id}`}>Открыть заказ-наряд ↗</Link></div> : null}
          {relatedOffers.length ? relatedOffers.map((offer: any) => <div className="list-row" key={offer.id}>
            <div className="list-row-main">
              <b>{offer.title}</b>
              <div className="cell-sub">{offer.suppliers?.name ?? "Поставщик"} · {offer.brand || "бренд не указан"} · {offer.sku || "артикул не указан"}</div>
              <div className="cell-sub">Наличие: {availabilityName(offer.availability)} · применимость: {fitmentName(offer.fitment_status)} · источник: {sourceName(offer.source_type)}</div>
              <div className="cell-sub">Срок поставки: {offer.eta_at ? formatInTimeZone(offer.eta_at, ctx.tenant.timezone, { dateStyle: "medium" }) : "не указан"} · данные зафиксированы: {formatInTimeZone(offer.observed_at, ctx.tenant.timezone, { dateStyle: "short", timeStyle: "short" })}</div>
            </div>
            <div className="text-right">
              <b>{offer.purchase_price == null ? "Цена не указана" : money(Number(offer.purchase_price), offer.currency)}</b>
              {canManage && !purchase && !["rejected", "stale", "accepted"].includes(offer.status) && offer.fitment_status !== "not_fit" && offer.availability !== "out_of_stock" && offer.purchase_price !== null
                ? <form action={orderSelectedOffer} style={{ marginTop: 7 }}><input type="hidden" name="offerId" value={offer.id}/><button className="btn small">Создать закупку</button></form>
                : null}
              {canManage && !purchase && (["rejected", "stale", "accepted"].includes(offer.status) || offer.fitment_status === "not_fit" || offer.availability === "out_of_stock" || offer.purchase_price === null)
                ? <div className="cell-sub">Закупка недоступна: проверьте статус, применимость, наличие и цену.</div>
                : null}
            </div>
          </div>) : <div className="empty-state">Предложений пока нет. Откройте каталог поставщика и внесите проверенные данные вручную.</div>}
          {purchase?.expected_at ? <div className="notice" style={{ marginTop: 9 }}>Ожидаемая поставка: {formatInTimeZone(purchase.expected_at, ctx.tenant.timezone, { dateStyle: "medium" })}</div> : null}
          {canManage ? <details className="section-gap">
            <summary style={{ cursor: "pointer", fontWeight: 800, fontSize: 11 }}>Добавить предложение вручную</summary>
            <form action={addManualOffer} className="form-grid" style={{ marginTop: 12 }}>
              <input type="hidden" name="requestId" value={request.id}/>
              <label className="field">Поставщик<input name="supplier" required minLength={2}/></label>
              <label className="field">Предложение<input name="title" required minLength={2}/></label>
              <label className="field">Цена закупки<input name="price" type="number" min="0" step="0.01"/></label>
              <label className="field">Ожидаемая дата<input name="etaAt" type="date"/></label>
              <label className="field">Бренд<input name="brand"/></label>
              <label className="field">Артикул<input name="sku"/></label>
              <label className="field">Наличие<select name="availability"><option value="unknown">Неизвестно</option><option value="in_stock">В наличии</option><option value="limited">Ограничено</option><option value="backorder">Под заказ</option><option value="out_of_stock">Нет в наличии</option></select></label>
              <label className="field">Применимость<select name="fitment"><option value="unverified">Не проверена</option><option value="confirmed">Подтверждена</option><option value="probable">Вероятна</option><option value="not_fit">Не подходит</option></select></label>
              <div className="span-2"><button className="btn small">Сохранить предложение</button></div>
            </form>
          </details> : null}
        </article>;
      }) : <div className="panel empty-state">Заявок на запчасти пока нет.</div>}
    </section>
  </AppShell>;
}

function one<T>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}
function money(value: number, currency: string) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency }).format(value);
}
function availabilityName(value: string) {
  return ({ unknown: "Неизвестно", in_stock: "В наличии", limited: "Ограничено", backorder: "Под заказ", out_of_stock: "Нет в наличии" } as Record<string, string>)[value] ?? value;
}
function fitmentName(value: string) {
  return ({ unverified: "Не проверена", probable: "Вероятна", confirmed: "Подтверждена", not_fit: "Не подходит" } as Record<string, string>)[value] ?? value;
}
function sourceName(value: string) {
  return ({ manual: "Вручную", supplier_api: "API поставщика", import: "Импорт" } as Record<string, string>)[value] ?? value;
}
