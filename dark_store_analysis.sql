-- =====================================================================
-- Dark Store Sales, Stock-out & Demand Analysis  (MySQL 8+)
-- Data: dark_store_simple.csv  (SIMULATED: 3 stores, 12 products, 90 days)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. SETUP: create the table and load the CSV
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS dark_store_db;
USE dark_store_db;

DROP TABLE IF EXISTS dark_store;
CREATE TABLE dark_store (
    sale_date       DATE,
    store           VARCHAR(30),
    product         VARCHAR(30),
    category        VARCHAR(30),
    units_sold      INT,
    price           INT,
    lead_time_days  INT,
    stockout        TINYINT      -- 1 = product ran out that day, 0 = in stock
);

-- Option A: LOAD DATA (change the path; needs local_infile enabled)
-- LOAD DATA LOCAL INFILE 'C:/path/to/dark_store_simple.csv'
-- INTO TABLE dark_store
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

-- Option B (easier): MySQL Workbench -> right-click the table -> Table Data Import Wizard -> choose the CSV.

-- Quick check after loading: should return 3240 rows
SELECT COUNT(*) AS total_rows FROM dark_store;


-- ---------------------------------------------------------------------
-- 1. Which categories earn the most?
-- ---------------------------------------------------------------------
SELECT category,
       SUM(units_sold * price) AS revenue
FROM dark_store
GROUP BY category
ORDER BY revenue DESC;
-- Expected: Staples 1,504,050 | Dairy 1,444,325 | Fruits & Veg 1,131,105 | Beverages 608,600 | Snacks 345,340


-- ---------------------------------------------------------------------
-- 2. Which products matter most? (share and cumulative share)
-- ---------------------------------------------------------------------
WITH p AS (
    SELECT product, SUM(units_sold * price) AS revenue
    FROM dark_store
    GROUP BY product
)
SELECT product,
       revenue,
       ROUND(revenue * 100 / SUM(revenue) OVER (), 1) AS share_pct,
       ROUND(SUM(revenue) OVER (ORDER BY revenue DESC) * 100 / SUM(revenue) OVER (), 1) AS cumulative_pct
FROM p
ORDER BY revenue DESC;
-- Expected: Atta 15.1, Rice 14.8, Milk 13.5 ... top 3 = 43.3% cumulative


-- ---------------------------------------------------------------------
-- 3. Which days sell the most?
-- ---------------------------------------------------------------------
SELECT DAYNAME(sale_date) AS day_name,
       SUM(units_sold)    AS units_sold
FROM dark_store
GROUP BY DAYNAME(sale_date)
ORDER BY MIN(WEEKDAY(sale_date));       -- Monday first
-- Expected: Saturday 13,877 and Sunday 13,750 are the highest


-- ---------------------------------------------------------------------
-- 4. Where do stock-outs happen?
-- ---------------------------------------------------------------------
-- 4a. By store
SELECT store,
       ROUND(AVG(stockout) * 100, 1) AS stockout_pct
FROM dark_store
GROUP BY store
ORDER BY stockout_pct DESC;
-- Expected: Whitefield 13.3 | Indiranagar 8.6 | Koramangala 5.4

-- 4b. By category
SELECT category,
       ROUND(AVG(stockout) * 100, 1) AS stockout_pct
FROM dark_store
GROUP BY category
ORDER BY stockout_pct DESC;
-- Expected: Fruits & Veg 14.2 | Dairy 13.1 | Snacks 5.2 | Staples 4.4 | Beverages 4.1


-- ---------------------------------------------------------------------
-- 5. Do stock-outs happen more on weekends?
-- ---------------------------------------------------------------------
SELECT CASE WHEN DAYOFWEEK(sale_date) IN (1, 7) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       ROUND(AVG(stockout) * 100, 1) AS stockout_pct
FROM dark_store
GROUP BY day_type;
-- Expected: Weekday 8.5 | Weekend 10.6


