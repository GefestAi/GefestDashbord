#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Переменные
USER_TOKEN=""

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Помощь
usage() {
    cat <<EOF
Использование: $0 [опции]

Опции:
  --token <TOKEN>    Использовать указанный LOCAL_AUTH_TOKEN (минимум 50 символов)
  -h, --help         Показать эту справку

Примеры:
  $0                                    # Автоматическая генерация токена
  $0 --token "your-secure-token-here"   # Использовать свой токен

EOF
    exit 0
}

# Парсинг аргументов
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --token)
                if [[ $# -lt 2 || -z ${2:-} ]]; then
                    error "Не указано значение для --token"
                    exit 1
                fi
                USER_TOKEN="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                error "Неизвестный аргумент: $1"
                usage
                ;;
        esac
    done
    
    # Проверка длины токена если указан
    if [ -n "$USER_TOKEN" ] && [ ${#USER_TOKEN} -lt 50 ]; then
        error "LOCAL_AUTH_TOKEN должен быть минимум 50 символов (передано: ${#USER_TOKEN})"
        exit 1
    fi
}

# Генерация токена
generate_token() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 32
    else
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64
    fi
}

# Проверка зависимостей
check_dependencies() {
    info "Проверка зависимостей..."
    
    if ! command -v uv &> /dev/null; then
        error "uv не установлен. Установите: curl -LsSf https://astral.sh/uv/install.sh | sh"
        exit 1
    fi
    
    if ! command -v node &> /dev/null; then
        error "Node.js не установлен"
        exit 1
    fi
    
    if ! command -v psql &> /dev/null; then
        error "PostgreSQL не установлен"
        exit 1
    fi
}

# Настройка .env файлов
setup_env_files() {
    info "Настройка конфигурационных файлов..."
    
    # Создаём backend/.env если не существует
    if [ ! -f "$SCRIPT_DIR/backend/.env" ]; then
        if [ -f "$SCRIPT_DIR/backend/.env.example" ]; then
            cp "$SCRIPT_DIR/backend/.env.example" "$SCRIPT_DIR/backend/.env"
            info "Создан backend/.env из .env.example"
        else
            error "Не найден backend/.env.example"
            exit 1
        fi
    fi
    
    # Создаём frontend/.env если не существует
    if [ ! -f "$SCRIPT_DIR/frontend/.env" ]; then
        if [ -f "$SCRIPT_DIR/frontend/.env.example" ]; then
            cp "$SCRIPT_DIR/frontend/.env.example" "$SCRIPT_DIR/frontend/.env"
            info "Создан frontend/.env из .env.example"
        fi
    fi
    
    # Проверяем и устанавливаем LOCAL_AUTH_TOKEN
    local current_token=""
    if grep -q "^LOCAL_AUTH_TOKEN=" "$SCRIPT_DIR/backend/.env" 2>/dev/null; then
        current_token=$(grep "^LOCAL_AUTH_TOKEN=" "$SCRIPT_DIR/backend/.env" | cut -d'=' -f2-)
    fi
    
    local final_token=""
    
    # Если передан токен через аргумент - используем его
    if [ -n "$USER_TOKEN" ]; then
        info "Использование токена из аргументов командной строки"
        final_token="$USER_TOKEN"
    # Если есть валидный токен в .env - используем его
    elif [ -n "$current_token" ] && [ ${#current_token} -ge 50 ]; then
        info "Использование существующего LOCAL_AUTH_TOKEN из backend/.env"
        final_token="$current_token"
    # Иначе генерируем новый
    else
        info "Генерация нового LOCAL_AUTH_TOKEN..."
        final_token=$(generate_token)
        info "Новый токен сгенерирован"
    fi
    
    # Обновляем в backend/.env
    if grep -q "^LOCAL_AUTH_TOKEN=" "$SCRIPT_DIR/backend/.env"; then
        sed -i "s|^LOCAL_AUTH_TOKEN=.*|LOCAL_AUTH_TOKEN=$final_token|" "$SCRIPT_DIR/backend/.env"
    else
        echo "LOCAL_AUTH_TOKEN=$final_token" >> "$SCRIPT_DIR/backend/.env"
    fi
    
    echo "$final_token" > "$SCRIPT_DIR/.auth_token"
    
    # Убеждаемся что AUTH_MODE=local
    if grep -q "^AUTH_MODE=" "$SCRIPT_DIR/backend/.env"; then
        sed -i "s|^AUTH_MODE=.*|AUTH_MODE=local|" "$SCRIPT_DIR/backend/.env"
    else
        echo "AUTH_MODE=local" >> "$SCRIPT_DIR/backend/.env"
    fi
    
    # Устанавливаем BASE_URL если пустой
    if ! grep -q "^BASE_URL=http" "$SCRIPT_DIR/backend/.env"; then
        sed -i "s|^BASE_URL=.*|BASE_URL=http://localhost:8000|" "$SCRIPT_DIR/backend/.env"
    fi
    
    # Устанавливаем CORS_ORIGINS
    if ! grep -q "^CORS_ORIGINS=.*localhost:3000" "$SCRIPT_DIR/backend/.env"; then
        sed -i "s|^CORS_ORIGINS=.*|CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000,http://0.0.0.0:3000|" "$SCRIPT_DIR/backend/.env"
    fi
}

# Запуск PostgreSQL
start_postgres() {
    info "Проверка PostgreSQL..."
    
    # Проверяем, запущен ли PostgreSQL
    if systemctl is-active --quiet postgresql 2>/dev/null || systemctl is-active --quiet postgresql@16-main 2>/dev/null; then
        info "PostgreSQL уже запущен"
    else
        info "Запуск PostgreSQL..."
        if command -v systemctl &> /dev/null; then
            sudo systemctl start postgresql || sudo systemctl start postgresql@16-main
            sleep 2
            info "PostgreSQL запущен"
        else
            error "systemctl не найден. Запустите PostgreSQL вручную"
            exit 1
        fi
    fi
    
    # Ждём пока PostgreSQL будет готов
    for i in {1..10}; do
        if sudo -u postgres psql -c "SELECT 1" &> /dev/null; then
            info "PostgreSQL готов к работе"
            break
        fi
        if [ $i -eq 10 ]; then
            error "PostgreSQL не отвечает"
            exit 1
        fi
        sleep 1
    done
    
    # Создаём базу данных если не существует
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw mission_control; then
        info "База данных mission_control уже существует"
    else
        info "Создание базы данных mission_control..."
        sudo -u postgres psql -c "CREATE DATABASE mission_control;"
        info "База данных создана"
    fi
    
    # Устанавливаем пароль для пользователя postgres если нужно
    sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';" &> /dev/null || true
}

# Проверка PostgreSQL
check_postgres() {
    info "Проверка подключения к PostgreSQL..."
    
    if ! PGPASSWORD=postgres psql -h localhost -U postgres -d mission_control -c "SELECT 1" &> /dev/null; then
        error "Не удается подключиться к базе данных mission_control"
        error "Убедитесь, что PostgreSQL запущен и база создана"
        exit 1
    fi
    
    info "PostgreSQL работает корректно"
}

# Применение миграций
run_migrations() {
    info "Применение миграций базы данных..."
    cd "$SCRIPT_DIR/backend"
    uv run alembic upgrade head
    cd "$SCRIPT_DIR"
}

# Запуск backend
start_backend() {
    info "Запуск backend на http://localhost:8000..."
    cd "$SCRIPT_DIR/backend"
    uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload &
    BACKEND_PID=$!
    echo $BACKEND_PID > "$SCRIPT_DIR/.backend.pid"
    cd "$SCRIPT_DIR"
    
    # Ожидание запуска backend
    for i in {1..30}; do
        if curl -s http://localhost:8000/healthz > /dev/null 2>&1; then
            info "Backend успешно запущен (PID: $BACKEND_PID)"
            return 0
        fi
        sleep 1
    done
    
    warn "Backend запущен, но healthcheck не отвечает"
}

# Запуск frontend
start_frontend() {
    info "Запуск frontend на http://localhost:3000..."
    cd "$SCRIPT_DIR/frontend"
    npm run dev &
    FRONTEND_PID=$!
    echo $FRONTEND_PID > "$SCRIPT_DIR/.frontend.pid"
    cd "$SCRIPT_DIR"
    
    info "Frontend запущен (PID: $FRONTEND_PID)"
}

# Обработка остановки
cleanup() {
    echo ""
    warn "Остановка сервисов..."
    
    if [ -f "$SCRIPT_DIR/.backend.pid" ]; then
        BACKEND_PID=$(cat "$SCRIPT_DIR/.backend.pid")
        if kill -0 "$BACKEND_PID" 2>/dev/null; then
            kill "$BACKEND_PID"
            info "Backend остановлен"
        fi
        rm -f "$SCRIPT_DIR/.backend.pid"
    fi
    
    if [ -f "$SCRIPT_DIR/.frontend.pid" ]; then
        FRONTEND_PID=$(cat "$SCRIPT_DIR/.frontend.pid")
        if kill -0 "$FRONTEND_PID" 2>/dev/null; then
            kill "$FRONTEND_PID"
            info "Frontend остановлен"
        fi
        rm -f "$SCRIPT_DIR/.frontend.pid"
    fi
    parse_args "$@"
    
    
    exit 0
}

trap cleanup SIGINT SIGTERM

# Основной процесс
main() {
    info "Запуск OpenClaw Mission Control..."
    
    check_dependencies
    setup_env_files
    start_postgres
    check_postgres
    run_migrations
    start_backend
    start_frontend
    
    # Читаем токен из файла
    local auth_token=""
    if [ -f "$SCRIPT_DIR/.auth_token" ]; then
        auth_token=$(cat "$SCRIPT_DIR/.auth_token")
    fi
    
    echo ""
    info "================================"
    info "Сервисы запущены:"
    info "  Frontend: http://localhost:3000"
    info "  Backend:  http://localhost:8000"
    info "  API Docs: http://localhost:8000/docs"
    info ""
    if [ -n "$auth_token" ]; then
        info "LOCAL_AUTH_TOKEN: $auth_token"
    fi
    info "================================"
    echo ""
    info "Нажмите Ctrl+C для остановки"
    
    # Ожидание
    wait
}

main "$@"
