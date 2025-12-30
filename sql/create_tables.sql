-- initial ddl for clickhouse tables
-- kafka engine table, mergetree table, and materialized view

-- drop existing tables if they exist (for clean setup)
DROP TABLE IF EXISTS transactions_mv;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS transactions_kafka;

-- kafka engine table: reads from kafka topic
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
    kafka_group_name = 'clickhouse_consumer_group',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1048576;

-- mergetree table: target storage table
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
    target Nullable(UInt8)
) ENGINE = MergeTree()
ORDER BY (us_state, cat_id);

-- materialized view: transfers data from kafka table to mergetree table
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

