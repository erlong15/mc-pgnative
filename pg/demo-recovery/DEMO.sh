#!/bin/bash
#
# Демонстрация восстановления CloudNativePG из бэкапа
#
# Сценарии:
#   1. Подготовка тестовых данных
#   2. PITR - восстановление на точку в прошлом в новый кластер
#   3. Disaster Recovery - полное восстановление кластера
#   4. Полная демонстрация (все сценарии)
#

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Переменная для хранения времени PITR
PITR_TIME=""

print_header() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

print_step() {
    echo ""
    echo -e "${GREEN}=== $1 ===${NC}"
}

print_warning() {
    echo -e "${YELLOW}ВНИМАНИЕ: $1${NC}"
}

print_error() {
    echo -e "${RED}ОШИБКА: $1${NC}"
}

show_menu() {
    print_header "CloudNativePG Recovery Demo"
    echo ""
    echo "Выберите сценарий:"
    echo ""
    echo "  1) PITR Demo - полная демонстрация Point-in-Time Recovery"
    echo "     (подготовка данных + восстановление из WAL)"
    echo ""
    echo "  2) Disaster Recovery - восстановление при полной потере"
    echo ""
    echo "  3) Полная демонстрация (PITR + Disaster Recovery)"
    echo ""
    echo "  4) Очистка - удалить PITR кластер"
    echo "  5) Статус - показать состояние кластеров"
    echo ""
    echo "  0) Выход"
    echo ""
}

check_cluster() {
    if ! kubectl get cluster cluster-example &>/dev/null; then
        print_error "Кластер cluster-example не найден!"
        echo "Сначала создайте кластер или выполните Disaster Recovery"
        return 1
    fi
    return 0
}

