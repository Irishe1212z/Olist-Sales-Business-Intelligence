-- ============================================================
-- FILE: 04_advanced_window_functions.sql
-- PROJECT: Olist Sales & BI Platform
-- PURPOSE: Advanced analytics using SQL window functions
-- QUERIES: Q18 through Q20
-- TECHNIQUES: LAG, LEAD, RANK, DENSE_RANK, NTILE,
--             Running totals (SUM OVER), PARTITION BY,
--             CTEs chained together, conditional aggregation
-- ============================================================


-- ════════════════════════════════════════════════════════════════
-- Q18 | MONTH-OVER-MONTH REVENUE GROWTH RATE
-- Business question: How fast is revenue growing month over month?
--                    Which months had the highest growth spikes?
--                    Which months saw revenue decline?
-- Technique: LAG window function to access prior month's revenue,
--            arithmetic to calculate growth rate
-- ════════════════════════════════════════════════════════════════
WITH monthly_revenue AS (
    -- Step 1: Aggregate revenue by month (using purchase_ym derived column from cleaned data)
    SELECT
        o.purchase_ym                                AS year_month,
        COUNT(DISTINCT o.order_id)                   AS orders,
        ROUND(SUM(p.payment_value), 2)               AS revenue
    FROM orders o
    JOIN payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
      AND o.purchase_year IN (2017, 2018)
    GROUP BY o.purchase_ym
),
-- Step 2: Add window function columns in a second CTE
-- (DuckDB requires window functions in a separate scope from the aggregation)
with_lag AS (
    SELECT
        year_month,
        orders,
        revenue,
        LAG(revenue) OVER (ORDER BY year_month)      AS prev_month_revenue
    FROM monthly_revenue
)
SELECT
    year_month,
    orders,
    revenue,
    prev_month_revenue,
    ROUND(revenue - prev_month_revenue, 2)           AS revenue_change,
    ROUND(
        (revenue - prev_month_revenue)
        / NULLIF(prev_month_revenue, 0) * 100, 2
    )                                                AS mom_growth_pct,
    ROUND(SUM(revenue) OVER (
        ORDER BY year_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2)                                            AS cumulative_revenue
FROM with_lag
ORDER BY year_month;


-- ════════════════════════════════════════════════════════════════
-- Q19 | YEAR-OVER-YEAR REVENUE COMPARISON
-- Business question: How did 2018 revenue compare to 2017?
--                    Which months showed the strongest YoY growth?
-- Technique: CTEs to isolate each year, conditional aggregation
--            (pivot-style) to align months side by side
-- ════════════════════════════════════════════════════════════════
WITH monthly_by_year AS (
    SELECT
        o.purchase_month                             AS month,
        o.purchase_year                              AS year,
        ROUND(SUM(p.payment_value), 2)               AS revenue
    FROM orders o
    JOIN payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
      AND o.purchase_year IN (2017, 2018)
    GROUP BY o.purchase_month, o.purchase_year
)
SELECT
    month,
    CASE month
        WHEN 1 THEN 'January'    WHEN 2 THEN 'February'
        WHEN 3 THEN 'March'      WHEN 4 THEN 'April'
        WHEN 5 THEN 'May'        WHEN 6 THEN 'June'
        WHEN 7 THEN 'July'       WHEN 8 THEN 'August'
        WHEN 9 THEN 'September'  WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'  WHEN 12 THEN 'December'
    END                                              AS month_name,
    -- Conditional aggregation: pivot revenue by year
    ROUND(SUM(CASE WHEN year = 2017 THEN revenue ELSE 0 END), 2) AS revenue_2017,
    ROUND(SUM(CASE WHEN year = 2018 THEN revenue ELSE 0 END), 2) AS revenue_2018,
    -- YoY change and growth rate
    ROUND(
        SUM(CASE WHEN year = 2018 THEN revenue ELSE 0 END) -
        SUM(CASE WHEN year = 2017 THEN revenue ELSE 0 END), 2
    )                                                AS yoy_change,
    ROUND(
        (SUM(CASE WHEN year = 2018 THEN revenue ELSE 0 END) -
         SUM(CASE WHEN year = 2017 THEN revenue ELSE 0 END))
        / NULLIF(SUM(CASE WHEN year = 2017 THEN revenue ELSE 0 END), 0)
        * 100, 2
    )                                                AS yoy_growth_pct
FROM monthly_by_year
GROUP BY month
ORDER BY month;


-- ════════════════════════════════════════════════════════════════
-- Q20 | CATEGORY REVENUE RANKING BY YEAR (PARTITION BY)
-- Business question: Did the top product categories remain
--                    consistent between 2017 and 2018, or did
--                    the rankings change?
-- Technique: DENSE_RANK() with PARTITION BY year — ranks reset
--            within each year independently.
--            LEAD() to show next year's rank for comparison.
-- ════════════════════════════════════════════════════════════════
WITH category_year_revenue AS (
    -- Step 1: Revenue per category per year
    SELECT
        COALESCE(t.product_category_name_english, 'uncategorized') AS category,
        o.purchase_year                                             AS year,
        ROUND(SUM(i.price), 2)                                      AS revenue,
        COUNT(DISTINCT i.order_id)                                  AS orders
    FROM items i
    JOIN products    pr ON i.product_id          = pr.product_id
    LEFT JOIN translation t ON pr.product_category_name = t.product_category_name
    JOIN orders      o  ON i.order_id            = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.purchase_year IN (2017, 2018)
    GROUP BY t.product_category_name_english, pr.product_category_name, o.purchase_year
),
ranked AS (
    -- Step 2: Rank within each year using PARTITION BY
    SELECT
        category,
        year,
        revenue,
        orders,
        DENSE_RANK() OVER (
            PARTITION BY year          -- Rank resets for each year
            ORDER BY revenue DESC
        )                              AS revenue_rank
    FROM category_year_revenue
)
-- Step 3: Show 2017 vs 2018 side by side for top 15 categories
SELECT
    r17.revenue_rank                              AS rank_2017,
    r17.category,
    ROUND(r17.revenue, 2)                         AS revenue_2017,
    r18.revenue_rank                              AS rank_2018,
    ROUND(r18.revenue, 2)                         AS revenue_2018,
    -- Rank movement: negative = improved, positive = dropped
    r17.revenue_rank - r18.revenue_rank           AS rank_improvement,
    ROUND(
        (r18.revenue - r17.revenue) / NULLIF(r17.revenue, 0) * 100, 1
    )                                             AS revenue_growth_pct
FROM ranked r17
LEFT JOIN ranked r18
    ON r17.category = r18.category
    AND r18.year = 2018
WHERE r17.year = 2017
  AND r17.revenue_rank <= 15
ORDER BY r17.revenue_rank;
