-- optimized ddl for clickhouse tables
-- includes partitioning, enhanced ordering, and skip indexes for better query performance

-- drop existing tables if they exist
DROP TABLE IF EXISTS transactions_mv;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS transactions_kafka;

-- kafka engine table: reads from kafka topic (same as initial version)
CREATE TABLE transactions_kafka (
    transaction_time String,
    merch String,
    cat_id String,
    amount Float64,
    name_1 String,
    name_2 String,
    gender String,
    street String,
    one_city String,
    us_state String,
    jobs String,
    lat Float64,
    lon Float64,
    merchant_lat Float64,
    merchant_lon Float64,
    population_city Float64,
    target Nullable(UInt8)
) ENGINE = Kafka()
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'transactions',
    kafka_group_name = 'clickhouse_consumer_group_optimized',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1048576;

-- optimized mergetree table with partitioning and enhanced ordering
CREATE TABLE transactions (
    transaction_time String,
    merch String,
    cat_id String,
    amount Float64,
    name_1 String,
    name_2 String,
    gender String,
    street String,
    one_city String,
    us_state String,
    jobs String,
    lat Float64,
    lon Float64,
    merchant_lat Float64,
    merchant_lon Float64,
    population_city Float64,
    target Nullable(UInt8),
    -- materialized columns for date partitioning and faster queries
    transaction_date Date MATERIALIZED toDate(parseDateTimeBestEffort(transaction_time)),
    transaction_year_month UInt32 MATERIALIZED toYYYYMM(toDate(parseDateTimeBestEffort(transaction_time))),
    -- skip indexes for faster filtering on commonly queried columns
    INDEX idx_us_state us_state TYPE bloom_filter GRANULARITY 1,
    INDEX idx_cat_id cat_id TYPE bloom_filter GRANULARITY 1
) ENGINE = MergeTree()
PARTITION BY transaction_year_month
ORDER BY (us_state, cat_id, amount DESC)
SETTINGS index_granularity = 8192;

-- materialized view: transfers data from kafka table to optimized mergetree table
CREATE MATERIALIZED VIEW transactions_mv TO transactions AS
SELECT
    transaction_time,
    merch,
    cat_id,
    amount,
    name_1,
    name_2,
    gender,
    street,
    one_city,
    us_state,
    jobs,
    lat,
    lon,
    merchant_lat,
    merchant_lon,
    population_city,
    target
FROM transactions_kafka;

