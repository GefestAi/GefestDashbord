# Запуск OpenClaw Mission Control (без Docker)

## Быстрый старт

```bash
# Запустить все сервисы (токен генерируется автоматически)
./start.sh

# Запустить с конкретным токеном
./start.sh --token "your-secure-token-minimum-50-characters-long-string"

# Справка
./start.sh --help
```

Скрипт автоматически:
- ✅ Проверит зависимости (uv, node, postgresql)
- ✅ Настроит .env файлы (создаст из .example если нужно)
- ✅ Сгенерирует LOCAL_AUTH_TOKEN (или использует существующий)
- ✅ Запустит PostgreSQL (если не запущен)
- ✅ Создаст базу данных mission_control
- ✅ Применит миграции
- ✅ Запустит backend на http://localhost:8000
- ✅ Запустит frontend на http://localhost:3000

После запуска токен авторизации будет выведен в консоли.

```bash
# Остановить все сервисы
./stop.sh
```

После запуска:
- **Frontend**: http://localhost:3000
- **Backend**: http://localhost:8000
- **API Docs**: http://localhost:8000/docs

## Авторизация

**AUTH_MODE**: `local`

### Варианты установки токена:

**1. Автоматическая генерация (по умолчанию)**
```bash
./start.sh
```
Токен генерируется автоматически и сохраняется в [`backend/.env`](backend/.env).

**2. Свой токен через аргумент**
```bash
./start.sh --token "your-secure-token-minimum-50-characters-long-string"
```

**3. Использование существующего токена**
Если токен уже есть в [`backend/.env`](backend/.env), он будет использован автоматически.

После запуска токен выводится в консоли. Введите его в интерфейсе при входе.

Чтобы посмотреть текущий токен:
```bash
grep LOCAL_AUTH_TOKEN backend/.env
```

## Требования

- **PostgreSQL** 16+ (будет запущен автоматически)
- **Python** 3.12+ (через uv)
- **Node.js** 22+
- **uv** (для Python окружения)

PostgreSQL должен быть **установлен**, но не обязательно запущен - скрипт запустит его автоматически.

## Установка зависимостей (первый запуск)

```bash
# Установить uv (если не установлен)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Установить зависимости (опционально, start.sh работает и без этого)
make setup
```

`./start.sh` автоматически настроит окружение при первом запуске.

## Ручной запуск

Если нужно запустить сервисы отдельно:

### Backend
```bash
cd backend
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Frontend
```bash
cd frontend
npm run dev
```

## Настройка

### Backend (.env)
`backend/.env` содержит:
- `DATABASE_URL` - подключение к PostgreSQL
- `CORS_ORIGINS` - разрешенные origins для CORS
- `LOCAL_AUTH_TOKEN` - токен для авторизации
- `BASE_URL` - базовый URL backend

### Frontend (.env)
`frontend/.env` содержит:
- `NEXT_PUBLIC_API_URL=auto` - автоопределение backend URL
- `NEXT_PUBLIC_AUTH_MODE=local` - режим авторизации

## База данных

PostgreSQL должен быть запущен локально:

```bash
# Проверить статус
sudo systemctl status postgresql

# Запустить
sudo systemctl start postgresql

# Проверить подключение
PGPASSWORD=postgres psql -h localhost -U postgres -d mission_control -c "SELECT version();"
```

## Логи

При запуске через `start.sh` логи выводятся в консоль.

## Порты

- **8000** - Backend API
- **3000** - Frontend
- **5432** - PostgreSQL

## Устранение проблем

### Порт занят
```bash
# Найти процесс на порту
lsof -ti:8000
lsof -ti:3000

# Убить процесс
kill $(lsof -ti:8000)
```

### База данных недоступна
```bash
# Создать базу заново
sudo -u postgres psql -c "CREATE DATABASE mission_control;"
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
```

### Обновление зависимостей
```bash
# Backend
cd backend && uv sync

# Frontend
cd frontend && npm install
```

## Разработка

```bash
# Запустить проверки (lint, typecheck, tests)
make check

# Только backend тесты
make backend-test

# Только frontend тесты
make frontend-test

# Регенерировать API клиент (backend должен работать на 8000)
make api-gen
```
