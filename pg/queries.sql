-- Получить все активные товары с их категориями
SELECT p.name, p.price, c.name as category
FROM products p
JOIN product_categories pc ON p.product_id = pc.product_id
JOIN categories c ON pc.category_id = c.category_id
WHERE p.is_active = TRUE
ORDER BY p.price DESC;

-- Получить топ-5 товаров по количеству продаж
SELECT p.name, SUM(oi.quantity) as total_sold
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.product_id, p.name
ORDER BY total_sold DESC
LIMIT 5;

-- Создать заказ из корзины пользователя (пример процедуры)
WITH cart_data AS (
    SELECT ci.product_id, ci.quantity, p.price
    FROM cart_items ci
    JOIN products p ON ci.product_id = p.product_id
    WHERE ci.cart_id = 1
)
INSERT INTO order_items (order_id, product_id, product_name, unit_price, quantity)
SELECT 
    1 as order_id, 
    cd.product_id,
    (SELECT name FROM products WHERE product_id = cd.product_id),
    cd.price,
    cd.quantity
FROM cart_data cd;