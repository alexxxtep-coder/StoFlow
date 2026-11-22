import type { ReactNode } from "react";
import Link from "next/link";
import { signOut } from "@/app/logout/actions";
import { formatInTimeZone } from "@/domain/timezone.mjs";

// The five primary areas mirror the 5.7 workshop prototype.
// Secondary routes stay grouped under the same mental model.
const groups = [
  { label: "ОСНОВНОЕ", items: [
    ["/today", "▦", "Сегодня", "today"],
    ["/work", "◉", "Работа", "work"],
    ["/clients", "♙", "Клиенты", "clients"],
    ["/money", "◈", "Финансы", "money"],
    ["/manage", "☷", "Управление", "manage"],
  ]},
] as const;

const secondary: Record<string, readonly (readonly [string, string, string])[]> = {
  work: [
    ["/tasks", "✓", "Задачи"],
    ["/schedule", "▦", "Календарь и посты"],
    ["/archive", "▤", "Архив заказов"],
    ["/supply", "⚙", "Снабжение и запчасти"],
  ],
  money: [
    ["/analytics", "▥", "Аналитика"],
  ],
  manage: [
    ["/settings", "⚙", "Настройки"],
    ["/assistant", "✧", "ИИ-помощник"],
    ["/automation", "⟳", "Автоматизация"],
    ["/online-booking", "▣", "Онлайн-запись"],
    ["/integrations", "⌘", "Интеграции"],
  ],
};

const routeArea: Record<string, string> = {
  today: "today", work: "work", tasks: "work", schedule: "work", archive: "work",
  supply: "work", clients: "clients", money: "money", analytics: "money",
  manage: "manage", settings: "manage", assistant: "manage", automation: "manage",
  "online-booking": "manage", integrations: "manage",
};

export function AppShell({ children, active, tenantName, role, currency = "BYN", timezone = "Europe/Minsk" }: {
  children: ReactNode; active: string; tenantName: string; role: string; currency?: string; timezone?: string;
}) {
  const area = routeArea[active] ?? active;
  const secondaryItems = secondary[area] ?? [];
  return <div className="app-shell">
    <aside className="sidebar">
      <Link href="/today" className="brand-lockup"><span className="brand-mark">S</span><span><b>STO.Flow</b><small>WORKSHOP OS · 5.7 UX</small></span></Link>
      <div className="workspace-chip"><span className="workspace-dot"/><span><small>РАБОЧЕЕ ПРОСТРАНСТВО</small><b>{tenantName}</b></span></div>
      {groups.map(group => <div className="nav-group" key={group.label}><div className="nav-label">{group.label}</div><nav className="nav">{group.items.map(([href, icon, label, key]) => <Link key={href} href={href} className={area === key ? "active" : ""}><span className="nav-icon">{icon}</span><span>{label}</span></Link>)}</nav></div>)}
      {secondaryItems.length > 0 ? <div className="nav-subgroup">
        <div className="nav-label">РАЗДЕЛЫ</div>
        <nav className="nav nav-secondary">{secondaryItems.map(([href, icon, label]) => <Link key={href} href={href} className={active === href.slice(1) ? "active" : ""}><span className="nav-icon">{icon}</span><span>{label}</span></Link>)}</nav>
      </div> : null}
      <div className="sidebar-bottom"><div className="user-avatar">{role === "owner" ? "В" : "С"}</div><div className="user-meta"><b>{roleLabel(role)}</b><small>{currency} · {timezone}</small></div><span className="online-dot" title="Рабочее пространство"/><form action={signOut}><button className="side-logout" title="Выйти" aria-label="Выйти">↪</button></form></div>
    </aside>
    <main className="main-area">
      <header className="topbar"><div className="topbar-left"><span className="status-pill"><i/>Система активна</span><span className="topbar-divider"/> <span className="topbar-context">{areaLabel(area)}</span></div><div className="topbar-right"><span className="topbar-date">{formatInTimeZone(new Date(), timezone, { dateStyle: "medium" })}</span><span className="topbar-avatar">{tenantName.slice(0,1).toUpperCase()}</span></div></header>
      <div className="page-content">{children}</div>
      <footer className="app-footer"><span>STO.Flow · интерфейс по эталону 5.7</span><span>Данные из Supabase · изоляция по организациям</span></footer>
    </main>
  </div>;
}

function areaLabel(area: string) {
  const labels: Record<string,string> = { today: "Рабочий день", work: "Операционная работа", clients: "Клиентская база", money: "Финансы и аналитика", manage: "Управление сервисом" };
  return labels[area] ?? "Рабочее пространство";
}

export function roleLabel(role: string) {
  const labels: Record<string,string> = { owner: "Владелец", admin: "Администратор", service_manager: "Руководитель сервиса", service_advisor: "Приёмщик", mechanic: "Механик", parts_manager: "Снабжение", finance: "Финансы" };
  return labels[role] ?? role;
}

export function QueryError({ title, error }: { title: string; error: { message?: string; code?: string } | null | undefined }) {
  if (!error) return null;
  return <div className="query-error"><b>{title}: данные не загрузились.</b><span>{error.message || "Неизвестная ошибка запроса."}{error.code ? ` · Код ${error.code}` : ""}</span><small>Проверьте миграции Supabase, права роли и политики доступа. Подробности также доступны в терминале сервера.</small></div>;
}