-- ---------------------------------------------------------------------
-- 6. How much sales do stock-outs cost?
-- ASSUMPTION: a stock-out day loses 30% of that day's sales (change 0.30 to test other values)
-- ---------------------------------------------------------------------
-- 6a. Total
SELECT ROUND(SUM(units_sold * price * stockout * 0.30)) AS lost_revenue,
       ROUND(SUM(units_sold * price * stockout * 0.30) * 100 / SUM(units_sold * price), 1) AS pct_of_revenue
FROM dark_store;
-- Expected: about Rs 142,254 = 2.8% of revenue

-- 6b. By store
SELECT store,
       ROUND(SUM(units_sold * price * stockout * 0.30)) AS lost_revenue
FROM dark_store
GROUP BY store
ORDER BY lost_revenue DESC;
-- Expected: Whitefield about 71,268 (half of the total)


-- ---------------------------------------------------------------------
-- 7. Priority table: where should we fix stock first?
-- ---------------------------------------------------------------------
WITH t AS (
    SELECT store, category,
           SUM(units_sold * price)                          AS revenue,
           ROUND(AVG(stockout) * 100, 1)                    AS stockout_pct,
           ROUND(SUM(units_sold * price * stockout * 0.30)) AS lost_revenue
    FROM dark_store
    GROUP BY store, category
)
SELECT store, category, revenue, stockout_pct, lost_revenue,
       CASE WHEN ROW_NUMBER() OVER (ORDER BY lost_revenue DESC) <= 3 THEN 'Fix first'
            WHEN ROW_NUMBER() OVER (ORDER BY lost_revenue DESC) <= 6 THEN 'Next'
            ELSE 'Monitor' END AS priority
FROM t
ORDER BY lost_revenue DESC;
-- Expected top 3: Whitefield Dairy, Whitefield Fruits & Veg, Indiranagar Dairy


-- ---------------------------------------------------------------------
-- 8. Simple demand forecast: naive vs 7-day average
-- Naive   = yesterday's sales
-- 7-day   = average of the previous 7 days (the current day is not included)
-- Error % = total |actual - forecast| / total actual sales (lower is better)
-- ---------------------------------------------------------------------
WITH f AS (
    SELECT units_sold,
           AVG(units_sold)   OVER w AS ma7,
           COUNT(units_sold) OVER w AS n_days,      -- how many past days were available
           LAG(units_sold)   OVER (PARTITION BY store, product ORDER BY sale_date) AS naive
    FROM dark_store
    WINDOW w AS (PARTITION BY store, product
                 ORDER BY sale_date
                 ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING)
)
SELECT ROUND(SUM(ABS(units_sold - naive)) * 100 / SUM(units_sold), 1) AS naive_error_pct,
       ROUND(SUM(ABS(units_sold - ma7))   * 100 / SUM(units_sold), 1) AS ma7_error_pct
FROM f
WHERE n_days = 7;          -- skip the first 7 days (no full history yet)
-- Expected: naive 29.4 | 7-day average 22.7


-- ---------------------------------------------------------------------
-- 9. Safety stock and reorder point
-- Safety stock  = 1.65 x std of daily demand x sqrt(lead time)   (1.65 = about 95% service level)
-- Reorder point = average daily demand x lead time + safety stock
-- ---------------------------------------------------------------------
WITH daily AS (
    SELECT product, sale_date,
           SUM(units_sold)     AS units,           -- total demand of the product across all stores
           MAX(lead_time_days) AS lt
    FROM dark_store
    GROUP BY product, sale_date
)
SELECT product,
       ROUND(AVG(units))                                   AS avg_daily,
       ROUND(STDDEV_SAMP(units))                           AS std_daily,
       MAX(lt)                                             AS lead_time,
       ROUND(1.65 * STDDEV_SAMP(units) * SQRT(MAX(lt)))    AS safety_stock,
       ROUND(AVG(units) * MAX(lt) + 1.65 * STDDEV_SAMP(units) * SQRT(MAX(lt))) AS reorder_point
FROM daily
GROUP BY product
ORDER BY reorder_point DESC;
-- Expected: Chips about 214, Cola 207, Biscuits 164, Milk 162 ... Rice 66
