-- ============================================================
-- PROJECT: Meesho Supplier Performance & RTO Loss Analysis
-- PROBLEM: A Meesho supplier is losing ~48% revenue due to
--          RTO (Return to Origin) & customer returns.
--          This project identifies WHERE, WHY, and WHAT
--          products drive maximum losses — and which states
--          & products are most profitable.
-- DATASET: Real Meesho August 2022 supplier data
-- AUTHOR : [Your Name]
-- TOOL   : MySQL Workbench
-- ============================================================


-- ============================================================
-- STEP 1: CREATE DATABASE & TABLES
-- ============================================================

CREATE DATABASE IF NOT EXISTS meesho_analysis;
USE meesho_analysis;

-- Table 1: All Orders (from ForwardReports)
CREATE TABLE IF NOT EXISTS orders (
    order_id           INT PRIMARY KEY,
    sub_order_num      VARCHAR(50) UNIQUE,
    order_date         DATE,
    order_status       VARCHAR(30),
    state              VARCHAR(60),
    pincode            INT,
    gst_amount         DECIMAL(10,2),
    meesho_price       DECIMAL(10,2),
    shipping_charges   DECIMAL(10,2),
    total_price        DECIMAL(10,2)
);

-- Table 2: Order Items with Product Details (from Orders_Aug)
CREATE TABLE IF NOT EXISTS order_items (
    item_id            INT PRIMARY KEY,
    sub_order_num      VARCHAR(50),
    product_name       TEXT,
    sku                VARCHAR(50),
    size               VARCHAR(30),
    quantity           INT,
    listed_price       DECIMAL(10,2),
    discounted_price   DECIMAL(10,2),
    credit_reason      VARCHAR(30),
    FOREIGN KEY (sub_order_num) REFERENCES orders(sub_order_num)
        ON DELETE CASCADE
);

-- Table 3: Products Master
CREATE TABLE IF NOT EXISTS products (
    product_id         INT PRIMARY KEY,
    sku                VARCHAR(50) UNIQUE,
    product_name       TEXT,
    category           VARCHAR(30),
    avg_listed_price   DECIMAL(10,2),
    avg_discounted_price DECIMAL(10,2)
);

-- Table 4: State-Region Mapping
CREATE TABLE IF NOT EXISTS states (
    state_id           INT PRIMARY KEY,
    state_name         VARCHAR(60),
    region             VARCHAR(20)
);

-- Table 5: Returns (RTO + Customer Returns)
CREATE TABLE IF NOT EXISTS returns (
    return_id          INT PRIMARY KEY,
    sub_order_num      VARCHAR(50),
    order_date         DATE,
    state              VARCHAR(60),
    return_type        VARCHAR(30),
    revenue_lost       DECIMAL(10,2)
);


-- ============================================================
-- STEP 2: LOAD DATA
-- (Import CSVs via MySQL Workbench: Table Data Import Wizard)
-- OR use LOAD DATA INFILE if local_infile is enabled:
--
-- LOAD DATA LOCAL INFILE '/path/to/orders.csv'
-- INTO TABLE orders FIELDS TERMINATED BY ','
-- ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS
-- (order_id, sub_order_num, order_date, order_status, state,
--  pincode, gst_amount, meesho_price, shipping_charges, total_price);
-- ============================================================


-- ============================================================
-- STEP 3: BUSINESS QUERIES (10 Queries)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- Q1. Overall Order Status Summary
-- BUSINESS QUESTION: What % of orders are profitable vs lost?
-- ─────────────────────────────────────────────────────────────
SELECT
    order_status,
    COUNT(*)                                          AS total_orders,
    SUM(meesho_price)                                 AS revenue,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders,
    ROUND(SUM(meesho_price) * 100.0 / SUM(SUM(meesho_price)) OVER (), 2) AS pct_of_revenue
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;


