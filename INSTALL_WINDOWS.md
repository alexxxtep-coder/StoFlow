# Быстрая установка на Windows

1. Распакуйте этот архив на диск D: или другой диск с запасом свободного места.
2. Создайте `.env.local` в той же папке, где лежит `package.json`. Возьмите шаблон из `.env.example`.
3. Запустите PowerShell в папке проекта и выполните:

```powershell
New-Item -ItemType Directory -Force .tmp | Out-Null
$env:TEMP = (Join-Path (Get-Location) '.tmp')
$env:TMP = $env:TEMP
npm.cmd install --cache .npm-cache --no-audit
```

4. В Supabase SQL Editor примените SQL:
   - новая пустая база — целиком `supabase/STO.Flow_6.0_NEW_DATABASE.sql`;
   - существующая база с применённой `0001_initial_schema.sql` — целиком `supabase/STO.Flow_6.0_EXISTING_DATABASE_UPGRADE.sql` (включает 0002–0004).
   Не запускайте скрипт для новой базы поверх уже существующих таблиц.
5. Запустите:

```powershell
npm.cmd run dev
```

6. Не закрывая PowerShell, откройте `http://localhost:3000`.

Если PowerShell пишет, что `npm` не распознан или запуск `npm.ps1` запрещён, используйте именно `npm.cmd`. Если `node -v` показывает Alpha/preview-сборку, установите стабильную Node.js LTS.
