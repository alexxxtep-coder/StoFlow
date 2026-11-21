# Модель данных

Миграция `0001_initial_schema.sql` задаёт ядро:
- Организации и членства: tenants, memberships.
- CRM: customers, vehicles, leads.
- Ресурсы и запись: resources, appointments.
- Заказ: work_orders, work_order_lines, work_order_line_financials.
- Исполнение: tasks.
- Parts.Finder: suppliers, part_requests, supplier_offers, purchases.
- Финансы: payments, payment_allocations, expenses.
- Контроль: audit_logs.

Все денежные поля `numeric`; даты/время — `timestamptz`; идентификаторы — UUID. Связи ключевых сущностей используют составные foreign keys с tenant_id.

## Следующие таблицы/поля до пилота
- customer_contacts и customer_consents;
- conversations, messages, interaction_events;
- employee profiles, shifts, competencies;
- quality_checklists / checklist_items;
- purchase_receipt_lines и история движения;
- order status history с actor/from/to/reason;
- permissions/role_permissions;
- notifications/outbox;
- attachments/storage metadata;
- SaaS plans/subscriptions/invoices;
- location_id и филиальная модель при подтверждённой необходимости.
