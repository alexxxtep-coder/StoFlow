# Развёртывание и первичная настройка

1. Создать Supabase project в выбранном регионе после правовой проверки размещения данных.
2. В новой пустой базе выполнить `0001_initial_schema.sql`, затем последовательно `0002_transactional_operations.sql`, `0003_financial_integrity.sql` и `0004_procurement_safety.sql`.
3. Создать пользователя через Supabase Auth (на первом этапе приглашение администратором).
4. После первого входа пользователь без membership попадёт на onboarding и создаст workspace через защищённый RPC `create_workspace(p_name)`.
5. Настроить `.env.local` по `.env.example`.
6. `npm install`, `npm run dev`.
7. Для production: настроить домен, HTTPS, redirect URLs Auth, резервирование/PITR, мониторинг, логирование, секреты и CI.
8. До реального пилота пройти RLS tests, backup restore, E2E и правовую проверку.

Не использовать Supabase Service Role Key на клиенте. Не включать демо-данные в рабочую организацию.
