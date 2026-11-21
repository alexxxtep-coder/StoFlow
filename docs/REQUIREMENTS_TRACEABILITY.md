# Матрица прослеживаемости требований

| Требование | Источник | Реализация в текущем срезе | Статус |
|---|---|---|---|
| Единая платформа STO.Flow + Parts.Finder | Product Spec §2.1, §3.8 | Общая схема tenant/customer/vehicle/order/parts | Основа заложена |
| Шесть рабочих зон | Product Spec §3.1 | Shell частично; текущий экран «Сегодня» | Частично |
| Авторизация | Product Spec §4.3, ТЗ 1 | Supabase Auth sign-in | Реализовано в срезе |
| Организации и членства | Product Spec §4.3–4.4 | tenants, memberships, create_workspace RPC | Схема заложена |
| Изоляция tenant | Product Spec §4.3 | RLS policies и membership helper | Заложено; требует live RLS tests |
| Клиенты и автомобили | Product Spec §3.3, §3.6 | customers, vehicles | Схема + atomic lead flow |
| Обращения | Product Spec §3.3 | leads + create_lead_with_context RPC с поиском существующего клиента по нормализованному телефону | Вертикальный срез |
| Запись и ресурсы | Product Spec §3.5 | appointments, resources + PostgreSQL exclusion constraint для пересекающихся интервалов одного ресурса | Защита на уровне БД заложена; live concurrent test не проведён |
| Заказ-наряд | Product Spec §3.6 | work_orders, work_order_lines, work_order_line_financials; создание из обращения RPC; DB transition guard + status history | Создание из обращения и список активных заказов; полный редактор/строки ещё нет |
| Задачи/WIP | Product Spec §3.7 | tasks | Схема; автоматизации позже |
| Parts.Finder | Product Spec §3.8 | part_requests, supplier_offers, suppliers, purchases; RPC ручного предложения и атомарного создания закупки | Рабочий ручной сценарий: запрос → предложение → закупка; приёмка ещё нет |
| Финансы | Product Spec §3.9 | payments, allocations, expenses, numeric amounts; отдельные RLS-права | Схема; бизнес-отчёты позже |
| Коммуникации | Product Spec §3.4 | Не реализовано | Следующий этап |
| AI Assistant | Product Spec §3.12 | Не подключён | Следующий этап; не имитируется |
| Внешние supplier APIs | Product Spec §3.8 | Adapter contract пока документируется | Не подключено |
| Backup/restore, monitoring | QA checklist §6.7–6.8 | Документация/план | Не проверено |
| Беларусь: privacy/legal | QA checklist §6.9 | Зафиксировано как launch gate | Не проверено |
