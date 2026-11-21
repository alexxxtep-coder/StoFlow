# Known limitations — STO.Flow 6.0

This release is a functional expanded MVP for a controlled pilot, not a declaration of production readiness.

## Implemented

- Next.js App Router, Supabase SSR authentication, tenant context, PostgreSQL/RLS.
- Today dashboard, leads, lead-to-order conversion, active work-order list and detail.
- CRM customers and multiple vehicles per customer.
- Internal appointments with a PostgreSQL resource-overlap constraint.
- Basic tasks, statuses and priorities; no advanced per-stage WIP configuration.
- Work-order line items with transactional financial values (migration 0002).
- Parts request → manual supplier offer → purchase creation; migration 0004 blocks purchases for rejected/stale, not-fit, out-of-stock or unpriced offers and protects direct inserts. Receiving/status update and inventory movement are not implemented.
- Payment registration with optional allocation to one work order. Migration 0003 validates currency, amount precision, customer/order ownership, outstanding balance and prevents allocations exceeding payment/order totals. Refunds, reversals, multi-order split allocation UI and reconciliation are not implemented.
- Finance now includes a separate register of completed/issued work orders with billed amount, allocated payments and remaining balance (latest 300 orders).
- Expense registration, basic analytics and organization settings.
- Rule-based operational signals, not a generative AI assistant.

## Not implemented / external prerequisites

- Public customer self-booking portal. Only the authenticated internal appointment calendar is available.
- Supplier catalog APIs, VIN decoder/catalog, messaging, telephony, payment gateways, fiscalization or AI-provider integration.
- Automatic inventory movements, stock balances, goods receipt workflow and serial/lot tracking.
- Full WIP limits, automatic load balancing, SLA timers and automatic task creation.
- Employee invitation and full membership/role administration inside the app; invite users through Supabase Auth and configure memberships securely.
- Payroll, complete accounting, legal documents and audited profitability reporting.
- Organization switcher for users who belong to multiple tenants.
- Independently reviewed RLS coverage, live multi-tenant penetration tests, backup/restore drill, monitoring and production deployment.
- Multi-tenant users still resolve to their first active membership; an organization switcher is not implemented. Do not use accounts with multiple active memberships until this is addressed.

## Data and security

- Never use a Supabase Secret / Service Role Key in `NEXT_PUBLIC_*` variables.
- Every application query must be tenant-scoped and must still rely on RLS as the final boundary.
- Validate migration 0002 on a staging Supabase project before using the new order-line and payment RPCs.
- Do not place demo/localStorage prototype data into a live tenant without an explicit reviewed import process.

- Регистрацию расходов могут выполнять только владелец, администратор или пользователь с ролью «Финансы»; руководитель сервиса видит данные, но не проводит финансовые операции.


Migration 0004 adds procurement guards. Purchase records are intentionally immutable through the authenticated client until a reviewed goods-receipt workflow is implemented; service-role maintenance remains privileged.