# ============================================
# СЦЕНАРИЙ 1: PITR Demo (полный цикл)
# ============================================
run_pitr_demo() {
    print_header "PITR Demo - Point-in-Time Recovery"
    echo "Демонстрация восстановления на точку между бэкапами (из WAL)"
    echo ""

    check_cluster || return 1

    # ШАГ 1: Подготовка данных
    print_step "ШАГ 1: Создаём начальные данные"
    kubectl cnpg psql cluster-example -- -c "
CREATE TABLE IF NOT EXISTS important_data (
    id SERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
DELETE FROM important_data;
INSERT INTO important_data (data) VALUES ('Начальные данные - строка 1');
INSERT INTO important_data (data) VALUES ('Начальные данные - строка 2');
SELECT * FROM important_data;
"

    # ШАГ 2: Бэкап
    print_step "ШАГ 2: Создаём бэкап (базовая точка)"
    kubectl cnpg backup cluster-example --method plugin --plugin-name barman-cloud.cloudnative-pg.io
    echo "Ожидаем завершения бэкапа..."
    sleep 15
    kubectl get backup -l cnpg.io/cluster=cluster-example --sort-by=.metadata.creationTimestamp | tail -3

    # Получаем serverName из кластера, если не задан - используем имя кластера
    PITR_SERVER=$(kubectl get cluster cluster-example -o jsonpath='{.spec.plugins[0].parameters.serverName}' 2>/dev/null)
    PITR_SERVER="${PITR_SERVER:-cluster-example}"

    # ШАГ 3: Вставка данных после бэкапа
    print_step "ШАГ 3: Вставляем 10 строк ПОСЛЕ бэкапа"
    echo ""
    echo -e "${YELLOW}Каждая строка записывается в WAL с уникальным временем${NC}"
    echo ""

    for i in $(seq 1 10); do
        kubectl cnpg psql cluster-example -- -c "INSERT INTO important_data (data) VALUES ('WAL строка $i - после бэкапа');" 2>/dev/null

        INSERT_TIME=$(kubectl cnpg psql cluster-example -- -t -c "SELECT created_at FROM important_data ORDER BY id DESC LIMIT 1;" 2>/dev/null | tr -d ' \n')
        echo "  Строка $i: $INSERT_TIME"

        # Сохраняем время после 5-й строки
        if [ "$i" -eq 5 ]; then
            # Формат: "YYYY-MM-DD HH:MM:SS+00" (RFC 3339 с пробелом)
            PITR_TIME=$(kubectl cnpg psql cluster-example -- -t -A -c "SELECT to_char(created_at + interval '1 second', 'YYYY-MM-DD HH24:MI:SS')||'+00' FROM important_data ORDER BY id DESC LIMIT 1;" 2>/dev/null)
            # Убираем все пробелы и переносы в начале/конце
            PITR_TIME=$(echo "$PITR_TIME" | tr -d '\n\r' | sed 's/^ *//;s/ *$//')
            echo ""
            echo -e "  ${GREEN}>>> Точка восстановления (после строки 5): $PITR_TIME${NC}"
            echo ""
        fi

        sleep 2
    done

    # ШАГ 4: Ждём архивирования WAL
    print_step "ШАГ 4: Ждём архивирования WAL (30 сек)"
    sleep 30

    print_step "Итоговые данные в базе (12 строк)"
    kubectl cnpg psql cluster-example -- -c "SELECT id, data, created_at FROM important_data ORDER BY id;"

    echo ""
    read -p "Нажмите Enter для запуска PITR восстановления..."

    # ШАГ 5: PITR восстановление
    print_step "ШАГ 5: Создаём PITR кластер на время $PITR_TIME"

    # Удаляем старый PITR кластер если есть
    if kubectl get cluster cluster-example-pitr &>/dev/null; then
        print_warning "Удаляем существующий PITR кластер..."
        kubectl delete cluster cluster-example-pitr --wait=true
    fi

    echo "ServerName: $PITR_SERVER"

    cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: cluster-example-pitr
spec:
  instances: 1
  bootstrap:
    recovery:
      source: backup-source
      database: app
      owner: app
      secret:
        name: app-secret
      recoveryTarget:
        targetTime: "$PITR_TIME"
  externalClusters:
    - name: backup-source
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: yandex-backup-store
          serverName: $PITR_SERVER
  storage:
    pvcTemplate:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
EOF

    print_step "ШАГ 6: Ожидаем восстановления (до 5 минут)"
    echo "Следить за прогрессом: kubectl get pods -l cnpg.io/cluster=cluster-example-pitr -w"

    if kubectl wait --for=condition=Ready cluster/cluster-example-pitr --timeout=300s; then
        echo -e "${GREEN}PITR кластер готов!${NC}"
    else
        print_warning "Таймаут ожидания. Проверьте логи."
        return 1
    fi

    # ШАГ 7: Сравнение результатов
    print_step "ШАГ 7: Сравнение данных"

    echo ""
    echo -e "${YELLOW}=== PITR кластер (должно быть 7 строк: 2 начальные + 5 WAL) ===${NC}"
    kubectl cnpg psql cluster-example-pitr -- -c "SELECT id, data FROM important_data ORDER BY id;" || true

    echo ""
    echo -e "${YELLOW}=== Оригинальный кластер (все 12 строк) ===${NC}"
    kubectl cnpg psql cluster-example -- -c "SELECT id, data FROM important_data ORDER BY id;" || true

    echo ""
    print_header "PITR Demo завершена!"
    echo ""
    echo "Результат:"
    echo "  - Бэкап содержал только 2 строки"
    echo "  - Строки 3-7 восстановлены из WAL архива"
    echo "  - Строки 8-12 НЕ восстановлены (были после точки PITR)"
}

# ============================================
# СЦЕНАРИЙ 3: DISASTER RECOVERY
# ============================================
run_disaster_recovery() {
    print_header "Disaster Recovery"

    print_warning "Этот сценарий УДАЛИТ текущий кластер cluster-example!"
    echo ""
    read -p "Продолжить? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Отменено."
        return
    fi

    print_step "Удаляем кластер cluster-example"
    kubectl delete cluster cluster-example --wait=false || true
    kubectl delete pvc -l cnpg.io/cluster=cluster-example --wait=false || true

    print_step "Ждём полного удаления (30 сек)"
    sleep 30

    print_step "Восстанавливаем кластер из бэкапа"
    # Генерируем уникальное имя serverName чтобы избежать конфликта с существующими WAL
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    sed "s/cluster-example-restored/cluster-example-dr-${TIMESTAMP}/" "$(dirname "$0")/02-disaster-recovery.yaml" | kubectl apply -f -
    echo "Используем serverName: cluster-example-dr-${TIMESTAMP}"

    print_step "Ожидаем восстановления (до 10 минут)"
    echo "Можно следить за прогрессом:"
    echo "  kubectl get pods -l cnpg.io/cluster=cluster-example -w"
    echo "  kubectl logs -l cnpg.io/cluster=cluster-example -c full-recovery -f"

    if kubectl wait --for=condition=Ready cluster/cluster-example --timeout=600s; then
        echo -e "${GREEN}Кластер восстановлен!${NC}"
    else
        print_warning "Таймаут ожидания. Проверьте логи."
    fi

    print_step "Статус восстановленного кластера"
    kubectl cnpg status cluster-example

    print_step "Проверяем данные"
    kubectl cnpg psql cluster-example -- -c "SELECT * FROM important_data ORDER BY id;" || true

    echo ""
    echo -e "${GREEN}Disaster Recovery завершен!${NC}"
}

# ============================================
# ПОЛНАЯ ДЕМОНСТРАЦИЯ
# ============================================
run_full_demo() {
    print_header "Полная демонстрация"

    run_pitr_demo

    echo ""
    read -p "Нажмите Enter для демо Disaster Recovery..."
    run_disaster_recovery

    print_header "Демонстрация завершена!"
}

# ============================================
# ОЧИСТКА
# ============================================
cleanup() {
    print_header "Очистка"

    if kubectl get cluster cluster-example-pitr &>/dev/null; then
        read -p "Удалить PITR кластер cluster-example-pitr? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete cluster cluster-example-pitr
            echo "PITR кластер удалён"
        fi
    else
        echo "PITR кластер не найден"
    fi

    rm -f /tmp/pitr_time.txt /tmp/pitr_server.txt
}

# ============================================
# СТАТУС
# ============================================
show_status() {
    print_header "Статус кластеров"

    echo ""
    echo "=== Кластеры ==="
    kubectl get clusters

    echo ""
    echo "=== Бэкапы ==="
    kubectl get backups --sort-by=.metadata.creationTimestamp | tail -10

    echo ""
    echo "=== cluster-example ==="
    if kubectl get cluster cluster-example &>/dev/null; then
        kubectl cnpg status cluster-example 2>/dev/null | head -30
    else
        echo "Кластер не найден"
    fi
}

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
main() {
    # Если передан аргумент, выполняем соответствующий сценарий
    case "${1:-}" in
        pitr|1)
            run_pitr_demo
            exit 0
            ;;
        dr|disaster|2)
            run_disaster_recovery
            exit 0
            ;;
        full|all|3)
            run_full_demo
            exit 0
            ;;
        cleanup|4)
            cleanup
            exit 0
            ;;
        status|5)
            show_status
            exit 0
            ;;
    esac

    # Интерактивное меню
    while true; do
        show_menu
        read -p "Выберите опцию [0-5]: " choice

        case $choice in
            1) run_pitr_demo ;;
            2) run_disaster_recovery ;;
            3) run_full_demo ;;
            4) cleanup ;;
            5) show_status ;;
            0)
                echo "До свидания!"
                exit 0
                ;;
            *)
                print_error "Неверный выбор"
                ;;
        esac

        echo ""
        read -p "Нажмите Enter для возврата в меню..."
    done
}

main "$@"
