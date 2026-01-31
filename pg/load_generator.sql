-- load_generator.sql
-- Скрипт для генерации нагрузки на БД интернет-магазина
-- Запуск: psql -d online_store -f load_generator.sql

-- Отключаем вывод промежуточных результатов для чистоты
\set QUIET off
\timing on

-- Параметры нагрузки (можно менять)
\set NUM_USERS 1000          -- Количество пользователей для генерации
\set NUM_PRODUCTS 200        -- Количество продуктов для генерации
\set NUM_ORDERS 5000         -- Количество заказов
\set NUM_CONCURRENT_SESSIONS 10 -- "Псевдо-параллельных" сессий
\set TRANSACTIONS_PER_SESSION 50 -- Транзакций на сессию

DO $$
DECLARE
    -- Глобальные переменные
    user_count INTEGER;
    product_count INTEGER;
    category_count INTEGER;
    order_count INTEGER;
    
    -- Функции для генерации данных
BEGIN
    RAISE NOTICE '=== НАЧАЛО ГЕНЕРАЦИИ НАГРУЗКИ ===';
    RAISE NOTICE 'Параметры: % пользователей, % товаров, % заказов', 
        :NUM_USERS, :NUM_PRODUCTS, :NUM_ORDERS;
    
    -- 1. Очистка старых тестовых данных (опционально)
    RAISE NOTICE '1. Очистка старых тестовых данных...';
    -- DELETE FROM order_coupons;
    -- DELETE FROM order_items;
    -- DELETE FROM orders;
    -- DELETE FROM cart_items;
    -- DELETE FROM carts;
    -- DELETE FROM product_reviews;
    -- DELETE FROM inventory_log;
    -- DELETE FROM product_categories;
    -- DELETE FROM product_images;
    -- DELETE FROM products WHERE product_id > 3;
    -- DELETE FROM addresses WHERE user_id > 1;
    -- DELETE FROM users WHERE user_id > 1;
    
    -- 2. Генерация пользователей
    RAISE NOTICE '2. Генерация % пользователей...', :NUM_USERS;
    INSERT INTO users (email, password_hash, first_name, last_name, phone, registration_date)
    SELECT 
        'user' || generate_series || '@example.com',
        md5(random()::text),
        (ARRAY['Иван','Петр','Алексей','Сергей','Дмитрий','Андрей','Михаил'])[floor(random()*7+1)],
        (ARRAY['Иванов','Петров','Сидоров','Смирнов','Кузнецов','Попов','Васильев'])[floor(random()*7+1)],
        '+7' || floor(random() * 9000000000 + 1000000000)::text,
        NOW() - (random() * 365 || ' days')::INTERVAL
    FROM generate_series(1, :NUM_USERS);
    
    SELECT COUNT(*) INTO user_count FROM users;
    RAISE NOTICE '   Создано пользователей: %', user_count;
    
    -- 3. Генерация адресов для пользователей
    RAISE NOTICE '3. Генерация адресов...';
    INSERT INTO addresses (user_id, country, city, street, house_number, apartment, postal_code, is_default)
    SELECT 
        u.user_id,
        'Россия',
        (ARRAY['Москва','Санкт-Петербург','Новосибирск','Екатеринбург','Казань','Нижний Новгород'])[floor(random()*6+1)],
        (ARRAY['Ленина','Пушкина','Гагарина','Советская','Мира','Центральная'])[floor(random()*6+1)],
        floor(random()*100 + 1)::text,
        CASE WHEN random() > 0.3 THEN floor(random()*200 + 1)::text ELSE NULL END,
        floor(random()*190000 + 100000)::text,
        TRUE
    FROM users u
    WHERE u.user_id > 1;  -- Пропускаем существующих
    
    -- 4. Генерация дополнительных товаров
    RAISE NOTICE '4. Генерация % товаров...', :NUM_PRODUCTS;
    INSERT INTO products (sku, name, slug, description, short_description, 
                         price, discount_price, quantity_in_stock, weight_kg, is_active)
    SELECT 
        'SKU-' || generate_series,
        'Товар ' || generate_series || ' ' || 
        (ARRAY['Премиум','Эконом','Супер','Ультра','Профи'])[floor(random()*5+1)],
        'product-' || generate_series,
        'Подробное описание товара ' || generate_series || '. ' ||
        repeat('Это отличный товар с множеством функций. ', 5),
        'Краткое описание товара ' || generate_series,
        round((random() * 100000 + 100)::numeric, 2),
        CASE WHEN random() > 0.7 THEN round((random() * 80000 + 50)::numeric, 2) ELSE NULL END,
        floor(random() * 1000),
        round((random() * 10)::numeric, 3),
        random() > 0.1  -- 90% активных товаров
    FROM generate_series(4, :NUM_PRODUCTS + 3);
    
    SELECT COUNT(*) INTO product_count FROM products;
    RAISE NOTICE '   Всего товаров: %', product_count;
    
    -- 5. Привязка товаров к категориям
    RAISE NOTICE '5. Привязка товаров к категориям...';
    SELECT COUNT(*) INTO category_count FROM categories;
    
    INSERT INTO product_categories (product_id, category_id)
    SELECT 
        p.product_id,
        ceil(random() * category_count)
    FROM products p
    ON CONFLICT DO NOTHING;
    
    -- Каждому товару даем 1-3 категории
    INSERT INTO product_categories (product_id, category_id)
    SELECT 
        p.product_id,
        ceil(random() * category_count)
    FROM products p
    WHERE random() > 0.5
    ON CONFLICT DO NOTHING;
    
    INSERT INTO product_categories (product_id, category_id)
    SELECT 
        p.product_id,
        ceil(random() * category_count)
    FROM products p
    WHERE random() > 0.7
    ON CONFLICT DO NOTHING;
    
    -- 6. Генерация корзин для пользователей
    RAISE NOTICE '6. Создание корзин для пользователей...';
    INSERT INTO carts (user_id)
    SELECT user_id 
    FROM users 
    WHERE random() > 0.3  -- У 70% пользователей есть корзины
    ON CONFLICT DO NOTHING;
    
    -- 7. Генерация заказов
    RAISE NOTICE '7. Генерация % заказов...', :NUM_ORDERS;
    
    -- Вспомогательная функция для генерации одного заказа
    FOR i IN 1..:NUM_ORDERS LOOP
        -- Выбираем случайного пользователя с адресом
        WITH random_user AS (
            SELECT u.user_id, a.address_id
            FROM users u
            JOIN addresses a ON u.user_id = a.user_id
            WHERE u.user_id > 1
            ORDER BY random()
            LIMIT 1
        )
        INSERT INTO orders (order_number, user_id, shipping_address_id, 
                           billing_address_id, status, total_amount, 
                           shipping_cost, payment_method, payment_status)
        SELECT 
            'ORD-' || to_char(NOW(), 'YYYYMMDD') || '-' || i,
            ru.user_id,
            ru.address_id,
            ru.address_id,
            (ARRAY['pending','processing','shipped','delivered','cancelled'])[floor(random()*5+1)],
            round((random() * 50000 + 500)::numeric, 2),
            CASE WHEN random() > 0.5 THEN round((random() * 2000)::numeric, 2) ELSE 0 END,
            (ARRAY['card','cash_on_delivery','online','bank_transfer'])[floor(random()*4+1)],
            (ARRAY['pending','paid','failed'])[floor(random()*3+1)]
        FROM random_user ru;
        
        -- Генерируем 1-5 товаров для каждого заказа
        FOR j IN 1..floor(random()*5 + 1) LOOP
            INSERT INTO order_items (order_id, product_id, product_name, 
                                    unit_price, quantity, discount)
            SELECT 
                i,
                p.product_id,
                p.name,
                COALESCE(p.discount_price, p.price),
                floor(random()*5 + 1),
                CASE WHEN random() > 0.8 THEN round((random() * 1000)::numeric, 2) ELSE 0 END
            FROM products p
            WHERE p.is_active = TRUE
            ORDER BY random()
            LIMIT 1
            ON CONFLICT DO NOTHING;
        END LOOP;
        
        -- Прогресс каждые 100 заказов
        IF i % 100 = 0 THEN
            RAISE NOTICE '   Создано заказов: % из %', i, :NUM_ORDERS;
        END IF;
    END LOOP;
    
    SELECT COUNT(*) INTO order_count FROM orders;
    RAISE NOTICE '   Создано заказов: %', order_count;
    
    -- 8. Генерация отзывов о товарах
    RAISE NOTICE '8. Генерация отзывов...';
    INSERT INTO product_reviews (product_id, user_id, rating, title, comment, is_approved)
    SELECT 
        p.product_id,
        u.user_id,
        floor(random()*5 + 1),
        CASE 
            WHEN random() > 0.5 THEN 'Отличный товар!'
            WHEN random() > 0.5 THEN 'Хорошее качество'
            ELSE 'Нормально, но есть недостатки'
        END,
        'Текст отзыва пользователя ' || u.user_id || ' о товаре ' || p.product_id ||
        CASE 
            WHEN random() > 0.7 THEN '. Очень рекомендую!'
            WHEN random() > 0.5 THEN '. В целом доволен.'
            ELSE '. Можно было бы лучше.'
        END,
        random() > 0.2  -- 80% одобренных отзывов
    FROM products p
    CROSS JOIN (SELECT user_id FROM users ORDER BY random() LIMIT 50) u
    WHERE random() > 0.7  -- Отзывы для 30% товаров
    LIMIT 1000;
    
    -- 9. Заполнение истории инвентаря
    RAISE NOTICE '9. Заполнение истории инвентаря...';
    INSERT INTO inventory_log (product_id, quantity_change, new_quantity, 
                              change_type, reference_id, notes)
    SELECT 
        p.product_id,
        CASE 
            WHEN random() > 0.3 THEN floor(random()*100 + 1)
            ELSE -floor(random()*50 + 1)
        END,
        p.quantity_in_stock,
        (ARRAY['purchase','sale','adjustment','return','damage'])[floor(random()*5+1)],
        CASE 
            WHEN random() > 0.5 THEN (SELECT order_id FROM orders ORDER BY random() LIMIT 1)
            ELSE NULL
        END,
        CASE 
            WHEN random() > 0.7 THEN 'Автоматическая корректировка'
            WHEN random() > 0.5 THEN 'Поступление от поставщика'
            ELSE 'Реализация покупателю'
        END
    FROM products p
    CROSS JOIN generate_series(1, 3)  -- По 3 записи на товар
    WHERE random() > 0.4;
    
    RAISE NOTICE '=== ОСНОВНЫЕ ДАННЫЕ СОЗДАНЫ ===';
    RAISE NOTICE 'Переходим к генерации нагрузки...';
    
