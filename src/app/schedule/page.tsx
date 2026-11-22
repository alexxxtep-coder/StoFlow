import Link from "next/link";
import { redirect } from "next/navigation";
import { requireMembership } from "@/lib/auth/context";
import { AppShell, QueryError } from "@/components/app-shell";
import { createAppointment } from "./actions";
import { formatInTimeZone, localDateTimeToIso, toDateTimeLocalValue } from "@/domain/timezone.mjs";

type SearchParams = Promise<{ week?: string }>;

function addDays(date: string, amount: number) {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + amount);
  return value.toISOString().slice(0, 10);
}

function mondayOf(date: string) {
  const value = new Date(`${date}T12:00:00Z`);
  const day = (value.getUTCDay() + 6) % 7;
  value.setUTCDate(value.getUTCDate() - day);
  return value.toISOString().slice(0, 10);
}

function isDate(value: string | undefined): value is string {
  if (!value || !/^\\d{4}-\\d{2}-\\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T12:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function dayLabel(date: string) {
  return new Intl.DateTimeFormat("ru-RU", {
    weekday: "short", day: "numeric", month: "short", timeZone: "UTC"
  }).format(new Date(`${date}T12:00:00Z`));
}

export default async function SchedulePage({ searchParams }: { searchParams: SearchParams }) {
  const ctx = await requireMembership();
  if (!ctx.ok) redirect("/login");

  const params = await searchParams;
  const today = toDateTimeLocalValue(Date.now(), ctx.tenant.timezone).slice(0, 10);
  const selectedWeek = mondayOf(isDate(params.week) ? params.week : today);
  const weekEnd = addDays(selectedWeek, 7);
  const startIso = localDateTimeToIso(`${selectedWeek}T00:00`, ctx.tenant.timezone);
  const endIso = localDateTimeToIso(`${weekEnd}T00:00`, ctx.tenant.timezone);

  const [{ data: appointments, error }, { data: customers, error: customerError }, { data: resources, error: resourceError }] = await Promise.all([
    ctx.supabase.from("appointments").select("id,starts_at,ends_at,status,notes,customers(name,normalized_phone),resources(name)").eq("tenant_id", ctx.tenantId).lt("starts_at", endIso).gt("ends_at", startIso).order("starts_at").limit(250),
    ctx.supabase.from("customers").select("id,name,normalized_phone").eq("tenant_id", ctx.tenantId).order("name").limit(500),
    ctx.supabase.from("resources").select("id,name,resource_type").eq("tenant_id", ctx.tenantId).eq("is_active", true).order("name")
  ]);

  const canEdit = ["owner", "admin", "service_manager", "service_advisor"].includes(String(ctx.role));
  const days = Array.from({ length: 7 }, (_, index) => addDays(selectedWeek, index));
  const byDay = new Map(days.map(day => [day, (appointments ?? []).filter((appointment: any) => toDateTimeLocalValue(appointment.starts_at, ctx.tenant.timezone).slice(0, 10) === day)]));

  return <AppShell active="schedule" tenantName={ctx.tenant.name} role={ctx.role} currency={ctx.tenant.currency} timezone={ctx.tenant.timezone}>
    <div className="page-heading">
      <div><div className="eyebrow">ПЛАНИРОВАНИЕ ПОСТОВ</div><h1>Календарь записей</h1><p className="subtitle">Недельный обзор записей по дням, постам и времени. Пересечения на одном посту блокируются базой данных.</p></div>
      <div className="heading-actions"><Link className="btn outline" href={`/schedule?week=${addDays(selectedWeek, -7)}`}>← Неделя</Link><Link className="btn outline" href={`/schedule?week=${today}`}>Сегодня</Link><Link className="btn outline" href={`/schedule?week=${addDays(selectedWeek, 7)}`}>Следующая →</Link></div>
    </div>
    <form method="get" className="calendar-toolbar"><label className="field">Перейти к неделе<input type="date" name="week" defaultValue={selectedWeek}/></label><button className="btn outline">Показать</button><span className="cell-sub">{dayLabel(selectedWeek)} — {dayLabel(addDays(selectedWeek, 6))}</span></form>
    <QueryError title="Записи" error={error}/><QueryError title="Клиенты" error={customerError}/><QueryError title="Рабочие посты" error={resourceError}/>
    {canEdit ? <section className="panel section-gap">
      <div className="eyebrow">НОВАЯ ЗАПИСЬ</div><h2 className="panel-title" style={{ marginTop: 5 }}>Записать клиента</h2>
      <form action={createAppointment} className="form-grid">
        <label className="field">Клиент *<select name="customerId" required defaultValue=""><option value="" disabled>Выберите клиента</option>{customers?.map((customer: any) => <option value={customer.id} key={customer.id}>{customer.name} · {customer.normalized_phone}</option>)}</select></label>
        <label className="field">Пост / ресурс<select name="resourceId" defaultValue=""><option value="">Без назначения</option>{resources?.map((resource: any) => <option value={resource.id} key={resource.id}>{resource.name}</option>)}</select></label>
        <label className="field">Начало *<input type="datetime-local" name="start" required defaultValue={toDateTimeLocalValue(Date.now() + 3600000, ctx.tenant.timezone)}/></label>
        <label className="field">Окончание *<input type="datetime-local" name="end" required defaultValue={toDateTimeLocalValue(Date.now() + 2 * 3600000, ctx.tenant.timezone)}/></label>
        <label className="field span-2">Комментарий<input name="notes" maxLength={500}/></label>
        <div className="span-2"><button className="btn">Создать запись</button></div>
      </form>
    </section> : null}
    <section className="section-gap">
      <div className="panel-head"><div><div className="eyebrow">НЕДЕЛЬНОЕ РАСПИСАНИЕ</div><h2 className="panel-title" style={{ marginTop: 5 }}>Записи по дням</h2></div><span className="tag">{appointments?.length ?? 0} записей</span></div>
      <div className="calendar-week">
        {days.map(day => {
          const items = byDay.get(day) ?? [];
          return <section className={`calendar-day ${day === today ? "is-today" : ""}`} key={day}>
            <header><b>{dayLabel(day)}</b><span>{items.length}</span></header>
            <div className="calendar-day-body">
              {items.length ? items.map((appointment: any) => <article className="calendar-entry" key={appointment.id}>
                <b>{formatInTimeZone(appointment.starts_at, ctx.tenant.timezone, { hour: "2-digit", minute: "2-digit" })}–{formatInTimeZone(appointment.ends_at, ctx.tenant.timezone, { hour: "2-digit", minute: "2-digit" })}</b>
                <strong>{appointment.customers?.name ?? "Клиент"}</strong>
                <span>{appointment.resources?.name ?? "Пост не назначен"}</span>
                <span className={`tag ${appointment.status === "confirmed" ? "green" : appointment.status === "cancelled" ? "red" : "blue"}`}>{appointmentStatus(appointment.status)}</span>
                {appointment.notes ? <small>{appointment.notes}</small> : null}
              </article>) : <div className="calendar-empty">Нет записей</div>}
            </div>
          </section>;
        })}
      </div>
      <p className="cell-sub calendar-note">В календаре показаны записи, пересекающие выбранную неделю. Для перехода к конкретной дате выберите её в поле выше.</p>
    </section>
  </AppShell>;
}

function appointmentStatus(status: string) {
  const labels: Record<string, string> = { requested: "Запрошена", confirmed: "Подтверждена", arrived: "Прибыл", cancelled: "Отменена", no_show: "Не явился" };
  return labels[status] ?? status;
}
