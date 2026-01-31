# CloudNativePG 1.28 — Rolling Update
https://cloudnative-pg.io/docs/1.28/rolling_update

---

## 1. Что такое Rolling Update

Rolling Update в CloudNativePG — это механизм обновления PostgreSQL-кластера без его пересоздания и без повторной инициализации данных.

Ключевые свойства:
- обновление выполняется pod за pod’ом;
- сначала обновляются реплики, затем primary;
- PVC не пересоздаются, данные не клонируются;
- используется стандартный Kubernetes-подход: delete → recreate pod.

Полного zero-downtime не гарантируется, но простой минимизируется и контролируется.

---

## 2. Что инициирует Rolling Update

Rolling Update запускается при изменениях в spec объекта Cluster, включая:
- изменение imageName (новая версия PostgreSQL);
- обновление image catalog;
- изменение списка расширений PostgreSQL;
- изменения конфигурации PostgreSQL, требующие рестарта;
- изменение ресурсов (CPU / memory);
- обновление оператора.

---

## 3. Порядок обновления

1. Обновляется одна реплика.
2. После её готовности обновляется следующая реплика.
3. После обновления всех реплик выполняется обновление primary.

---

## 4. Управление обновлением Primary

Поведение обновления primary настраивается:

spec:
  primaryUpdateStrategy: unsupervised | supervised
  primaryUpdateMethod: restart | switchover

---

## 5. primaryUpdateStrategy

### unsupervised
- полностью автоматическое обновление;
- оператор сам завершает обновление primary.

### supervised
- после обновления реплик процесс останавливается;
- primary обновляется вручную.

Команды:
kubectl cnpg promote <cluster> <new_primary>
kubectl cnpg restart <cluster> <current_primary>

---

## 6. primaryUpdateMethod

### restart
- primary остаётся primary;
- pod удаляется и пересоздаётся;
- в 1.28 разрешено одновременно менять image и параметры PostgreSQL.

### switchover
- наиболее синхронизированная реплика становится primary;
- старый primary становится standby;
- нельзя одновременно менять image и конфигурацию PostgreSQL.

---

## 7. Поведение сервисов

- Kubernetes Services исключают pod’ы в процессе обновления;
- приложения должны уметь переподключаться.

---

## 8. Примеры конфигурации

Автоматический switchover:
spec:
  primaryUpdateStrategy: unsupervised
  primaryUpdateMethod: switchover

Ручной контроль:
spec:
  primaryUpdateStrategy: supervised
  primaryUpdateMethod: switchover

---

## 9. Практические рекомендации

- Обновление image PostgreSQL → switchover
- Изменение image + параметров → restart
- Жёсткий контроль окна → supervised + switchover

---

## 10. Итог

Rolling Update — controlled downtime.
switchover — основной production-паттерн.
restart — удобен для конфигурационных изменений.


## Важные замечания

1. **Образы system deprecated**: Образы с суффиксом `-system` помечены как deprecated и будут удалены. Рекомендуется миграция на `-minimal` или `-standard` с плагином Barman Cloud.

2. **Параметр max_slot_wal_keep_size**: Для PostgreSQL 17.0-17.5 перед мажорным обновлением убедитесь, что параметр установлен в `-1` или обновитесь до 17.6+.

3. **Расширения PostgreSQL**: Убедитесь, что все расширения совместимы с новой версией.

4. **Тестирование**: Обязательно протестируйте процесс обновления в тестовой среде перед применением в production.

5. **Мониторинг**: Используйте Prometheus/Grafana для мониторинга процесса обновления.

6. **Время простоя**: 
   - Минорное обновление: минимальный downtime (несколько секунд при переключении primary)
   - Мажорное обновление: полный downtime на время выполнения pg_upgrade (может занять от нескольких минут до часов в зависимости от размера базы)

7. **Бэкапы**: Старые бэкапы (base backups и WAL) доступны только для предыдущей версии PostgreSQL. После мажорного обновления создайте новый бэкап.