-- ─────────────────────────────────────────────────────────────
-- Q2. Total Revenue vs Revenue Lost to Returns/RTO
-- BUSINESS QUESTION: How much money is the supplier losing?
-- ─────────────────────────────────────────────────────────────
SELECT
    SUM(CASE WHEN order_status = 'Delivered' THEN meesho_price ELSE 0 END) AS revenue_earned,
    SUM(CASE WHEN order_status IN ('rto','Return') THEN meesho_price ELSE 0 END) AS revenue_lost,
    SUM(CASE WHEN order_status = 'Cancelled' THEN meesho_price ELSE 0 END) AS revenue_cancelled,
    SUM(meesho_price) AS total_potential_revenue,
    ROUND(
        SUM(CASE WHEN order_status IN ('rto','Return') THEN meesho_price ELSE 0 END)
        * 100.0 / SUM(meesho_price), 2
    ) AS return_loss_pct
FROM orders;


-- ─────────────────────────────────────────────────────────────
-- Q3. State-wise Order Performance (Top 10)
-- BUSINESS QUESTION: Which states bring profit and which cause loss?
-- ─────────────────────────────────────────────────────────────
SELECT
    o.state,
    s.region,
    COUNT(*)                                              AS total_orders,
    SUM(CASE WHEN o.order_status = 'Delivered' THEN 1 ELSE 0 END) AS delivered,
    SUM(CASE WHEN o.order_status IN ('rto','Return') THEN 1 ELSE 0 END) AS returns,
    ROUND(
        SUM(CASE WHEN o.order_status IN ('rto','Return') THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    ) AS return_rate_pct,
    SUM(o.meesho_price)                                   AS total_revenue
FROM orders o
LEFT JOIN states s ON o.state = s.state_name
GROUP BY o.state, s.region
ORDER BY return_rate_pct DESC
LIMIT 10;


-- ─────────────────────────────────────────────────────────────
-- Q4. Region-wise Revenue Summary
-- BUSINESS QUESTION: Which geographic region is most profitable?
-- ─────────────────────────────────────────────────────────────
SELECT
    s.region,
    COUNT(o.order_id)          AS total_orders,
    SUM(o.meesho_price)        AS total_revenue,
    SUM(o.gst_amount)          AS total_gst,
    SUM(o.shipping_charges)    AS total_shipping,
    ROUND(AVG(o.meesho_price), 2) AS avg_order_value
FROM orders o
JOIN states s ON o.state = s.state_name
GROUP BY s.region
ORDER BY total_revenue DESC;


-- ─────────────────────────────────────────────────────────────
-- Q5. Top 5 Products by Revenue (using JOINed data)
-- BUSINESS QUESTION: Which products generate most revenue?
-- ─────────────────────────────────────────────────────────────
SELECT
    sku,
    SUM(quantity)                      AS total_qty_sold,
    SUM(discounted_price)              AS total_revenue,
    ROUND(AVG(discounted_price), 2)    AS avg_selling_price
FROM order_items
GROUP BY sku
ORDER BY total_revenue DESC
LIMIT 5;


-- ─────────────────────────────────────────────────────────────
-- Q6. RTO Analysis by State — WHERE are returns happening most?
-- BUSINESS QUESTION: Should the supplier stop selling to certain states?
-- ─────────────────────────────────────────────────────────────
SELECT
    state,
    return_type,
    COUNT(*)           AS return_count,
    SUM(revenue_lost)  AS total_loss,
    RANK() OVER (PARTITION BY return_type ORDER BY SUM(revenue_lost) DESC) AS loss_rank
FROM returns
GROUP BY state, return_type
ORDER BY total_loss DESC
LIMIT 10;


-- ─────────────────────────────────────────────────────────────
-- Q7. Weekly Order Trend (Aug 2022)
-- BUSINESS QUESTION: Which week had peak orders and peak returns?
-- ─────────────────────────────────────────────────────────────
SELECT
    WEEK(order_date)                AS week_number,
    MIN(order_date)                 AS week_start,
    COUNT(*)                        AS total_orders,
    SUM(CASE WHEN order_status = 'Delivered' THEN 1 ELSE 0 END)          AS delivered,
    SUM(CASE WHEN order_status IN ('rto','Return') THEN 1 ELSE 0 END)    AS returned,
    SUM(meesho_price)               AS weekly_revenue
FROM orders
WHERE order_date BETWEEN '2022-08-01' AND '2022-08-31'
GROUP BY WEEK(order_date)
ORDER BY week_number;


-- ─────────────────────────────────────────────────────────────
-- Q8. Size-wise Return Analysis
-- BUSINESS QUESTION: Which clothing sizes get returned the most?
-- ─────────────────────────────────────────────────────────────
SELECT
    size,
    COUNT(*)                                AS total_orders,
    SUM(CASE WHEN credit_reason = 'RTO_COMPLETE' OR credit_reason = 'RTO_LOCKED' THEN 1 ELSE 0 END) AS rto_count,
    SUM(CASE WHEN credit_reason = 'CANCELLED' THEN 1 ELSE 0 END)  AS cancelled_count
FROM order_items
GROUP BY size
ORDER BY total_orders DESC;


-- ─────────────────────────────────────────────────────────────
-- Q9. CTE — Supplier Profit Estimate per Order
-- BUSINESS QUESTION: After GST + shipping, what is actual net per order?
-- ─────────────────────────────────────────────────────────────
WITH profit_cte AS (
    SELECT
        sub_order_num,
        order_date,
        state,
        order_status,
        meesho_price,
        gst_amount,
        shipping_charges,
        (meesho_price - gst_amount - shipping_charges) AS estimated_net_profit
    FROM orders
    WHERE order_status = 'Delivered'
)
SELECT
    state,
    COUNT(*)                              AS delivered_orders,
    ROUND(SUM(estimated_net_profit), 2)   AS total_net_profit,
    ROUND(AVG(estimated_net_profit), 2)   AS avg_profit_per_order,
    ROUND(MIN(estimated_net_profit), 2)   AS min_profit,
    ROUND(MAX(estimated_net_profit), 2)   AS max_profit
FROM profit_cte
GROUP BY state
ORDER BY total_net_profit DESC
LIMIT 10;


-- ─────────────────────────────────────────────────────────────
-- Q10. Final Business Dashboard Query
-- BUSINESS QUESTION: Give a complete supplier health scorecard
-- ─────────────────────────────────────────────────────────────
WITH summary AS (
    SELECT
        COUNT(*)                                                              AS total_orders,
        SUM(CASE WHEN order_status = 'Delivered' THEN 1 ELSE 0 END)          AS delivered,
        SUM(CASE WHEN order_status IN ('rto','Return') THEN 1 ELSE 0 END)    AS returns,
        SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END)          AS cancelled,
        SUM(CASE WHEN order_status = 'Shipped' THEN 1 ELSE 0 END)            AS in_transit,
        SUM(meesho_price)                                                     AS gross_revenue,
        SUM(gst_amount)                                                       AS total_gst,
        SUM(shipping_charges)                                                 AS total_shipping,
        SUM(CASE WHEN order_status = 'Delivered'
            THEN meesho_price - gst_amount - shipping_charges ELSE 0 END)    AS net_profit
    FROM orders
)
SELECT
    total_orders,
    delivered,
    returns,
    cancelled,
    in_transit,
    ROUND(delivered * 100.0 / total_orders, 1)  AS delivery_rate_pct,
    ROUND(returns   * 100.0 / total_orders, 1)  AS return_rate_pct,
    gross_revenue,
    total_gst,
    total_shipping,
    ROUND(net_profit, 2)                        AS estimated_net_profit,
    ROUND(net_profit * 100.0 / gross_revenue, 1) AS profit_margin_pct
FROM summary;


-- ============================================================
-- KEY FINDINGS (Document these in your GitHub README)
-- ============================================================
-- 1. Only 36.2% of orders were delivered successfully
-- 2. ~40.5% of orders were RTO or Returns (revenue lost: ₹85,764)
-- 3. Uttar Pradesh & Tamil Nadu = highest order volume states
-- 4. Free Size & Semi-Stitched items have highest non-delivery rate
-- 5. Net profit margin after GST + shipping is significantly low
-- 6. Party Wear Gown (SKU: hk1446 type) = top revenue product
-- ============================================================
