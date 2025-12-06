#!/usr/bin/env bash
set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}[●]${NC} $1"
}

success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[⚠]${NC} $1"
}

error() {
  echo -e "${RED}[✗]${NC} $1" >&2
}

# Функция для выполнения mongosh-команды в контейнере
run_mongo() {
  local container="$1"
  local port="$2"
  local js_cmd="$3"
  docker compose exec -T "$container" mongosh --port "$port" --quiet --eval "$js_cmd" 2>/dev/null | tr -d '\r'
}

# === 1. Общее количество документов через mongos ===
log "1. Запрос общего количества документов через mongos_router..."
TOTAL=$(run_mongo "mongos_router" "27020" "db.getSiblingDB('somedb').helloDoc.countDocuments()")
success "Общее количество документов в кластере: ${CYAN}${TOTAL}${NC}"

echo

# === 2. Данные на шарде 1 (shard1 replica set) ===
log "2. Проверка данных на шарде shard1 (replica set 'shard1')..."

declare -A SHARD1_COUNTS
for i in 1 2 3; do
  container="shard1_${i}"
  port=$((27020 + i))
  count=$(run_mongo "$container" "$port" "db.getSiblingDB('somedb').helloDoc.countDocuments()" || echo "-1")
  SHARD1_COUNTS[$i]=$count
  if [[ "$count" == "-1" ]]; then
    error "  shard1_${i}: недоступен"
  elif [[ "$count" == "0" ]]; then
    warn "  shard1_${i}: ${count} документов"
  else
    success "  shard1_${i}: ${CYAN}${count}${NC} документов"
  fi
done

# Анализ: все ли реплики синхронизированы?
unique_counts1=($(printf '%s\n' "${SHARD1_COUNTS[@]}" | sort -u | grep -v -- "-1"))
if [[ ${#unique_counts1[@]} -eq 1 ]] && [[ "${unique_counts1[0]}" != "-1" ]]; then
  success "→ Все реплики shard1 синхронизированы: ${unique_counts1[0]} документов"
elif [[ ${#unique_counts1[@]} -eq 0 ]]; then
  error "→ Все ноды shard1 недоступны"
else
  warn "→ Расхождение в данных на репликах shard1: (${unique_counts1[*]})"
fi

echo

# === 3. Данные на шарде 2 (shard2 replica set) ===
log "3. Проверка данных на шарде shard2 (replica set 'shard2')..."

declare -A SHARD2_COUNTS
for i in 1 2 3; do
  container="shard2_${i}"
  port=$((27030 + i))
  count=$(run_mongo "$container" "$port" "db.getSiblingDB('somedb').helloDoc.countDocuments()" || echo "-1")
  SHARD2_COUNTS[$i]=$count
  if [[ "$count" == "-1" ]]; then
    error "  shard2_${i}: недоступен"
  elif [[ "$count" == "0" ]]; then
    warn "  shard2_${i}: ${count} документов"
  else
    success "  shard2_${i}: ${CYAN}${count}${NC} документов"
  fi
done

unique_counts2=($(printf '%s\n' "${SHARD2_COUNTS[@]}" | sort -u | grep -v -- "-1"))
if [[ ${#unique_counts2[@]} -eq 1 ]] && [[ "${unique_counts2[0]}" != "-1" ]]; then
  success "→ Все реплики shard2 синхронизированы: ${unique_counts2[0]} документов"
elif [[ ${#unique_counts2[@]} -eq 0 ]]; then
  error "→ Все ноды shard2 недоступны"
else
  warn "→ Расхождение в данных на репликах shard2: (${unique_counts2[*]})"
fi

echo

# === 4. Проверка через API ===
log "4. Запрос количества документов через API (/helloDoc/count)..."
API_TOTAL=$(curl -s http://localhost:8080/helloDoc/count 2>/dev/null || echo "error")

if [[ "$API_TOTAL" == "error" ]]; then
  error "→ API недоступен (порт 8080)"
elif [[ "$API_TOTAL" == "$TOTAL" ]]; then
  success "→ API вернул корректное значение: ${CYAN}${API_TOTAL}${NC}"
else
  warn "→ Расхождение: API=${API_TOTAL}, mongos=${TOTAL}"
fi

echo

# === 5. Итоговый анализ распределения ===
log "5. Анализ распределения данных по шардам..."

shard1_docs=${unique_counts1[0]:-0}
shard2_docs=${unique_counts2[0]:-0}

# Приводим к числам
shard1_docs=$((shard1_docs == -1 ? 0 : shard1_docs))
shard2_docs=$((shard2_docs == -1 ? 0 : shard2_docs))
sum_local=$((shard1_docs + shard2_docs))

if [[ "$sum_local" -eq "$TOTAL" ]]; then
  success "✅ Согласованность данных подтверждена:"
  printf "   shard1: %s\n   shard2: %s\n   Итого:  %s = mongos (%s)\n" \
    "${CYAN}${shard1_docs}${NC}" \
    "${CYAN}${shard2_docs}${NC}" \
    "${GREEN}${sum_local}${NC}" \
    "${CYAN}${TOTAL}${NC}"
else
  warn "⚠️  Несоответствие: сумма по шардам ($sum_local) ≠ mongos ($TOTAL)"
  printf "   Возможно: данные ещё реплицируются, шардинг не включён, или часть документов в 'orphaned chunks'.\n"
fi

echo
log "Проверка завершена."