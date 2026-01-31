
-- Таблица пользователей (клиентов)
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    registration_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- Таблица адресов доставки
CREATE TABLE addresses (
    address_id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    country VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    street VARCHAR(255) NOT NULL,
    house_number VARCHAR(20) NOT NULL,
    apartment VARCHAR(20),
    postal_code VARCHAR(20),
    is_default BOOLEAN DEFAULT FALSE
);

-- Таблица категорий товаров (иерархическая)
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    parent_category_id INTEGER REFERENCES categories(category_id) ON DELETE SET NULL,
    description TEXT,
    image_url VARCHAR(500),
    display_order INTEGER DEFAULT 0
);

-- Таблица товаров
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    short_description VARCHAR(500),
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    discount_price DECIMAL(10,2) CHECK (discount_price >= 0),
    quantity_in_stock INTEGER DEFAULT 0 CHECK (quantity_in_stock >= 0),
    weight_kg DECIMAL(8,3),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Связующая таблика товаров и категорий (многие-ко-многим)
CREATE TABLE product_categories (
    product_id INTEGER REFERENCES products(product_id) ON DELETE CASCADE,
    category_id INTEGER REFERENCES categories(category_id) ON DELETE CASCADE,
    PRIMARY KEY (product_id, category_id)
);

-- Таблица изображений товаров
CREATE TABLE product_images (
    image_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(product_id) ON DELETE CASCADE,
    image_url VARCHAR(500) NOT NULL,
    alt_text VARCHAR(255),
    display_order INTEGER DEFAULT 0,
    is_main BOOLEAN DEFAULT FALSE
);

-- Таблица отзывов о товарах
CREATE TABLE product_reviews (
    review_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(product_id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    title VARCHAR(200),
    comment TEXT,
    is_approved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица корзин (shopping carts)
CREATE TABLE carts (
    cart_id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица элементов корзины
CREATE TABLE cart_items (
    cart_item_id SERIAL PRIMARY KEY,
    cart_id INTEGER REFERENCES carts(cart_id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(product_id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(cart_id, product_id)
);

-- Таблица заказов
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    shipping_address_id INTEGER REFERENCES addresses(address_id),
    billing_address_id INTEGER REFERENCES addresses(address_id),
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    -- Возможные статусы: pending, processing, shipped, delivered, cancelled, refunded
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    shipping_cost DECIMAL(10,2) DEFAULT 0 CHECK (shipping_cost >= 0),
    tax_amount DECIMAL(10,2) DEFAULT 0 CHECK (tax_amount >= 0),
    payment_method VARCHAR(50),
    payment_status VARCHAR(50) DEFAULT 'pending',
    -- payment_status: pending, paid, failed, refunded
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица элементов заказа
CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(product_id),
    product_name VARCHAR(255) NOT NULL, -- Сохраняем на момент заказа
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    discount DECIMAL(10,2) DEFAULT 0 CHECK (discount >= 0),
    total_price DECIMAL(10,2) GENERATED ALWAYS AS (unit_price * quantity - discount) STORED
);

-- Таблица промокодов/купонов
CREATE TABLE coupons (
    coupon_id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    discount_type VARCHAR(20) NOT NULL, -- 'percentage' или 'fixed'
    discount_value DECIMAL(10,2) NOT NULL CHECK (discount_value >= 0),
    min_order_amount DECIMAL(10,2) DEFAULT 0,
    max_discount_amount DECIMAL(10,2),
    valid_from TIMESTAMP NOT NULL,
    valid_until TIMESTAMP,
    usage_limit INTEGER,
    used_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE
);

-- Таблица использования купонов в заказах
CREATE TABLE order_coupons (
    order_id INTEGER REFERENCES orders(order_id) ON DELETE CASCADE,
    coupon_id INTEGER REFERENCES coupons(coupon_id) ON DELETE CASCADE,
    discount_applied DECIMAL(10,2) NOT NULL CHECK (discount_applied >= 0),
    PRIMARY KEY (order_id, coupon_id)
);

-- Таблица склада/инвентаризации
CREATE TABLE inventory_log (
    log_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(product_id) ON DELETE CASCADE,
    quantity_change INTEGER NOT NULL,
    -- положительное число - пополнение, отрицательное - продажа
    new_quantity INTEGER NOT NULL,
    change_type VARCHAR(50) NOT NULL,
    -- Типы: 'purchase', 'sale', 'adjustment', 'return', 'damage'
    reference_id INTEGER, -- ID заказа, поставки и т.д.
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by INTEGER REFERENCES users(user_id) ON DELETE SET NULL
);

-- Создаем индексы для улучшения производительности
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_price ON products(price);
CREATE INDEX idx_products_active ON products(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_categories_parent ON categories(parent_category_id);
CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created ON orders(created_at);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_cart_items_cart ON cart_items(cart_id);
CREATE INDEX idx_inventory_product ON inventory_log(product_id);
CREATE INDEX idx_product_reviews_product ON product_reviews(product_id);
CREATE INDEX idx_product_reviews_approved ON product_reviews(is_approved) WHERE is_approved = TRUE;

-- Создаем триггер для автоматического обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Применяем триггер к таблицам
CREATE TRIGGER update_products_updated_at 
    BEFORE UPDATE ON products 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at 
    BEFORE UPDATE ON orders 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_carts_updated_at 
    BEFORE UPDATE ON carts 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_product_reviews_updated_at 
    BEFORE UPDATE ON product_reviews 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Триггер для обновления количества товара на складе при изменении инвентаря
CREATE OR REPLACE FUNCTION update_product_stock()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE products 
    SET quantity_in_stock = NEW.new_quantity,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = NEW.product_id;
    
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER after_inventory_log 
    AFTER INSERT ON inventory_log 
    FOR EACH ROW EXECUTE FUNCTION update_product_stock();

-- Вставляем тестовые данные (опционально)
INSERT INTO categories (name, slug, description) VALUES
    ('Электроника', 'electronics', 'Электронные устройства и гаджеты'),
    ('Одежда', 'clothing', 'Мужская и женская одежда'),
    ('Книги', 'books', 'Художественная и учебная литература');

INSERT INTO products (sku, name, slug, description, price, quantity_in_stock) VALUES
    ('NB-001', 'Ноутбук Gaming Pro', 'notebook-gaming-pro', 'Игровой ноутбук с RTX 4060', 129999.99, 10),
    ('TS-202', 'Футболка хлопковая', 't-shirt-cotton', 'Мужская футболка из 100% хлопка', 1999.99, 50),
    ('BK-555', 'PostgreSQL для профессионалов', 'postgresql-professional', 'Книга по администрированию PostgreSQL', 2999.99, 25);

INSERT INTO product_categories (product_id, category_id) VALUES
    (1, 1), -- Ноутбук -> Электроника
    (2, 2), -- Футболка -> Одежда
    (3, 3); -- Книга -> Книги