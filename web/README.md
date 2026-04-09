# ByteAway Web

React + Vite фронт для клиентов и B2B.

## Запуск
```bash
cd web
npm install
npm run dev # http://localhost:5173
```

По умолчанию все запросы на `/api` проксируются на `http://localhost:3000` (мастер-нода). Можно задать `VITE_MASTER_NODE_URL`:
```bash
VITE_MASTER_NODE_URL=http://127.0.0.1:3000 npm run dev
```

## Страницы
- `/` – лендинг для клиентов.
- `/how-it-works` – описание архитектуры.
- `/download` – как получить APK.
- `/business` – ЛК B2B: ввод Bearer токена, просмотр баланса, создание и перечень API ключей.

## Привязка к мастер-ноде
- Баланс: `GET /api/v1/balance` (требует Bearer).
- Креды: `POST /api/v1/business/proxy-credentials`, `GET /api/v1/business/proxy-credentials`.

## Прод
```bash
npm run build
npm run preview
```
Собранный билд в `web/dist/` можно раздавать через Nginx рядом с мастер-нодой, проксируя `/api` на Rust сервис.

### Важно для продакшена
- В проде нужно отдавать именно `web/dist/`.
- Не используйте `web/index.html` из исходников: он подключает `/src/main.tsx` и в Nginx это часто приводит к ошибке MIME (`application/octet-stream`) и серому экрану.
- APK и update manifest должны лежать в одном каталоге `/downloads/`:
	- `/downloads/byteaway-release.apk`
	- `/downloads/android.json`
