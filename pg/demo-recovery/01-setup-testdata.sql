-- Скрипт для создания тестовых данных с временными метками
-- Запускать через: kubectl cnpg psql cluster-example -- -f /path/to/script.sql

-- Создаём таблицу для демонстрации
CREATE TABLE IF NOT EXISTS important_data (
    id SERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Вставляем начальные данные
INSERT INTO important_data (data) VALUES
    ('Критически важные данные 1'),
    ('Критически важные данные 2'),
    ('Критически важные данные 3');

-- Показываем что вставили
SELECT * FROM important_data ORDER BY id;

-- Показываем текущее время для PITR
SELECT NOW() AS "Текущее время (запомните для PITR)";