END $$;

-- =============================================
-- ЧАСТЬ 2: ГЕНЕРАЦИЯ НАГРУЗКИ (ИМИТАЦИЯ РАБОТЫ)
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '10. Начало генерации рабочей нагрузки...';
END $$;

-- Функция для имитации одной пользовательской сессии
CREATE OR REPLACE FUNCTION simulate_user_session(session_id INT) RETURNS VOID AS $$
DECLARE
    v_user_id INT;
    v_product_id INT;
    v_order_id INT;
    v_cart_id INT;
    v_category_id INT;
    v_search_term TEXT;
    v_start_time TIMESTAMP;
    v_query TEXT;
    v_result RECORD;
BEGIN
    v_start_time := NOW();
    
    -- Выбираем случайного пользователя для сессии
    SELECT user_id INTO v_user_id 
    FROM users 
    WHERE user_id > 1 
    ORDER BY random() 
    LIMIT 1;
    
    -- СЕРИЯ ИМИТАЦИОННЫХ ЗАПРОСОВ
    
    -- 1. Просмотр товаров (часто читающие запросы)
    FOR i IN 1..5 LOOP
        -- Запрос 1: Получение товаров по категории
        EXECUTE '
            SELECT p.product_id, p.name, p.price, c.name as category_name
            FROM products p
            JOIN product_categories pc ON p.product_id = pc.product_id
            JOIN categories c ON pc.category_id = c.category_id
            WHERE c.category_id = $1 AND p.is_active = TRUE
            ORDER BY p.price DESC
            LIMIT 20'
        INTO v_result
        USING floor(random() * 3 + 1);
        
        -- Запрос 2: Поиск товаров
        v_search_term := (ARRAY['ноутбук','книга','футболка','телефон','аксессуар'])[floor(random()*5+1)];
        EXECUTE '
            SELECT product_id, name, price
            FROM products 
            WHERE name ILIKE $1 AND is_active = TRUE
            ORDER BY price
            LIMIT 15'
        INTO v_result
        USING '%' || v_search_term || '%';
        
        -- Запрос 3: Получение детальной информации о товаре
        SELECT product_id INTO v_product_id 
        FROM products 
        WHERE is_active = TRUE 
        ORDER BY random() 
        LIMIT 1;
        
        EXECUTE '
            SELECT p.*, 
                   (SELECT AVG(rating) FROM product_reviews WHERE product_id = p.product_id AND is_approved = TRUE) as avg_rating,
                   (SELECT COUNT(*) FROM product_reviews WHERE product_id = p.product_id AND is_approved = TRUE) as review_count
            FROM products p
            WHERE p.product_id = $1'
        INTO v_result
        USING v_product_id;
        
        -- Небольшая пауза между запросами
        PERFORM pg_sleep(random() * 0.1);
    END LOOP;
    
    -- 2. Работа с корзиной (30% вероятности)
    IF random() > 0.7 THEN
        -- Получаем или создаем корзину
        SELECT cart_id INTO v_cart_id 
        FROM carts 
        WHERE user_id = v_user_id;
        
        IF v_cart_id IS NULL THEN
            INSERT INTO carts (user_id) VALUES (v_user_id) RETURNING cart_id INTO v_cart_id;
        END IF;
        
        -- Добавляем случайный товар в корзину
        SELECT product_id INTO v_product_id 
        FROM products 
        WHERE is_active = TRUE 
        ORDER BY random() 
        LIMIT 1;
        
        INSERT INTO cart_items (cart_id, product_id, quantity)
        VALUES (v_cart_id, v_product_id, floor(random()*3 + 1))
        ON CONFLICT (cart_id, product_id) 
        DO UPDATE SET quantity = cart_items.quantity + 1;
        
        -- Просмотр корзины
        EXECUTE '
            SELECT ci.quantity, p.name, p.price, ci.quantity * p.price as total
            FROM cart_items ci
            JOIN products p ON ci.product_id = p.product_id
            WHERE ci.cart_id = $1'
        INTO v_result
        USING v_cart_id;
    END IF;
    
    -- 3. Создание заказа (10% вероятности)
    IF random() > 0.9 THEN
        BEGIN
            -- Начинаем транзакцию
            -- START TRANSACTION; -- Не нужно в функции PL/pgSQL
            
            -- Создаем заказ
            INSERT INTO orders (order_number, user_id, status, total_amount, payment_method)
            VALUES (
                'LOAD-' || to_char(NOW(), 'YYYYMMDD-HH24MISS') || '-' || session_id,
                v_user_id,
                'pending',
                round((random() * 20000 + 1000)::numeric, 2),
                (ARRAY['card','online'])[floor(random()*2+1)]
            ) RETURNING order_id INTO v_order_id;
            
            -- Добавляем 1-3 товара в заказ
            FOR i IN 1..floor(random()*3 + 1) LOOP
                SELECT product_id, name, 
                       COALESCE(discount_price, price) INTO v_product_id, v_query, v_category_id
                FROM products 
                WHERE is_active = TRUE 
                ORDER BY random() 
                LIMIT 1;
                
                INSERT INTO order_items (order_id, product_id, product_name, 
                                        unit_price, quantity)
                VALUES (v_order_id, v_product_id, v_query, v_category_id, floor(random()*3 + 1));
                
                -- Обновляем инвентарь
                INSERT INTO inventory_log (product_id, quantity_change, new_quantity, 
                                          change_type, notes)
                SELECT 
                    v_product_id,
                    -floor(random()*3 + 1),
                    quantity_in_stock - floor(random()*3 + 1),
                    'sale',
                    'Продажа по заказу ' || v_order_id
                FROM products 
                WHERE product_id = v_product_id;
            END LOOP;
            
            -- Обновляем общую сумму заказа
            UPDATE orders 
            SET total_amount = (
                SELECT SUM(unit_price * quantity) 
                FROM order_items 
                WHERE order_id = v_order_id
            )
            WHERE order_id = v_order_id;
            
            -- COMMIT; -- Автоматический в функции
            RAISE NOTICE 'Сессия %: Создан заказ %', session_id, v_order_id;
            
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Сессия %: Ошибка при создании заказа: %', session_id, SQLERRM;
            -- ROLLBACK; -- Автоматический в функции при ошибке
        END;
    END IF;
    
    -- 4. Административные запросы (20% вероятности)
    IF random() > 0.8 THEN
        -- Запрос 1: Статистика продаж
        EXECUTE '
            SELECT 
                DATE(created_at) as day,
                COUNT(*) as order_count,
                SUM(total_amount) as total_revenue,
                AVG(total_amount) as avg_order_value
            FROM orders 
            WHERE created_at >= NOW() - INTERVAL ''7 days''
            GROUP BY DATE(created_at)
            ORDER BY day DESC'
        INTO v_result;
        
        -- Запрос 2: Популярные товары
        EXECUTE '
            SELECT 
                p.name,
                SUM(oi.quantity) as total_sold,
                SUM(oi.quantity * oi.unit_price) as revenue
            FROM order_items oi
            JOIN products p ON oi.product_id = p.product_id
            GROUP BY p.product_id, p.name
            ORDER BY total_sold DESC
            LIMIT 10'
        INTO v_result;
        
        -- Запрос 3: Активность пользователей
        EXECUTE '
            SELECT 
                u.user_id,
                u.email,
                COUNT(o.order_id) as order_count,
                SUM(o.total_amount) as total_spent
            FROM users u
            LEFT JOIN orders o ON u.user_id = o.user_id
            GROUP BY u.user_id, u.email
            ORDER BY total_spent DESC NULLS LAST
            LIMIT 15'
        INTO v_result;
    END IF;
    
    RAISE NOTICE 'Сессия % завершена за % мс', 
        session_id, 
        EXTRACT(EPOCH FROM (NOW() - v_start_time)) * 1000;
    
