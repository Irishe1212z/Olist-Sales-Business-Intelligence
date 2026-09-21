# Olist Sales, Customer & Business Intelligence Platform

An end-to-end data analytics portfolio project transforming 1.5 million rows of raw Brazilian e-commerce data into actionable business intelligence using SQL, Python, Excel, and Tableau.

---

## 1. Executive Summary
This project analyzes 96,478 delivered orders generating R$16.0M in revenue between January 2017 and August 2018 for Olist. The analysis uncovered a severe customer retention challenge (78.9% one-time buyers) and identified a critical 30-day delivery threshold strongly associated with collapsing customer satisfaction. The end product is a fully reproducible analytics pipeline bridging raw relational data, statistical analysis, and interactive executive dashboards.

## 2. Business Context
Olist is a Brazilian e-commerce marketplace connecting small businesses to broader consumer markets. Stakeholders (Operations, Marketing, and Executive leadership) required visibility into revenue growth, geographic logistics bottlenecks, and customer lifetime value to guide strategic investments in marketing and freight subsidies.

## 3. Key Business Questions
1. **Revenue:** What is the true Monthly Recurring Revenue, and how do categories rank?
2. **Customers:** What proportion of customers return, and how concentrated is our revenue?
3. **Logistics:** Which geographic regions suffer from the highest delivery failure rates?
4. **Satisfaction:** How strongly are delivery times associated with customer review scores?
5. **Profitability:** Which product categories are destroying margins via high freight costs?

## 4. Key Findings
* **The Retention Crisis:** 78.9% of customers are one-time buyers. The business is heavily dependent on constant new customer acquisition.
* **Revenue Concentration:** The top 10% of customers generate 58.3% of total revenue—a steeper concentration than the standard 80/20 rule.
* **Delivery & Satisfaction:** Late deliveries were associated with a severe drop in average review scores (from 4.29 to 2.57). Specifically, deliveries taking >30 days saw average scores collapse to 2.18.
* **Category Shifts:** Health & Beauty overtook all other categories to become the #1 revenue generator in 2018 (up 59.5% YoY), while holding favorable freight margins.
* **Geographic Risk:** São Paulo (SP), Rio de Janeiro (RJ), and Minas Gerais (MG) account for 64.6% of total revenue, highlighting extreme geographic concentration.

## 5. KPI Snapshot
* **Total Delivered Revenue:** R$ 16,008,872
* **Total Delivered Orders:** 96,478
* **Median Order Value (AOV):** R$ 105.28
* **On-Time Delivery Rate:** 91.9%
* **Average Review Score:** 4.16 / 5.0
* **Repeat Buyer Rate:** 21.1%

## 6. Project Architecture
`Raw CSVs` → `Python Pandas (Cleaning & Derived Columns)` → `DuckDB (SQL Analysis)` → `Python (Statistical EDA)` → `Pre-Aggregated CSVs` → `Tableau & Excel (Visualizations)`

## 7. Data Model & "Fan-Out" Prevention
The raw data consisted of 9 tables in a Snowflake schema. 
* **Key Challenge:** `orders` have a one-to-many relationship with both `items` and `payments`. A standard `LEFT JOIN` across all three tables causes severe row multiplication, artificially inflating revenue.
* **Solution:** Payments and items were strictly pre-aggregated to the `order_id` grain *before* joining to the master orders table, ensuring accurate revenue calculations and preserving the correct analytical grain.

## 8. SQL Analysis
The SQL phase (`/sql/`) answers 20 complex business questions using **DuckDB**.
* **Techniques Used:** Common Table Expressions (CTEs), Subqueries, Conditional Aggregation (`CASE WHEN`), Window Functions (`LAG`, `ROW_NUMBER`, `DENSE_RANK`, `PARTITION BY`, `SUM OVER` for running totals), and Safe Division (`NULLIF`).

## 9. Python EDA (Exploratory Data Analysis)
The Python phase (`/notebooks/`) focused on statistical distributions and visualizations.
* **Statistical Highlight:** Identified a strong right-skew in Order Value (Skewness = 9.37). The mean AOV (R$160) was heavily distorted by outliers (max order R$13K+). Consequently, **Median AOV (R$105)** was selected as the standard metric for executive reporting to accurately represent the typical customer.

## 10. Excel Dashboard
A 5-sheet professional workbook (`/excel/`) demonstrating advanced spreadsheet reporting.
* Features KPI scorecard layouts, nested Conditional Formatting (Traffic lights, Data Bars, Color Scales), and line/bar/pie charts built dynamically from the cleaned data.

## 11. Tableau Dashboard
An interactive, executive-level dashboard.
* **Design Strategy:** To guarantee performance and data integrity, 5 pre-aggregated, grain-controlled CSVs were generated in Python specifically for Tableau. This completely eliminated the risk of join errors in the BI layer. 
* Includes dynamic map filtering, dual-axis charts, and KPI scorecards.

## 12. Business Recommendations
1. **Launch a 90-Day Re-engagement Campaign:** Because the median time to second purchase is 110 days, marketing should target one-time buyers with incentives around day 90 to protect the LTV/CAC ratio.
2. **Establish a 30-Day Delivery SLA:** Orders taking longer than 30 days are associated with unacceptable customer satisfaction levels (2.18 average score). Heavy geographic bottlenecks (e.g., Alagoas, Maranhão) require dedicated logistics interventions.
3. **Review Heavy-Item Freight Pricing:** Categories like Office Furniture cost 42.8% of product revenue in freight. Minimum order values or localized shipping restrictions should be evaluated.

## 13. Data Quality & Methodology
* **Duplicate Reviews:** Discovered a system bug where 789 identical `review_id`s mapped to different `order_id`s. Standardized to join strictly on `order_id`.
* **Boolean Handling:** Converted True/False delivery flags to 1/0/NaN numeric indicators, enabling rapid `AVG()` calculations for success rates while gracefully handling missing data.
* **Missing Dates:** Identified and filtered 8 edge-case orders marked "delivered" but missing actual delivery timestamps.

## 14. Repository Structure
```text
├── data/
│   ├── raw/               # Original Kaggle CSVs
│   ├── cleaned/           # Post-Pandas processed data
│   └── tableau/           # Pre-aggregated grain-controlled CSVs
├── notebooks/
│   ├── 01_data_cleaning.ipynb
│   └── 02_eda_and_analysis.ipynb
├── sql/
│   ├── 01_revenue_and_sales.sql
│   ├── 02_customer_analysis.sql
│   ├── 03_profitability_operations.sql
│   └── 04_advanced_window_functions.sql
├── excel/
│   └── olist_sales_analysis.xlsx
├── reports/
│   └── figures/           # Exported Matplotlib/Seaborn charts
└── README.md
```

## 15. Tech Stack
* **Database:** DuckDB, SQL
* **Data Processing & Stats:** Python (Pandas, NumPy, Matplotlib, Seaborn)
* **Visualization & BI:** Tableau, Microsoft Excel (openpyxl)
