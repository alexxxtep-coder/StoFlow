# Интеграции

## Parts.Finder
Первый режим — ручное создание предложения и импорт CSV. Каждое предложение хранит source_type, source_reference, observed_at, цену/валюту, наличие, ETA и статус применимости.

## SupplierAdapter contract (проектное решение)
- `searchParts(vehicle, query)`
- `getOfferDetails(externalOfferId)`
- `checkAvailability(externalOfferId)`
- `createSupplierOrder(approvedOffer)`
- `getOrderStatus(externalOrderId)`
- `cancelSupplierOrder(externalOrderId)` — только если поддерживается API.

Адаптеры ARMTEK, Шате-М, AUTO1, Проценка и других поставщиков не включаются без официальной документации, договора/доступа и реальных тестовых ответов. Не использовать обход авторизации и недокументированный парсинг кабинетов.

## Коммуникации
Telegram/Viber/WhatsApp/email/телефония — только официальные API. Пока канал не подключён, событие остаётся внутренней заметкой/черновиком, а не «отправленным сообщением».

## AI
Провайдер-agnostic серверный адаптер. Доступ к инструментам проверяет tenant и permissions. Любое изменение заказа, цены, брони, платежа или закупки требует подтверждения.
