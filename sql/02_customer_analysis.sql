-- ============================================================
-- FILE: 02_customer_analysis.sql
-- PROJECT: Olist Sales & BI Platform
-- PURPOSE: Customer behaviour, loyalty, and segmentation
-- QUERIES: Q7 through Q12
-- TECHNIQUES: CTEs, CASE WHEN, Subqueries, Window Functions
--             (ROW_NUMBER, NTILE, LAG), GROUP BY HAVING
-- ============================================================


-- ════════════════════════════════════════════════════════════════
-- Q7 | REPEAT VS ONE-TIME CUSTOMERS
-- Business question: What proportion of our customers came back
--                    to buy again? Are we retaining customers?
-- Technique: CTE to count orders per unique customer, then
--            CASE WHEN to classify, then aggregate
-- ════════════════════════════════════════════════════════════════
WITH customer_orders AS (
    -- Step 1: Count how many delivered orders each real person placed
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
classified AS (
    -- Step 2: Classify each customer as one-time or repeat
    SELECT
        customer_unique_id,
        order_count,
        CASE
            WHEN order_count = 1 THEN 'One-time buyer'
            WHEN order_count = 2 THEN 'Two purchases'
            WHEN order_count BETWEEN 3 AND 5 THEN 'Loyal (3-5 orders)'
            ELSE 'Very loyal (6+ orders)'
        END AS customer_segment
    FROM customer_orders
)
-- Step 3: Summarise
SELECT
    customer_segment,
    COUNT(*)                                          AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_customers,
    SUM(order_count)                                  AS total_orders_placed,
    ROUND(AVG(order_count), 2)                        AS avg_orders_per_customer
FROM classified
GROUP BY customer_segment
ORDER BY MIN(order_count);


-- ════════════════════════════════════════════════════════════════
-- Q8 | REVENUE CONCENTRATION — PARETO ANALYSIS
-- Business question: Do a small number of customers drive most
--                    of our revenue? (The 80/20 principle)
-- Technique: CTE → NTILE(10) to split into revenue deciles →
--            aggregate by decile
-- ════════════════════════════════════════════════════════════════
WITH customer_revenue AS (
    -- Step 1: Total revenue per unique customer
    SELECT
        c.customer_unique_id,
        ROUND(SUM(p.payment_value), 2) AS lifetime_revenue
    FROM customers c
    JOIN orders    o ON c.customer_id  = o.customer_id
    JOIN payments  p ON o.order_id     = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
deciled AS (
    -- Step 2: Assign each customer to a revenue decile (1=lowest, 10=highest)
    SELECT
        customer_unique_id,
        lifetime_revenue,
        NTILE(10) OVER (ORDER BY lifetime_revenue ASC) AS revenue_decile
    FROM customer_revenue
)
-- Step 3: Aggregate by decile to show revenue concentration
SELECT
    revenue_decile,
    CASE revenue_decile
        WHEN 10 THEN 'Top 10%'
        WHEN 9  THEN 'Next 10% (80-90th pct)'
        ELSE         'Bottom 80%'
    END                                                  AS decile_label,
    COUNT(*)                                             AS customers,
    ROUND(SUM(lifetime_revenue), 2)                      AS segment_revenue,
    ROUND(SUM(lifetime_revenue) * 100.0
          / SUM(SUM(lifetime_revenue)) OVER(), 2)        AS pct_of_total_revenue,
    ROUND(AVG(lifetime_revenue), 2)                      AS avg_revenue_per_customer,
    ROUND(MIN(lifetime_revenue), 2)                      AS min_revenue,
    ROUND(MAX(lifetime_revenue), 2)                      AS max_revenue
FROM deciled
GROUP BY revenue_decile
ORDER BY revenue_decile DESC;


-- ════════════════════════════════════════════════════════════════
-- Q9 | PURCHASE FREQUENCY DISTRIBUTION
-- Business question: How often do customers buy? Is purchase
--                    frequency clustered at 1 or spread across
--                    multiple orders?
-- Technique: CTE → GROUP BY frequency → percentage of customers
-- ════════════════════════════════════════════════════════════════
WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    order_count                                           AS purchases,
    COUNT(*)                                             AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)   AS pct_of_customers,
    -- Cumulative: what % of customers have bought N or fewer times?
    ROUND(SUM(COUNT(*)) OVER (ORDER BY order_count
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          * 100.0 / SUM(COUNT(*)) OVER(), 2)             AS cumulative_pct
FROM customer_order_counts
GROUP BY order_count
ORDER BY order_count;


-- ════════════════════════════════════════════════════════════════
-- Q10 | DAYS BETWEEN FIRST AND SECOND PURCHASE
-- Business question: For customers who returned, how long did it
--                    take them to come back? This informs the
--                    timing of retention marketing.
-- Technique: ROW_NUMBER() to rank orders per customer,
--            self-join to align first and second purchase,
--            DATE arithmetic
-- ════════════════════════════════════════════════════════════════
WITH ranked_orders AS (
    -- Step 1: Rank each customer's orders chronologically
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS purchase_rank
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
first_orders AS (
    SELECT customer_unique_id, order_purchase_timestamp AS first_purchase_date
    FROM ranked_orders WHERE purchase_rank = 1
),
second_orders AS (
    SELECT customer_unique_id, order_purchase_timestamp AS second_purchase_date
    FROM ranked_orders WHERE purchase_rank = 2
)
-- Step 2: Join first and second orders, calculate the gap
SELECT
    COUNT(*)                                          AS repeat_customers,
    ROUND(AVG(
        DATEDIFF('day', fo.first_purchase_date, so.second_purchase_date)
    ), 1)                                             AS avg_days_to_return,
    MIN(
        DATEDIFF('day', fo.first_purchase_date, so.second_purchase_date)
    )                                                 AS min_days_to_return,
    MAX(
        DATEDIFF('day', fo.first_purchase_date, so.second_purchase_date)
    )                                                 AS max_days_to_return,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY
        DATEDIFF('day', fo.first_purchase_date, so.second_purchase_date)
    )                                                 AS median_days_to_return
FROM first_orders fo
JOIN second_orders so USING (customer_unique_id);


-- ════════════════════════════════════════════════════════════════
-- Q11 | TOP 20 CUSTOMERS BY REVENUE (DENSE_RANK)
-- Business question: Who are our highest-value individual customers?
--                    What is their revenue and order frequency?
-- Technique: CTE + DENSE_RANK window function
-- ════════════════════════════════════════════════════════════════
WITH customer_metrics AS (
    SELECT
        c.customer_unique_id,
        c.customer_state,
        COUNT(DISTINCT o.order_id)             AS total_orders,
        ROUND(SUM(p.payment_value), 2)         AS lifetime_revenue,
        MIN(o.order_purchase_timestamp::DATE)  AS first_order_date,
        MAX(o.order_purchase_timestamp::DATE)  AS last_order_date
    FROM customers c
    JOIN orders   o ON c.customer_id  = o.customer_id
    JOIN payments p ON o.order_id     = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, c.customer_state
)
SELECT
    DENSE_RANK() OVER (ORDER BY lifetime_revenue DESC) AS revenue_rank,
    customer_unique_id,
    customer_state,
    total_orders,
    lifetime_revenue,
    ROUND(lifetime_revenue / total_orders, 2)          AS avg_order_value,
    first_order_date,
    last_order_date
FROM customer_metrics
ORDER BY lifetime_revenue DESC
LIMIT 20;


-- ════════════════════════════════════════════════════════════════
-- Q12 | CUSTOMER ACQUISITION TREND — FIRST ORDER BY MONTH
-- Business question: How many new customers did we acquire each
--                    month? Is acquisition accelerating?
-- Technique: CTE to find each customer's first order date,
--            then GROUP BY month
-- ════════════════════════════════════════════════════════════════
WITH first_purchase AS (
    -- Each customer's very first delivered order
    SELECT
        c.customer_unique_id,
        MIN(o.purchase_ym)  AS first_purchase_ym,
        MIN(o.purchase_year) AS first_purchase_year
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    first_purchase_ym                                  AS month,
    COUNT(*)                                           AS new_customers,
    -- Running total of customer base
    SUM(COUNT(*)) OVER (
        ORDER BY first_purchase_ym
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                  AS cumulative_customers
FROM first_purchase
WHERE first_purchase_year IN (2017, 2018)
GROUP BY first_purchase_ym
ORDER BY first_purchase_ym;
