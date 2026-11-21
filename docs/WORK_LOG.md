# Build work log — STO.Flow 6.0

## Reference material

- Five self-contained HTML references were received: 5.1 Fast Intake, 5.4 Workshop Operations, 5.5 Workshop Operations, 5.6 Stabilized and 5.7 Workshop Operations.
- HTML 5.7 used as the primary UX/functionality reference; prior versions are retained for comparison.
- All HTML scripts were checked with `node --check` in the build container.
- HTML prototype localStorage is not used as the live data layer.

## Version 6.0 work in this build

- Updated app shell and visual direction inspired by 5.7; responsive nav and app-wide states.
- Today dashboard and server-action lead intake; phone validation now counts digits and normalizes formatting before the RPC call.
- Work queue, order detail, order line item, task, status history and archive screens.
- CRM customers and multiple vehicles.
- Internal schedule and server-side overlap feedback.
- Parts.Finder manual requests/offers/purchase flow.
- Payment capture, optional order allocation and expense entry.
- Management of service catalog and workshop resources; read-only membership listing.
- Basic analytics; operational rule-based assistant; explicit state pages for automation, integrations and online booking.
- Transactional RPC migration 0002 added for work-order lines and payments/allocations.

## Tests run here

- `npm test`: 6/6 unit tests passed.
- `node --check src/domain/order.mjs`: passed.
- Embedded JavaScript extracted from all five HTML prototypes: passed `node --check`.
- TypeScript/TSX transpile syntax check: 38 files, zero syntax diagnostics.
- SQL migration 0002 dollar-quote balance and function names checked statically.

## Not performed in this environment

- `npm install` did not complete because the package registry was not reachable within the execution timeout; offline npm cache lacked packages.
- Therefore Next.js production build, ESLint and full TypeScript semantic check were not run.
- No connection to the user's Supabase project was available; migrations, RPC execution, RLS, live CRUD and real dashboard loads are not verified remotely.
- No browser E2E, real concurrent booking test, backup/restore or penetration test was performed.

## Release status

Functional expanded MVP, suitable for local installation and controlled test after applying migrations 0001 (if new database) and 0002. Do not describe as a production-ready SaaS until the missing work in `KNOWN_LIMITATIONS.md` is completed and live validation passes.

## Второй полный проход проверки (2026-11-19)

- Исправлена работа с timezone организации для календаря, сроков задач и форматирования дат; добавлены тесты Europe/Minsk и IANA timezone validation.
- Закрытые заказ-наряды стали read-only для состава работ/задач/заявок на детали; добавлены DB triggers для обхода через прямые запросы.
- Защищены финансовые распределения при последующем изменении цены/количества; заблокировано перемещение строк между заказами/тенантами.
- Оплата теперь отклоняется, если у любой строки заказа отсутствует финансовая цена.
- RPC строк заказа проверяет terminal status и decimal precision; UI actions проверяют precision для сумм/количеств.
- RPC создания workspace защищена от повторного и параллельного создания нескольких активных организаций одним пользователем.
- Исправлены ролевые расхождения интерфейса снабжения, карточки заказа и аналитики.
- Повторный прогон: 24/24 Node tests; 39 TS/TSX syntax files; 91 local imports resolve. Full Next build, live SQL/RLS and browser E2E remain blocked by unavailable dependencies and Supabase/PostgreSQL connection.


## Независимый проход по архиву 0.3.0 и Supabase (2026-11-20)

- Архив распакован и проверен: 121 запись; Node tests исходной версии 24/24; JS/MJS syntax 9/9; TS/TSX syntax 41/41; 91 локальный импорт разрешается.
- Подключённая Supabase база проверена read-only: 21 таблица с RLS, пустые таблицы, схема и функции соответствуют базе 0001–0003; журнал миграций содержит только одну вручную зарегистрированную версию, поэтому требуется baseline перед CLI migration workflow.
- Добавлена миграция 0004: защита от закупки неподходящей детали, товара без наличия, предложения без цены, несоответствия валюты и заявки в terminal status.
- Исправлено локальное формирование даты расхода по timezone организации.
- После исправлений `node --test`: 26/26.
- База Supabase не изменялась; миграция 0004 не применялась. Full Next build/typecheck, browser E2E, конкурентные DB tests и backup/restore не выполнены.
