#!/usr/bin/env python3
"""
CSV to Kafka loader script.
Loads CSV file data into Kafka transactions topic.
"""

import argparse
import json
import logging
import os
import sys
from pathlib import Path

import pandas as pd
from confluent_kafka import Producer

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9095")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "transactions")


def load_csv(file_path: str) -> pd.DataFrame:
    """
    Load CSV file into pandas DataFrame.
    
    Args:
        file_path: Path to CSV file
        
    Returns:
        DataFrame with CSV data
        
    Raises:
        FileNotFoundError: If file doesn't exist
        ValueError: If file cannot be parsed
    """
    file_path_obj = Path(file_path)
    
    if not file_path_obj.exists():
        raise FileNotFoundError(f"CSV file not found: {file_path}")
    
    logger.info(f"Loading CSV file: {file_path}")
    
    try:
        df = pd.read_csv(file_path)
        logger.info(f"Loaded {len(df)} rows from CSV file")
        logger.info(f"Columns: {list(df.columns)}")
        return df
    except Exception as e:
        raise ValueError(f"Error reading CSV file: {e}")


def send_to_kafka(df: pd.DataFrame, topic: str, bootstrap_servers: str) -> bool:
    """
    send dataframe rows to kafka topic as json messages.
    handles large datasets by periodically polling and flushing.
    """
    logger.info(f"Connecting to Kafka: {bootstrap_servers}")
    logger.info(f"Topic: {topic}")
    
    producer_config = {
        'bootstrap.servers': bootstrap_servers,
        'queue.buffering.max.messages': 500000,
        'queue.buffering.max.kbytes': 1048576,
        'batch.num.messages': 10000,
        'linger.ms': 50
    }
    
    try:
        producer = Producer(producer_config)
    except Exception as e:
        logger.error(f"Failed to create Kafka producer: {e}")
        return False
    
    total_rows = len(df)
    successful = 0
    failed = 0
    
    logger.info(f"Starting to send {total_rows} rows to Kafka...")
    
    for idx, row in df.iterrows():
        try:
            row_dict = row.to_dict()
            message_value = json.dumps(row_dict, default=str)
            
            producer.produce(
                topic,
                value=message_value.encode('utf-8'),
                callback=lambda err, msg: None
            )
            
            successful += 1
            
            # poll every 100 messages to free up buffer
            if (idx + 1) % 100 == 0:
                producer.poll(0)
            
            # flush every 10000 messages for reliability
            if (idx + 1) % 10000 == 0:
                producer.flush()
                logger.info(f"Sent {idx + 1}/{total_rows} rows...")
                
        except Exception as e:
            logger.error(f"Error sending row {idx}: {e}")
            failed += 1
            producer.poll(0)
            continue
    
    logger.info("Flushing producer...")
    producer.flush()
    
    logger.info(f"Completed. Successful: {successful}, Failed: {failed}")
    
    if failed > 0:
        logger.warning(f"{failed} rows failed to send")
        return False
    
    return True


def main():
    parser = argparse.ArgumentParser(
        description='Load CSV file data into Kafka transactions topic'
    )
    parser.add_argument(
        'csv_file',
        type=str,
        help='Path to CSV file to load'
    )
    parser.add_argument(
        '--bootstrap-servers',
        type=str,
        default=KAFKA_BOOTSTRAP_SERVERS,
        help=f'Kafka bootstrap servers (default: {KAFKA_BOOTSTRAP_SERVERS})'
    )
    parser.add_argument(
        '--topic',
        type=str,
        default=KAFKA_TOPIC,
        help=f'Kafka topic name (default: {KAFKA_TOPIC})'
    )
    
    args = parser.parse_args()
    
    try:
        df = load_csv(args.csv_file)
        
        success = send_to_kafka(df, args.topic, args.bootstrap_servers)
        
        if success:
            logger.info("CSV data successfully loaded to Kafka")
            sys.exit(0)
        else:
            logger.error("Failed to load all data to Kafka")
            sys.exit(1)
            
    except FileNotFoundError as e:
        logger.error(str(e))
        sys.exit(1)
    except ValueError as e:
        logger.error(str(e))
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

