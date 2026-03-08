#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

info "Остановка OpenClaw Mission Control..."

# Остановка backend
if [ -f "$SCRIPT_DIR/.backend.pid" ]; then
    BACKEND_PID=$(cat "$SCRIPT_DIR/.backend.pid")
    if kill -0 "$BACKEND_PID" 2>/dev/null; then
        kill "$BACKEND_PID"
        info "Backend остановлен (PID: $BACKEND_PID)"
    else
        info "Backend процесс не найден"
    fi
    rm -f "$SCRIPT_DIR/.backend.pid"
else
    info "Backend не был запущен через start.sh"
fi

# Остановка frontend
if [ -f "$SCRIPT_DIR/.frontend.pid" ]; then
    FRONTEND_PID=$(cat "$SCRIPT_DIR/.frontend.pid")
    if kill -0 "$FRONTEND_PID" 2>/dev/null; then
        kill "$FRONTEND_PID"
        info "Frontend остановлен (PID: $FRONTEND_PID)"
    else
        info "Frontend процесс не найден"
    fi
    rm -f "$SCRIPT_DIR/.frontend.pid"
else
    info "Frontend не был запущен через start.sh"
fi

# Дополнительная очистка процессов на портах 8000 и 3000
for port in 8000 3000; do
    PID=$(lsof -ti:$port 2>/dev/null || true)
    if [ -n "$PID" ]; then
        kill $PID 2>/dev/null || true
        info "Остановлен процесс на порту $port (PID: $PID)"
    fi
done

# Удаляем временный файл с токеном
if [ -f "$SCRIPT_DIR/.auth_token" ]; then
    rm -f "$SCRIPT_DIR/.auth_token"
fi

info "Все сервисы остановлены"
