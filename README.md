# E-commerce Data Warehouse

📌 Project Overview
This project implements a Kimball-style Data Warehouse for an E-commerce Platform using MySQL. It includes staging tables, dimension tables, and fact tables to store and analyze sales, reviews, and transaction data.

📂 Database Structure
The database consists of two schemas:
raw_data → Contains staging tables for raw input data.
transformed_data → Stores cleaned and structured data for analytics.

📌 Staging Tables (raw_data)
staging_ecomm → Stores raw e-commerce transactions.
staging_reviews → Stores raw product review data.
staging_sales → Stores raw sales transaction data.

![alt text](image-4.png)

📌 Dimension Tables (transformed_data)
dim_users → Stores unique users.
dim_products → Stores unique products.
dim_payment_methods → Stores payment methods.
dim_sales_channel → Stores sales channels.
dim_fulfillment → Stores fulfillment types.

![alt text](image-2.png)

📌 Fact Tables (transformed_data)
fact_ecomm_sales → Stores processed e-commerce sales data.
fact_sales → Stores detailed transactional sales data.
fact_reviews → Stores product review data for analysis.

![alt text](image-3.png)

🔄 ETL Process
Extract raw data into staging tables.
Transform data using SQL queries (cleaning, deduplication, key mapping).
Load transformed data into dimension and fact tables.

Null values
![alt text](image-5.png)

SELECT * FROM transformed_data.fact_ecomm_sales LIMIT 10;
![alt text](image-6.png)

SELECT * FROM transformed_data.fact_sales LIMIT 10;
![alt text](image-7.png)

SELECT * FROM transformed_data.fact_reviews LIMIT 10;
![alt text](image-8.png)

📊 Analytical Queries
Total Sales Per Category
![alt text](image-10.png)

Average Review Score Per Product
![alt text](image-9.png)

Total Sales by Payment Method
![alt text](image-11.png)


📈 Power BI Dashboards
1️⃣ Sales Performance Dashboard
📌 KPIs:
✔️ Total Revenue → SUM(fact_sales.amount)
✔️ Total Orders → COUNT(fact_sales.orderid)
✔️ Average Order Value → SUM(fact_sales.amount) / COUNT(fact_sales.orderid)

📌 Charts:
📊 Sales by Category → Bar Chart (category, SUM(amount))
🌍 Sales by Region → Map (ship_city, SUM(amount))
📉 Sales Trend Over Time → Line Chart (date, SUM(amount))

2️⃣ Customer Analytics Dashboard
📌 KPIs:
✔️ Total Customers → COUNT(DISTINCT dim_users.user_id)

📌 Charts:
💳 Preferred Payment Methods → Pie Chart (payment_method, SUM(final_price))

3️⃣ Product & Reviews Dashboard
📌 KPIs:
✔️ Total Products Sold → COUNT(fact_ecomm_sales.product_key)
✔️ Average Product Rating → AVG(fact_reviews.score)

![alt text](image-1.png)

⚡ Installation & Usage
Clone the repository:

git clone https://github.com/utkarshgupta28/ecommerce-datawarehouse.git

Set up the database in MySQL:

CREATE DATABASE ecommerce_dw;

Run the provided SQL scripts to create schemas, tables, and load data.

📜 ERD (Entity Relationship Diagram)

![alt text](image.png)
