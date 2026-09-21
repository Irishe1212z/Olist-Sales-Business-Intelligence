-- ============================================================
-- FILE: 03_profitability_operations.sql
-- PROJECT: Olist Sales & BI Platform
-- PURPOSE: Profitability, freight costs, delivery, satisfaction
-- QUERIES: Q13 through Q17
-- TECHNIQUES: CTEs, CASE WHEN, HAVING, date arithmetic,
--             conditional aggregation, subqueries
-- ============================================================


-- ════════════════════════════════════════════════════════════════
-- Q13 | FREIGHT-TO-REVENUE RATIO BY CATEGORY
-- Business question: Which product categories have disproportionately
--                    high freight costs relative to product price?
--                    Where are our logistics costs hurting margins?
-- Technique: Multi-table JOIN, ratio calculation, HAVING to filter
--            categories with enough volume, ORDER BY ratio DESC
-- ════════════════════════════════════════════════════════════════
SELECT
    COALESCE(t.product_category_name_english, 'uncategorized') AS category,
    COUNT(DISTINCT i.order_id)                                  AS orders,
    ROUND(SUM(i.price), 2)                                      AS product_revenue,
    ROUND(SUM(i.freight_value), 2)                              AS freight_cost,
    ROUND(SUM(i.freight_value) / SUM(i.price) * 100, 2)        AS freight_to_revenue_pct,
    ROUND(AVG(i.price), 2)                                      AS avg_unit_price,
    ROUND(AVG(i.freight_value), 2)                              AS avg_freight_per_item
FROM items i
JOIN products    pr ON i.product_id          = pr.product_id
LEFT JOIN translation t ON pr.product_category_name = t.product_category_name
JOIN orders      o  ON i.order_id            = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY t.product_category_name_english, pr.product_category_name
HAVING COUNT(DISTINCT i.order_id) >= 100   -- Only categories with meaningful volume
ORDER BY freight_to_revenue_pct DESC
LIMIT 15;


-- ════════════════════════════════════════════════════════════════
-- Q14 | ON-TIME DELIVERY RATE BY STATE
-- Business question: Which Brazilian states have the worst delivery
--                    performance? Where should we invest in logistics?
-- Technique: JOIN, conditional aggregation using AVG on 1/0 flag,
--            HAVING for minimum volume, ORDER BY performance
-- ════════════════════════════════════════════════════════════════
SELECT
    c.customer_state                                      AS state,
    COUNT(DISTINCT o.order_id)                            AS delivered_orders,
    ROUND(AVG(o.delivery_days), 1)                        AS avg_delivery_days,
    MIN(o.delivery_days)                                  AS min_delivery_days,
    MAX(o.delivery_days)                                  AS max_delivery_days,
    -- AVG of 1/0 flag = on-time rate
    ROUND(AVG(o.delivered_on_time) * 100, 1)             AS on_time_delivery_pct,
    -- Average delay for late deliveries only
    ROUND(AVG(
        CASE WHEN o.delivered_on_time = 0
        THEN (o.delivery_days -
              DATEDIFF('day', o.order_purchase_timestamp,
                       o.order_estimated_delivery_date))
        END
    ), 1)                                                AS avg_days_late_when_late
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL   -- Exclude the 8 edge cases
HAVING COUNT(DISTINCT o.order_id) >= 200            -- States with enough volume
GROUP BY c.customer_state
ORDER BY on_time_delivery_pct ASC;


-- ════════════════════════════════════════════════════════════════
-- Q15 | REVIEW SCORE DISTRIBUTION
-- Business question: What is the distribution of customer review
--                    scores? What proportion of customers are
--                    satisfied (4-5 stars) vs unhappy (1-2 stars)?
-- Technique: GROUP BY, CASE WHEN for satisfaction bucket,
--            subquery for total count
-- ════════════════════════════════════════════════════════════════
SELECT
    r.review_score,
    CASE
        WHEN r.review_score >= 4 THEN '😊 Satisfied'
        WHEN r.review_score = 3  THEN '😐 Neutral'
        ELSE                          '😞 Unhappy'
    END                                                    AS sentiment,
    COUNT(*)                                               AS reviews,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)     AS pct_of_reviews
FROM reviews r
JOIN orders  o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY r.review_score
ORDER BY r.review_score DESC;


-- ════════════════════════════════════════════════════════════════
-- Q16 | DELIVERY PERFORMANCE vs REVIEW SCORE
-- Business question: Do customers who received late orders give
--                    lower review scores? Quantify the impact of
--                    delivery delays on customer satisfaction.
-- Technique: JOIN orders → reviews, CASE WHEN on on_time flag,
--            GROUP BY + AVG to compare satisfaction
-- ════════════════════════════════════════════════════════════════
SELECT
    CASE o.delivered_on_time
        WHEN 1 THEN 'Delivered On Time'
        WHEN 0 THEN 'Delivered Late'
        ELSE 'Unknown'
    END                                                    AS delivery_status,
    COUNT(DISTINCT o.order_id)                             AS orders,
    ROUND(AVG(o.delivery_days), 1)                         AS avg_delivery_days,
    ROUND(AVG(r.review_score), 3)                          AS avg_review_score,
    COUNT(CASE WHEN r.review_score >= 4 THEN 1 END)        AS satisfied_reviews,
    COUNT(CASE WHEN r.review_score <= 2 THEN 1 END)        AS unhappy_reviews,
    ROUND(COUNT(CASE WHEN r.review_score >= 4 THEN 1 END)
          * 100.0 / COUNT(*), 1)                           AS pct_satisfied
FROM orders o
LEFT JOIN reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.delivered_on_time IS NOT NULL
GROUP BY o.delivered_on_time
ORDER BY o.delivered_on_time DESC;


-- ════════════════════════════════════════════════════════════════
-- Q17 | PAYMENT BEHAVIOUR ANALYSIS
-- Business question: Does payment method or number of installments
--                    correlate with higher order values?
--                    Do installment buyers spend more?
-- Technique: GROUP BY payment_type, CASE WHEN for installment
--            buckets, aggregation
-- ════════════════════════════════════════════════════════════════
-- Part A: Revenue and order volume by payment type
SELECT
    'By Payment Type'                                     AS analysis,
    payment_type,
    COUNT(DISTINCT order_id)                              AS orders,
    ROUND(SUM(payment_value), 2)                          AS total_revenue,
    ROUND(AVG(payment_value), 2)                          AS avg_payment_value,
    ROUND(AVG(payment_installments), 1)                   AS avg_installments
FROM payments
WHERE payment_type NOT IN ('not_defined')
GROUP BY payment_type
ORDER BY total_revenue DESC;
