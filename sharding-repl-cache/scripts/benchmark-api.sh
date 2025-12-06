#!/usr/bin/env bash
set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

URL="http://localhost:8080/helloDoc/users"
COUNT=5
INTERVAL=5

log() { echo -e "${BLUE}[●]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; }

# Экранирует строку для отображения в команде (для кавычек, пробелов и т.п.)
shell_escape() {
  printf '%q' "$1"
}

log "🚀 Тестирование API: ${CYAN}${URL}${NC}"
log "Запросов: ${COUNT} | Интервал: ${INTERVAL} сек"

declare -a TIMES

for i in $(seq 1 $COUNT); do
  printf "${BLUE}[%2d/%d]${NC} " "$i" "$COUNT"

  # Формируем и выводим команду
  CURL_CMD="curl -sS -w \"\\\\n\%%{http_code}\\\\n\%%{time_total}\" --connect-timeout 5 --max-time 10 $(shell_escape "$URL")"
  echo -e "Выполняется: ${CYAN}${CURL_CMD}${NC}"

  # Выполняем ту же команду (без echo)
  RESPONSE=$(curl -sS -w "\n%{http_code}\n%{time_total}" \
    --connect-timeout 5 \
    --max-time 10 \
    "$URL" 2>&1) || { error "curl failed: $RESPONSE"; exit 1; }

  # Разбор ответа
  HTTP_BODY=$(echo "$RESPONSE" | sed '$d' | sed '$d')
  HTTP_CODE=$(echo "$RESPONSE" | tail -2 | head -1)
  TIME_SEC=$(echo "$RESPONSE" | tail -1)

  TIME_MS=$(awk -v t="$TIME_SEC" 'BEGIN { printf "%.0f", t*1000 }')

  if [[ "$HTTP_CODE" -eq 200 ]]; then
    success "✅ Ответ: HTTP ${HTTP_CODE}, время: ${TIME_MS} мс"
    TIMES+=("$TIME_SEC")
  else
    error "❌ Ответ: HTTP ${HTTP_CODE}, время: ${TIME_MS} мс"
    # Опционально: вывод тела при ошибке
    if [[ -n "$HTTP_BODY" ]] && [[ "$HTTP_BODY" != "{}" ]] && [[ "$HTTP_BODY" != "[]" ]]; then
      echo "   Тело ответа: $(echo "$HTTP_BODY" | tr '\n' ' ' | head -c 100)${NC}"
    fi
  fi

  # Ждём перед следующим (кроме последнего)
  if [[ $i -lt $COUNT ]]; then
    printf "${BLUE}[⏳]${NC} Ожидание ${INTERVAL} сек...\n"
    sleep "$INTERVAL"
  fi
done

echo
log "📊 Статистика (успешные запросы):"

if [[ ${#TIMES[@]} -eq 0 ]]; then
  error "Ни один запрос не завершился успешно."
  exit 1
fi

read -r MIN MAX AVG <<< $(printf "%s\n" "${TIMES[@]}" | awk '
  BEGIN { min=1e9; max=0; sum=0; n=0 }
  {
    t = $1;
    if (t < min) min = t;
    if (t > max) max = t;
    sum += t;
    n++;
  }
  END {
    avg = (n > 0) ? sum/n : 0;
    printf "%.3f %.3f %.3f", min, max, avg
  }
')

MIN_MS=$(awk -v t="$MIN" 'BEGIN { printf "%.0f", t*1000 }')
MAX_MS=$(awk -v t="$MAX" 'BEGIN { printf "%.0f", t*1000 }')
AVG_MS=$(awk -v t="$AVG" 'BEGIN { printf "%.0f", t*1000 }')

printf "   Минимум: %6s мс (%.3f с)\n" "$MIN_MS" "$MIN"
printf "   Максимум: %6s мс (%.3f с)\n" "$MAX_MS" "$MAX"
printf "   Среднее:  %6s мс (%.3f с)\n" "$AVG_MS" "$AVG"
echo

success "✅ Тестирование завершено."