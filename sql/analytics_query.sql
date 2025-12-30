-- analytics query: category with largest transaction per state
-- this query finds the category (cat_id) with the maximum transaction amount for each state

SELECT
    us_state,
    cat_id,
    max_amount
FROM (
    SELECT
        us_state,
        cat_id,
        MAX(amount) AS max_amount,
        ROW_NUMBER() OVER (PARTITION BY us_state ORDER BY MAX(amount) DESC) AS rn
    FROM transactions
    GROUP BY us_state, cat_id
) AS ranked
WHERE rn = 1
ORDER BY us_state;

-- to export results to csv, use clickhouse client:
-- clickhouse-client --query "SELECT us_state, cat_id, max_amount FROM (SELECT us_state, cat_id, MAX(amount) AS max_amount, ROW_NUMBER() OVER (PARTITION BY us_state ORDER BY MAX(amount) DESC) AS rn FROM transactions GROUP BY us_state, cat_id) AS ranked WHERE rn = 1 ORDER BY us_state" --format CSV > query_results.csv

