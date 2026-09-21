-- ============================================================
-- FILE: 01_revenue_and_sales.sql
-- PROJECT: Olist Sales & BI Platform
-- PURPOSE: Core revenue and sales performance analysis
-- QUERIES: Q1 through Q6
-- TECHNIQUES: SELECT, WHERE, GROUP BY, HAVING, ORDER BY,
--             JOINs, Subqueries, Aggregation, CASE WHEN
-- ============================================================
-- NOTE: Run via DuckDB. Tables are views over cleaned CSV files.
--       All revenue queries filter to order_status = 'delivered'.
-- ============================================================


-- ════════════════════════════════════════════════════════════════
-- Q1 | OVERALL BUSINESS KPIs
-- Business question: What is our total revenue, order volume, and
--                    average order value across the entire period?
-- Technique: Basic aggregation — SUM, COUNT, arithmetic
-- ════════════════════════════════════════════════════════════════
SELECT
    COUNT(DISTINCT o.order_id)                        AS total_orders,
    ROUND(SUM(p.total_payment), 2)                    AS total_revenue_brl,
    ROUND(SUM(p.total_payment) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value_brl,
    MIN(o.order_purchase_timestamp::DATE)             AS first_order_date,
    MAX(o.order_purchase_timestamp::DATE)             AS last_order_date
FROM orders o
-- Pre-aggregate payments to one row per order before joining
-- This prevents row multiplication (Phase 3 lesson)
JOIN (
    SELECT order_id, SUM(payment_value) AS total_payment
    FROM payments
    GROUP BY order_id
) p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered';


-- ════════════════════════════════════════════════════════════════
-- Q2 | MONTHLY REVENUE TREND
-- Business question: How has monthly revenue trended over time?
--                    Are we growing month over month?
-- Technique: GROUP BY date period, ORDER BY time
-- ════════════════════════════════════════════════════════════════
SELECT
    o.purchase_ym                                     AS year_month,
    COUNT(DISTINCT o.order_id)                        AS orders,
    ROUND(SUM(p.total_payment), 2)                    AS revenue_brl,
    ROUND(SUM(p.total_payment) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value_brl
FROM orders o
JOIN (
    SELECT order_id, SUM(payment_value) AS total_payment
    FROM payments
    GROUP BY order_id
) p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
  AND o.purchase_year IN (2017, 2018)   -- Focus on full years with complete data
GROUP BY o.purchase_ym
ORDER BY o.purchase_ym;


-- ════════════════════════════════════════════════════════════════
-- Q3 | QUARTERLY REVENUE BY YEAR
-- Business question: Which quarter of each year was strongest?
--                    How did quarterly performance change YoY?
-- Technique: Multi-column GROUP BY, CASE WHEN for labels
-- ════════════════════════════════════════════════════════════════
SELECT
    o.purchase_year                                   AS year,
    o.purchase_quarter                                AS quarter,
    CASE o.purchase_quarter
        WHEN 1 THEN 'Q1 (Jan-Mar)'
        WHEN 2 THEN 'Q2 (Apr-Jun)'
        WHEN 3 THEN 'Q3 (Jul-Sep)'
        WHEN 4 THEN 'Q4 (Oct-Dec)'
    END                                               AS quarter_label,
    COUNT(DISTINCT o.order_id)                        AS orders,
    ROUND(SUM(p.total_payment), 2)                    AS revenue_brl,
    ROUND(SUM(p.total_payment) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM orders o
JOIN (
    SELECT order_id, SUM(payment_value) AS total_payment
    FROM payments
    GROUP BY order_id
) p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
  AND o.purchase_year IN (2017, 2018)
GROUP BY o.purchase_year, o.purchase_quarter
ORDER BY o.purchase_year, o.purchase_quarter;


-- ════════════════════════════════════════════════════════════════
-- Q4 | TOP 10 PRODUCT CATEGORIES BY REVENUE
-- Business question: Which product categories generate the most
--                    revenue? Which have the highest AOV?
-- Technique: Multi-table JOIN (items → products → translation →
--             payments → orders), GROUP BY, ORDER BY, LIMIT
-- ════════════════════════════════════════════════════════════════
SELECT
    COALESCE(t.product_category_name_english, 'uncategorized') AS category,
    COUNT(DISTINCT i.order_id)                                  AS orders,
    ROUND(SUM(i.price), 2)                                      AS product_revenue_brl,
    ROUND(SUM(i.freight_value), 2)                              AS freight_revenue_brl,
    ROUND(SUM(i.price) + SUM(i.freight_value), 2)               AS total_item_revenue,
    ROUND(AVG(i.price), 2)                                      AS avg_unit_price,
    ROUND((SUM(i.price) + SUM(i.freight_value))
          / COUNT(DISTINCT i.order_id), 2)                      AS avg_order_value
FROM items i
JOIN products  pr ON i.product_id       = pr.product_id
LEFT JOIN translation t  ON pr.product_category_name = t.product_category_name
JOIN orders    o  ON i.order_id         = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY t.product_category_name_english, pr.product_category_name
ORDER BY product_revenue_brl DESC
LIMIT 10;


-- ════════════════════════════════════════════════════════════════
-- Q5 | REVENUE BY BRAZILIAN STATE
-- Business question: Which states generate the most revenue?
--                    Where are our customers concentrated?
-- Technique: JOIN orders → customers, GROUP BY state
-- ════════════════════════════════════════════════════════════════
SELECT
    c.customer_state                                  AS state,
    COUNT(DISTINCT o.order_id)                        AS orders,
    COUNT(DISTINCT c.customer_unique_id)              AS unique_customers,
    ROUND(SUM(p.total_payment), 2)                    AS revenue_brl,
    ROUND(SUM(p.total_payment)
          / COUNT(DISTINCT o.order_id), 2)            AS avg_order_value,
    ROUND(SUM(p.total_payment)
          / SUM(SUM(p.total_payment)) OVER () * 100, 2) AS pct_of_total_revenue
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN (
    SELECT order_id, SUM(payment_value) AS total_payment
    FROM payments GROUP BY order_id
) p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY revenue_brl DESC;


-- ════════════════════════════════════════════════════════════════
-- Q6 | TOP 15 SELLERS BY REVENUE
-- Business question: Which sellers generate the most revenue?
--                    Are we dependent on a small number of sellers?
-- Technique: JOIN items → payments → sellers, HAVING, subquery
--            for concentration check
-- ════════════════════════════════════════════════════════════════
WITH seller_revenue AS (
    -- Step 1: Calculate revenue per seller from delivered orders only
    SELECT
        i.seller_id,
        s.seller_state,
        COUNT(DISTINCT i.order_id)               AS orders_fulfilled,
        COUNT(DISTINCT i.product_id)             AS distinct_products,
        ROUND(SUM(i.price), 2)                   AS product_revenue,
        ROUND(SUM(i.freight_value), 2)           AS freight_revenue,
        ROUND(SUM(i.price) + SUM(i.freight_value), 2) AS total_revenue
    FROM items i
    JOIN sellers s ON i.seller_id = s.seller_id
    JOIN orders  o ON i.order_id  = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY i.seller_id, s.seller_state
),
total AS (
    -- Step 2: Get the total for percentage calculation
    SELECT SUM(total_revenue) AS grand_total FROM seller_revenue
)
SELECT
    sr.seller_id,
    sr.seller_state,
    sr.orders_fulfilled,
    sr.distinct_products,
    sr.total_revenue,
    ROUND(sr.total_revenue / t.grand_total * 100, 2) AS pct_of_total,
    -- Running total: cumulative revenue contribution
    ROUND(SUM(sr.total_revenue) OVER (ORDER BY sr.total_revenue DESC
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / t.grand_total * 100, 2)                   AS cumulative_pct
FROM seller_revenue sr
CROSS JOIN total t
ORDER BY sr.total_revenue DESC
LIMIT 15;