END;
$$ LANGUAGE plpgsql;

-- Запуск "параллельных" сессий
DO $$
DECLARE
    session_num INT;
    total_sessions INT := 0;
    successful_sessions INT := 0;
BEGIN
    RAISE NOTICE 'Запуск % "параллельных" сессий по % транзакций...', 
        :NUM_CONCURRENT_SESSIONS, :TRANSACTIONS_PER_SESSION;

    FOR session_num IN 1..:NUM_CONCURRENT_SESSIONS LOOP
        BEGIN
            -- Каждая сессия выполняет несколько транзакций
            FOR i IN 1..:TRANSACTIONS_PER_SESSION LOOP
                PERFORM simulate_user_session(session_num * 1000 + i);
                -- Небольшая задержка между транзакциями
                PERFORM pg_sleep(random() * 0.05);
            END LOOP;
            
            successful_sessions := successful_sessions + 1;
            RAISE NOTICE 'Сессия % успешно завершена', session_num;
            
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Ошибка в сессии %: %', session_num, SQLERRM;
        END;
        
        total_sessions := total_sessions + 1;
    END LOOP;
    
    RAISE NOTICE '=== ИТОГИ ГЕНЕРАЦИИ НАГРУЗКИ ===';
    RAISE NOTICE 'Всего сессий: %, успешных: %', total_sessions, successful_sessions;
