CREATE DATABASE ecommerce_dw;
USE DATABASE ecommerce_dw;
CREATE SCHEMA raw_data;
CREATE SCHEMA transformed_data;

--Create Staging Tables in raw_data

USE SCHEMA raw_data;

CREATE OR REPLACE TABLE staging_ecomm (
    user_id VARCHAR,
    product_id VARCHAR,
    category VARCHAR,
    price NUMBER(38,2),
    discount NUMBER(38,0),
    final_price NUMBER(38,2),
    payment_method VARCHAR,
    purchase_date VARCHAR
);


CREATE OR REPLACE TABLE staging_reviews (
    id NUMBER(38,0),
    productid VARCHAR,
    userid VARCHAR,
    profilename VARCHAR,
    helpfulnessnumerator NUMBER(38,0),
    helpfulnessdenominator NUMBER(38,0),
    score NUMBER(38,0),
    time NUMBER(38,0),
    summary VARCHAR,
    text VARCHAR
);

CREATE OR REPLACE TABLE staging_sales (
    index_col NUMBER(38,0),
    orderid VARCHAR,
    date VARCHAR,
    status VARCHAR,
    fulfilment VARCHAR,
    sales_channel VARCHAR,
    style VARCHAR,
    sku VARCHAR,
    category VARCHAR,
    size VARCHAR,
    asin VARCHAR,
    courier_status VARCHAR,
    qty NUMBER(38,0),
    currency VARCHAR,
    amount NUMBER(38,2),
    ship_city VARCHAR,
    ship_state VARCHAR,
    ship_postal_code NUMBER(38,1),
    ship_country VARCHAR,
    b2b BOOLEAN
);

--Dimension Tables

USE SCHEMA transformed_data;

--Users Dimension

CREATE OR REPLACE TABLE dim_users (
    user_key INT AUTOINCREMENT PRIMARY KEY,
    user_id VARCHAR UNIQUE
);

--Products Dimension

CREATE OR REPLACE TABLE dim_products (
    product_key INT AUTOINCREMENT PRIMARY KEY,
    product_id VARCHAR UNIQUE,
    category VARCHAR
);

--Payment Methods Dimension

CREATE OR REPLACE TABLE dim_payment_methods (
    payment_key INT AUTOINCREMENT PRIMARY KEY,
    payment_method VARCHAR UNIQUE
);

--Sales Channel Dimension

CREATE OR REPLACE TABLE dim_sales_channel (
    channel_key INT AUTOINCREMENT PRIMARY KEY,
    sales_channel VARCHAR UNIQUE
);

--Fulfillment Dimension

CREATE OR REPLACE TABLE dim_fulfillment (
    fulfillment_key INT AUTOINCREMENT PRIMARY KEY,
    fulfillment VARCHAR UNIQUE
);

--ETL Queries to Populate Dimension Tables

INSERT INTO transformed_data.dim_users (user_id)
SELECT DISTINCT user_id FROM raw_data.staging_ecomm;

INSERT INTO transformed_data.dim_products (product_id, category)
SELECT DISTINCT product_id, category FROM raw_data.staging_ecomm;

INSERT INTO transformed_data.dim_payment_methods (payment_method)
SELECT DISTINCT payment_method FROM raw_data.staging_ecomm;

INSERT INTO transformed_data.dim_sales_channel (sales_channel)
SELECT DISTINCT sales_channel FROM raw_data.staging_sales;

INSERT INTO transformed_data.dim_fulfillment (fulfillment)
SELECT DISTINCT fulfilment FROM raw_data.staging_sales;

--Fact Tables

--Fact Table for E-Commerce Sales

CREATE OR REPLACE TABLE fact_ecomm_sales (
    sales_id INT AUTOINCREMENT PRIMARY KEY,
    user_key INT,
    product_key INT,
    payment_key INT,
    price NUMBER(38,2),
    discount NUMBER(38,0),
    final_price NUMBER(38,2),
    purchase_date DATE,
    FOREIGN KEY (user_key) REFERENCES dim_users(user_key),
    FOREIGN KEY (product_key) REFERENCES dim_products(product_key),
    FOREIGN KEY (payment_key) REFERENCES dim_payment_methods(payment_key)
);

