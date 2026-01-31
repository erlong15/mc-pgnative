# Демонстрация восстановления CloudNativePG

Скрипты для демонстрации двух сценариев восстановления PostgreSQL из бэкапа.

## Предварительные требования

- Работающий кластер `cluster-example`
- Настроенный ObjectStore `yandex-backup-store`
- Secret `app-secret` с credentials для БД
- Успешные бэкапы (проверить: `kubectl cnpg status cluster-example`)

## Сценарии

### Сценарий 1: Disaster Recovery (полная потеря базы)

Восстановление кластера с тем же именем после полного удаления.

**Когда использовать:**
- Полная потеря данных кластера
- Восстановление после катастрофы
- Миграция в другой namespace/кластер K8s

### Сценарий 2: Point-in-Time Recovery (PITR)

Восстановление на определённый момент времени в НОВЫЙ кластер рядом.

**Когда использовать:**
- Случайное удаление данных (DELETE/DROP)
- Откат неудачной миграции
- Анализ состояния БД в прошлом
- Форензика и аудит

## Быстрый старт

### Интерактивный режим

```bash
cd pg/demo-recovery
./DEMO.sh
```

Откроется меню выбора сценария:
```
1) PITR Demo - полная демонстрация Point-in-Time Recovery
2) Disaster Recovery - восстановление при полной потере
3) Полная демонстрация (PITR + Disaster Recovery)
4) Очистка - удалить PITR кластер
5) Статус - показать состояние кластеров
0) Выход
```

### Запуск конкретного сценария

```bash
./DEMO.sh pitr       # PITR демонстрация (полный цикл)
./DEMO.sh dr         # Disaster Recovery
./DEMO.sh full       # Полная демонстрация
./DEMO.sh status     # Показать статус
./DEMO.sh cleanup    # Очистка
```

### PITR Demo (восстановление из WAL)

Сценарий `./DEMO.sh pitr` выполняет полный цикл:

1. Создаёт 2 начальные строки
2. Делает бэкап
3. Вставляет 10 строк **после бэкапа** с паузами
4. Сохраняет время после 5-й строки
5. Создаёт PITR кластер на это время
6. Показывает результат

**Результат:**
- PITR кластер: 7 строк (2 из бэкапа + 5 из WAL)
- Оригинал: 12 строк
- Строки 8-12 **не восстановились** — они были после точки PITR

### Ручной запуск

#### Шаг 1: Подготовка тестовых данных

```bash
# Создаём тестовую таблицу
kubectl cnpg psql cluster-example -- -c "
CREATE TABLE IF NOT EXISTS important_data (
    id SERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
INSERT INTO important_data (data) VALUES ('Важные данные');
SELECT * FROM important_data;
"

# Запоминаем время для PITR
date -u +"%Y-%m-%d %H:%M:%S+00"
```

#### Шаг 2: Создание бэкапа

```bash
kubectl cnpg backup cluster-example \
  --method plugin \
  --plugin-name barman-cloud.cloudnative-pg.io

# Проверяем статус
kubectl get backup -l cnpg.io/cluster=cluster-example
```

#### Шаг 3a: PITR в новый кластер

```bash
# Редактируем targetTime в манифесте
vi 03-pitr-new-cluster.yaml

# Применяем
kubectl apply -f 03-pitr-new-cluster.yaml

# Ждём готовности
kubectl wait --for=condition=Ready cluster/cluster-example-pitr --timeout=300s

# Проверяем данные
kubectl cnpg psql cluster-example-pitr -- -c "SELECT * FROM important_data;"
```

#### Шаг 3b: Disaster Recovery

```bash
# ВНИМАНИЕ: Удаляет кластер!
kubectl delete cluster cluster-example
kubectl delete pvc -l cnpg.io/cluster=cluster-example

# Ждём удаления
sleep 30

# Восстанавливаем
kubectl apply -f 02-disaster-recovery.yaml

# Ждём готовности
kubectl wait --for=condition=Ready cluster/cluster-example --timeout=600s

# Проверяем
kubectl cnpg status cluster-example
kubectl cnpg psql cluster-example -- -c "SELECT * FROM important_data;"
```

## Файлы

| Файл | Описание |
|------|----------|
| `DEMO.sh` | Интерактивный скрипт полной демонстрации |
| `01-setup-testdata.sql` | SQL для создания тестовых данных |
| `02-disaster-recovery.yaml` | Манифест Disaster Recovery |
| `03-pitr-new-cluster.yaml` | Манифест PITR в новый кластер |

## Формат времени для PITR

`recoveryTarget.targetTime` принимает формат RFC 3339:

```
2026-01-24 21:20:00+03      # С часовым поясом MSK
2026-01-24 18:20:00+00      # UTC
2026-01-24T18:20:00Z        # ISO формат
```

## Очистка после демо

```bash
# Удалить PITR кластер
kubectl delete cluster cluster-example-pitr

# Удалить старые бэкапы (опционально)
kubectl delete backup -l cnpg.io/cluster=cluster-example
```

## Troubleshooting

**Ошибка "no backup section":**
```bash
# Используйте method plugin
kubectl cnpg backup cluster-example --method plugin --plugin-name barman-cloud.cloudnative-pg.io
```

**Ошибка "Expected empty archive":**

При Disaster Recovery barman-cloud проверяет, что WAL архив пустой. Если там уже есть WAL от предыдущего восстановления, оно падает.

**Решение:** Каждое восстановление должно использовать **уникальный** `serverName`:
```yaml
plugins:
- name: barman-cloud.cloudnative-pg.io
  isWALArchiver: true
  parameters:
    barmanObjectName: yandex-backup-store
    serverName: cluster-example-dr-20260124  # Уникальное имя с датой!
```

**Автоматически с timestamp:**
```bash
TIMESTAMP=$(date +%Y%m%d%H%M%S)
sed "s/cluster-example-restored/cluster-example-dr-${TIMESTAMP}/" 02-disaster-recovery.yaml | kubectl apply -f -
```

DEMO.sh делает это автоматически.

**Кластер не запускается после recovery:**
```bash
# Проверьте логи
kubectl logs -l cnpg.io/cluster=cluster-example -c postgres

# Проверьте события
kubectl describe cluster cluster-example
```

**PITR на время до первого бэкапа:**
```bash
# Проверьте First Point of Recoverability
kubectl cnpg status cluster-example | grep "First Point"
```

**PITR после Disaster Recovery:**

После DR кластер использует новый `serverName` для WAL. PITR должен использовать тот же serverName:
```bash
# Узнать текущий serverName
kubectl get cluster cluster-example -o jsonpath='{.spec.plugins[0].parameters.serverName}'

# Использовать его в externalClusters.plugin.parameters.serverName
```

DEMO.sh определяет это автоматически.


## Мониторинг прогресса восстановления

```bash
# 1. Статус кластера
kubectl cnpg status cluster-example

# 2. Смотреть поды в реальном времени
kubectl get pods -l cnpg.io/cluster=cluster-example -w

# 3. Логи плагина barman-cloud (init-контейнер)
kubectl logs <pod-name> -c plugin-barman-cloud

# 4. Логи PostgreSQL во время recovery
kubectl logs <pod-name> -c full-recovery -f

# 5. События кластера
kubectl describe cluster cluster-example | tail -20
```