# Dark Store Inventory & Stock-out Analytics

A SQL project that analyses sales and stock-outs across dark stores to find where stock runs out, how much sales it costs, and how much stock should be kept.
## Business Questions

1. Which categories and products earn the most?
2. Which days sell the most?
3. Where do stock-outs happen (store, category, weekday vs weekend)?
4. How much sales do stock-outs cost?
5. Which store and category should be fixed first?
6. Can demand be forecasted with a simple method?
7. How much stock should be kept (safety stock and reorder point)?

## Files

| File | What it is |
|---|---|
| `dark_store_simple.csv` | Dataset: 3 stores, 12 products, 90 days (3,240 rows) |
| `dark_store_analysis.sql` | All queries, with expected results in the comments |

## Dataset Columns

| Column | Meaning |
|---|---|
| `sale_date` | Date of sale |
| `store` | Dark store name |
| `product`, `category` | Product and its category |
| `units_sold` | Units sold that day |
| `price` | Selling price per unit (Rs) |
| `lead_time_days` | Days taken to restock the product |
| `stockout` | 1 if the product ran out that day, 0 otherwise |

## How to Run

1. Open MySQL 8 or later (MySQL Workbench works well).
2. Open `dark_store_analysis.sql` and run Section 0 to create the table.
3. Load the CSV (Workbench: right-click the table, then **Table Data Import Wizard**).
4. Run `SELECT COUNT(*) FROM dark_store;` and check that it returns 3,240.
5. Run the remaining sections one by one.

## SQL Concepts Used

- `GROUP BY` and aggregations
- CTEs (`WITH`)
- Window functions: `SUM() OVER`, `ROW_NUMBER()`, `LAG()`, moving average with a window frame
- `CASE WHEN` for labels (weekday/weekend, priority)
- `STDDEV_SAMP` and `SQRT` for safety stock

## Key Findings

- **Fresh items run out most:** Fruits & Veg (14.2%) and Dairy (13.1%) have about 3 times the stock-out rate of other categories.
- **One store stands out:** Whitefield has a 13.3% stock-out rate, against 5.4% in Koramangala.
- **Weekends are tighter:** stock-outs are 10.6% on weekends vs 8.5% on weekdays.
- **Stock-outs cost sales:** an estimated Rs 1.42 lakh (about 2.8% of revenue) was lost.
- **Fix first:** Whitefield Dairy, Whitefield Fruits & Veg and Indiranagar Dairy hold about half of the lost sales.
- **Forecast:** a 7-day moving average reduced forecast error from 29.4% to 22.7% compared with "tomorrow = today".
- **Reorder points depend on lead time:** fast sellers with a 2-day lead time (Chips, Cola) need the highest reorder points.

## Method Notes

- **Lost sales** assume that a stock-out day loses **30%** of that day's sales. The data does not record lost sales, so this is an assumption. Change `0.30` in the SQL to test other values.
- **Forecast error** = total absolute gap between forecast and actual, divided by total actual sales.
- **Safety stock** = 1.65 x standard deviation of daily demand x square root of lead time (about 95% service level).
- **Reorder point** = average daily demand x lead time + safety stock.

## Limitations

- The data is simulated, so the findings are illustrative.
- The lost-sales figure depends on the 30% assumption.
- The forecast is a simple moving average and ignores promotions and trends.
- Lead time is treated as fixed, but real suppliers can be late.