END $$;

-- =============================================
-- ЧАСТЬ 3: ФИНАЛЬНЫЕ ЗАПРОСЫ ДЛЯ ПРОВЕРКИ
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '11. Финальная проверка и статистика...';
END $$;

\echo '=== Статистика базы данных ==='
SELECT 
    'Пользователи' as metric,
    COUNT(*) as value
FROM users
UNION ALL
SELECT 
    'Товары',
    COUNT(*)
FROM products
UNION ALL
SELECT 
    'Активные товары',
    COUNT(*)
FROM products 
WHERE is_active = TRUE
UNION ALL
SELECT 
    'Заказы',
    COUNT(*)
FROM orders
UNION ALL
SELECT 
    'Отзывы',
    COUNT(*)
FROM product_reviews
UNION ALL
SELECT 
    'Записи инвентаря',
    COUNT(*)
FROM inventory_log;

\echo ''
\echo '=== Статистика использования индексов ==='
SELECT 
    schemaname,
    relname,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY seq_scan + idx_scan DESC
LIMIT 10;

\echo ''
\echo '=== Проверка блокировок ==='
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;

\echo ''
\echo '=== Самые медленные запросы (если pg_stat_statements включен) ==='
DO $$
BEGIN
    -- Проверяем, существует ли представление pg_stat_statements
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'pg_stat_statements' AND n.nspname = 'pg_catalog'
    ) THEN
        -- Если pg_stat_statements включен, показываем статистику
        RAISE NOTICE 'pg_stat_statements доступен:';
        EXECUTE 'SELECT query, calls, total_exec_time, mean_exec_time, rows
                FROM pg_stat_statements 
                ORDER BY mean_exec_time DESC 
                LIMIT 5';
    ELSE
        RAISE NOTICE 'pg_stat_statements не включен. Для активации выполните:';
        RAISE NOTICE '  CREATE EXTENSION pg_stat_statements;';
        RAISE NOTICE '  Добавьте pg_stat_statements в shared_preload_libraries в postgresql.conf';
    END IF;
END $$;

\echo ''
DO $$
BEGIN
    RAISE NOTICE '=== ГЕНЕРАЦИЯ НАГРУЗКИ ЗАВЕРШЕНА ===';
    RAISE NOTICE 'Для продолжения нагрузки запустите скрипт заново или используйте pgbench';
    RAISE NOTICE 'Пример: pgbench -c 10 -j 2 -T 300 -f load_queries.sql online_store';
END $$;