# hw3: clickhouse + kafka integration

data pipeline project that loads csv data into kafka, stores it in clickhouse, and performs analytics queries.

## overview

this project implements a complete data pipeline:

```
csv file → kafka topic → clickhouse (kafka engine) → clickhouse (mergetree) → analytics query
```

the pipeline includes:
1. csv to kafka loader script
2. clickhouse tables with kafka engine integration
3. analytics query for finding maximum transaction category per state
4. optimized table structure for improved query performance

## prerequisites

- docker
- docker compose
- python 3.8+
- train.csv from kaggle dataset

## project structure

```
hw3/
├── docker-compose.yaml          # kafka + clickhouse infrastructure
├── README.md                    # this file
├── requirements.txt             # python dependencies
├── .gitignore
├── data/                        # csv data directory (gitignored)
│   └── .gitkeep
├── scripts/
│   └── load_csv_to_kafka.py     # csv to kafka loader script
└── sql/
    ├── create_tables.sql        # initial ddl (requirement #2)
    ├── create_tables_optimized.sql  # optimized ddl (requirement #4)
    ├── analytics_query.sql      # analytics query (requirement #3)
    └── query_results.csv        # query results (requirement #3)
```

## setup instructions

### 1. download data

download the `train.csv` file from kaggle:
- url: https://www.kaggle.com/competitions/teta-ml-1-2025/data?select=train.csv
- save it to `data/train.csv`

### 2. install python dependencies

```bash
pip install -r requirements.txt
```

### 3. start infrastructure

start kafka and clickhouse services:

```bash
docker-compose up -d
```

wait for all services to be healthy (check with `docker-compose ps`).

### 4. create clickhouse tables

execute the initial ddl script to create tables:

```bash
docker-compose exec -T clickhouse clickhouse-client < sql/create_tables.sql
```

this creates:
- `transactions_kafka` table (kafka engine)
- `transactions` table (mergetree)
- `transactions_mv` materialized view

### 5. load csv data to kafka

run the csv loader script:

```bash
python scripts/load_csv_to_kafka.py data/train.csv
```

or specify kafka connection details:

```bash
python scripts/load_csv_to_kafka.py data/train.csv --bootstrap-servers localhost:9095 --topic transactions
```

the script will:
- read the csv file
- send each row as a json message to kafka
- show progress (logs every 1000 rows)

### 6. verify data in clickhouse

check that data is flowing into clickhouse:

```bash
docker-compose exec clickhouse clickhouse-client --query "SELECT count() FROM transactions"
```

you should see the row count increasing as data is consumed from kafka.

### 7. run analytics query

execute the analytics query to find the category with largest transaction per state:

```bash
docker-compose exec -T clickhouse clickhouse-client < sql/analytics_query.sql
```

to export results to csv:

```bash
docker-compose exec clickhouse clickhouse-client --query "SELECT us_state, cat_id, max_amount FROM (SELECT us_state, cat_id, MAX(amount) AS max_amount, ROW_NUMBER() OVER (PARTITION BY us_state ORDER BY MAX(amount) DESC) AS rn FROM transactions GROUP BY us_state, cat_id) AS ranked WHERE rn = 1 ORDER BY us_state FORMAT CSV" > sql/query_results.csv
```

### 8. apply optimizations (requirement #4)

apply the optimized ddl for better query performance:

```bash
docker-compose exec -T clickhouse clickhouse-client < sql/create_tables_optimized.sql
```

the optimizations include:
- partitioning by year month
- enhanced order by clause (us_state, cat_id, amount)
- skip indexes on us_state and cat_id columns
- materialized columns for date based operations

note: after applying optimizations, you need to reload data:
1. reload csv to kafka (step 5)
2. wait for data to flow into clickhouse
3. re run analytics query (step 7)

## services

| service | port | description |
|---------|------|-------------|
| kafka | 9095 | kafka broker (external port) |
| kafka ui | 8080 | web interface for kafka monitoring |
| clickhouse http | 8123 | clickhouse http interface |
| clickhouse native | 9000 | clickhouse native protocol |
| zookeeper | 2181 | zookeeper (kafka dependency) |

### access points

- kafka ui: http://localhost:8080
- clickhouse http: http://localhost:8123
- clickhouse client: `docker-compose exec clickhouse clickhouse-client`

## usage examples

### clickhouse client commands

connect to clickhouse:

```bash
docker-compose exec clickhouse clickhouse-client
```

example queries:

```sql
-- check row count
SELECT count() FROM transactions;

-- sample rows
SELECT * FROM transactions LIMIT 10;

-- check partitions (for optimized version)
SELECT partition, count() FROM transactions GROUP BY partition;

-- run analytics query
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
```

### csv loader script options

```bash
# basic usage
python scripts/load_csv_to_kafka.py data/train.csv

# custom kafka connection
python scripts/load_csv_to_kafka.py data/train.csv \
    --bootstrap-servers localhost:9095 \
    --topic transactions

# help
python scripts/load_csv_to_kafka.py --help
```

## troubleshooting

### kafka topic not created

if the kafka setup service fails, manually create the topic:

```bash
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
    --create --topic transactions --partitions 3 --replication-factor 1
```

### clickhouse not receiving data

1. check kafka ui (http://localhost:8080) to verify messages are in the topic
2. check clickhouse logs: `docker-compose logs clickhouse`
3. verify kafka engine table is connected:
   ```sql
   SELECT * FROM system.kafka_consumers;
   ```
4. check materialized view is working:
   ```sql
   SELECT count() FROM transactions_kafka;
   SELECT count() FROM transactions;
   ```

### csv loader fails

- verify kafka is running: `docker-compose ps kafka`
- check kafka connection: `docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list`
- ensure csv file exists and is readable
- check python dependencies: `pip list | grep confluent-kafka`

### clickhouse connection issues

- verify clickhouse is healthy: `docker-compose ps clickhouse`
- check clickhouse logs: `docker-compose logs clickhouse`
- test http endpoint: `curl http://localhost:8123/ping` (should return "Ok")

### data not appearing after optimization

after applying optimized ddl, tables are dropped and recreated. you must:
1. reload csv data to kafka
2. wait for materialized view to process messages
3. verify data in new optimized table

### performance issues

- ensure optimized ddl is applied (step 8)
- check partition distribution: `SELECT partition, count() FROM transactions GROUP BY partition`
- verify skip indexes are created: check table structure with `DESC transactions`

## requirements implementation

- requirement #1: csv to kafka loader script (`scripts/load_csv_to_kafka.py`)
- requirement #2: clickhouse ddl script (`sql/create_tables.sql`)
- requirement #3: analytics query + results (`sql/analytics_query.sql`, `sql/query_results.csv`)
- requirement #4: optimized ddl (`sql/create_tables_optimized.sql`)

## stopping services

stop all services:

```bash
docker-compose down
```

stop and remove volumes (removes all data):

```bash
docker-compose down -v
```

## notes

- the csv loader script sends data in batch mode without delays for better performance
- clickhouse kafka engine automatically consumes messages from kafka topic
- materialized view transfers data from kafka engine table to mergetree table
- optimized version includes partitioning and indexes for faster queries

## license

this project is for educational purposes.
