-- load_queries.sql - запросы для pgbench
\set user_id random(1, 1000)
\set product_id random(1, 200)
\set category_id random(1, 3)

-- 1. Чтение: получение товаров по категории
SELECT p.product_id, p.name, p.price, c.name as category_name
FROM products p
JOIN product_categories pc ON p.product_id = pc.product_id
JOIN categories c ON pc.category_id = c.category_id
WHERE c.category_id = :category_id AND p.is_active = TRUE
ORDER BY p.price DESC
LIMIT 20;

-- 2. Чтение: поиск товаров
SELECT product_id, name, price
FROM products 
WHERE name ILIKE '%ноутбук%' AND is_active = TRUE
ORDER BY price
LIMIT 15;

-- 3. Чтение: детали товара
SELECT p.*, 
       (SELECT AVG(rating) FROM product_reviews WHERE product_id = p.product_id AND is_approved = TRUE) as avg_rating
FROM products p
WHERE p.product_id = :product_id;

-- 4. Запись: добавление просмотра (если есть таблица просмотров)
-- INSERT INTO product_views (product_id, user_id, viewed_at) 
-- VALUES (:product_id, :user_id, NOW());

-- 5. Чтение: корзина пользователя
SELECT ci.quantity, p.name, p.price, ci.quantity * p.price as total
FROM cart_items ci
JOIN products p ON ci.product_id = p.product_id
WHERE ci.cart_id = (SELECT cart_id FROM carts WHERE user_id = :user_id LIMIT 1);

-- 6. Запись: обновление корзины
INSERT INTO cart_items (cart_id, product_id, quantity)
VALUES (
    (SELECT cart_id FROM carts WHERE user_id = :user_id LIMIT 1),
    :product_id,
    1
)
ON CONFLICT (cart_id, product_id) 
DO UPDATE SET quantity = cart_items.quantity + 1;

-- 7. Чтение: статистика заказов
SELECT 
    DATE(created_at) as day,
    COUNT(*) as order_count,
    SUM(total_amount) as total_revenue
FROM orders 
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY day DESC;