--Fact Table for Sales

CREATE OR REPLACE TABLE fact_sales (
    sales_id INT AUTOINCREMENT PRIMARY KEY,
    orderid VARCHAR,
    date DATE,
    status VARCHAR,
    fulfillment_key INT,
    channel_key INT,
    style VARCHAR,
    sku VARCHAR,
    category VARCHAR,
    size VARCHAR,
    courier_status VARCHAR,
    qty NUMBER(38,0),
    currency VARCHAR,
    amount NUMBER(38,2),
    ship_city VARCHAR,
    ship_state VARCHAR,
    ship_postal_code NUMBER(38,1),
    ship_country VARCHAR,
    b2b BOOLEAN,
    FOREIGN KEY (fulfillment_key) REFERENCES dim_fulfillment(fulfillment_key),
    FOREIGN KEY (channel_key) REFERENCES dim_sales_channel(channel_key)
);

--Fact Table for Reviews

CREATE OR REPLACE TABLE fact_reviews (
    review_id INT AUTOINCREMENT PRIMARY KEY,
    product_key INT,
    user_key INT,
    profilename VARCHAR,
    helpfulnessnumerator NUMBER(38,0),
    helpfulnessdenominator NUMBER(38,0),
    score NUMBER(38,0),
    time NUMBER(38,0),
    summary VARCHAR,
    text VARCHAR,
    FOREIGN KEY (product_key) REFERENCES dim_products(product_key),
    FOREIGN KEY (user_key) REFERENCES dim_users(user_key)
);

--Data cleaning to fix NULL values

SELECT 
    COUNT(*) AS total_rows,
    SUM(CASE WHEN qty IS NULL THEN 1 ELSE 0 END) AS qty_nulls,
    SUM(CASE WHEN amount IS NULL THEN 1 ELSE 0 END) AS amount_nulls,
    SUM(CASE WHEN status IS NULL THEN 1 ELSE 0 END) AS status_nulls,
    SUM(CASE WHEN category IS NULL THEN 1 ELSE 0 END) AS category_nulls,
    SUM(CASE WHEN ship_country IS NULL THEN 1 ELSE 0 END) AS ship_country_nulls
FROM transformed_data.fact_sales;

--Fill NULLs with Default Values

UPDATE transformed_data.fact_sales 
SET amount = 0 
WHERE amount IS NULL;

UPDATE transformed_data.fact_sales 
SET ship_country = 'Unknown' 
WHERE ship_country IS NULL;

--ETL Query to Populate Fact Tables

--Fact Table: E-Commerce Sales

INSERT INTO transformed_data.fact_ecomm_sales (user_key, product_key, payment_key, price, discount, final_price, purchase_date)
SELECT 
    u.user_key, 
    p.product_key, 
    pm.payment_key, 
    s.price, 
    s.discount, 
    s.final_price, 
    TO_DATE(s.purchase_date, 'DD/MM/YYYY')  -- Assuming the raw format is DD/MM/YYYY
FROM raw_data.staging_ecomm s
JOIN transformed_data.dim_users u ON s.user_id = u.user_id
JOIN transformed_data.dim_products p ON s.product_id = p.product_id
JOIN transformed_data.dim_payment_methods pm ON s.payment_method = pm.payment_method;

--Fact Table: Sales

INSERT INTO transformed_data.fact_sales (orderid, date, status, fulfillment_key, channel_key, style, sku, category, size, courier_status, qty, currency, amount, ship_city, ship_state, ship_postal_code, ship_country, b2b)
SELECT 
    s.orderid, 
    TO_DATE(s.date, 'MM/DD/YYYY'),  -- Assuming the raw format is MM/DD/YYYY
    s.status, 
    f.fulfillment_key, 
    c.channel_key, 
    s.style, 
    s.sku, 
    s.category, 
    s.size, 
    s.courier_status, 
    s.qty, 
    s.currency, 
    s.amount, 
    s.ship_city, 
    s.ship_state, 
    s.ship_postal_code, 
    s.ship_country, 
    s.b2b
FROM raw_data.staging_sales s
JOIN transformed_data.dim_fulfillment f ON s.fulfilment = f.fulfillment
JOIN transformed_data.dim_sales_channel c ON s.sales_channel = c.sales_channel;

--Fact Table: Reviews

INSERT INTO transformed_data.fact_reviews (product_key, user_key, profilename, helpfulnessnumerator, helpfulnessdenominator, score, time, summary, text)
SELECT 
    p.product_key, 
    u.user_key, 
    r.PROFILENAME, 
    r.HELPFULNESSNUMERATOR, 
    r.HELPFULNESSDENOMINATOR, 
    r.SCORE, 
    r.TIME, 
    r.SUMMARY, 
    r.TEXT
FROM raw_data.staging_reviews r
JOIN transformed_data.dim_products p ON r.PRODUCTID = p.product_id
JOIN transformed_data.dim_users u ON r.USERID = u.user_id;


--Analytical questions

--Total sales per category
SELECT  f.category,  SUM(f.amount) AS total_sales 
FROM  transformed_data.fact_sales f  
GROUP BY  f.category;


--Average review score per product, excluding NULL scores
SELECT p.product_id, AVG(r.score) AS average_score
FROM transformed_data.fact_reviews r
JOIN transformed_data.dim_products p ON r.product_key = p.product_key
WHERE r.score IS NOT NULL
GROUP BY p.product_id;


--Total sales by payment method
SELECT pm.payment_method, SUM(f.final_price) AS total_sales  -- Using final_price instead of price * qty
FROM transformed_data.fact_ecomm_sales f
JOIN transformed_data.dim_payment_methods pm ON f.payment_key = pm.payment_key
GROUP BY pm.payment_method;

--TESTING

--Verify Staging Tables (raw_data)
SELECT 'staging_ecomm' AS table_name, COUNT(*) AS total_rows FROM raw_data.staging_ecomm
UNION ALL
SELECT 'staging_reviews', COUNT(*) FROM raw_data.staging_reviews
UNION ALL
SELECT 'staging_sales', COUNT(*) FROM raw_data.staging_sales;

--Verify Data Cleaning & Null Handling

SELECT 
    SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS product_id_nulls,
    SUM(CASE WHEN final_price IS NULL THEN 1 ELSE 0 END) AS final_price_nulls
FROM raw_data.staging_ecomm;

--Test Dimension Tables (transformed_data)

SELECT COUNT(DISTINCT user_id), COUNT(user_id) FROM transformed_data.dim_users;
SELECT COUNT(DISTINCT product_id), COUNT(product_id) FROM transformed_data.dim_products;
SELECT COUNT(DISTINCT payment_method), COUNT(payment_method) FROM transformed_data.dim_payment_methods;

--Check if Foreign Keys Are Mapped Properly

SELECT COUNT(*) FROM transformed_data.fact_ecomm_sales f
LEFT JOIN transformed_data.dim_users u ON f.user_key = u.user_key
WHERE u.user_key IS NULL;

--Verify Fact Table Population
SELECT 'fact_ecomm_sales' AS table_name, COUNT(*) AS total_rows FROM transformed_data.fact_ecomm_sales
UNION ALL
SELECT 'fact_sales', COUNT(*) FROM transformed_data.fact_sales
UNION ALL
SELECT 'fact_reviews', COUNT(*) FROM transformed_data.fact_reviews;

--SHOW TABLES
SELECT * FROM transformed_data.fact_ecomm_sales LIMIT 5;
SELECT * FROM transformed_data.fact_sales LIMIT 5;
SELECT * FROM transformed_data.fact_reviews LIMIT 5;
