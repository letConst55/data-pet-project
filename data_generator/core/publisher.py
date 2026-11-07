import json
import pandas as pd

try:
    from kafka import KafkaProducer
except ImportError:
    KafkaProducer = None

class EventPublisher:
    def __init__(self, mode="pandas", bootstrap_servers=['localhost:9092']):
        self.mode = mode
        self.producer = None
        self.pandas_store = {}
        
        if self.mode == "kafka":
            if KafkaProducer is None:
                raise ImportError("The kafka-python library is not installed.")
            self.producer = KafkaProducer(
                bootstrap_servers=bootstrap_servers,
                value_serializer=lambda v: json.dumps(v).encode('utf-8')
            )
            print("✅ Successfully connected to Redpanda (Kafka)")

    def publish(self, topic, event_type, payload, event_dt, event_id):
        timestamp_str = event_dt.isoformat()
        
        if self.mode == "kafka":
            event = {
                "event_id": event_id,
                "event_type": event_type,
                "timestamp": timestamp_str,
                "payload": payload
            }
            self.producer.send(topic, event)
        
        elif self.mode == "pandas":
            if event_type not in self.pandas_store:
                self.pandas_store[event_type] = []
            
            row = {
                "event_id": event_id,
                "event_type": event_type,
                "timestamp": timestamp_str
            }
            row.update(payload)
            self.pandas_store[event_type].append(row)

    def flush(self):
        if self.producer:
            self.producer.flush()

    def close(self):
        if self.producer:
            self.producer.flush()
            self.producer.close()
            
    def export_to_csv(self):
        if self.mode != "pandas":
            return
        for event_type, rows in self.pandas_store.items():
            if rows:
                df = pd.DataFrame(rows)
                filename = f"sample_{event_type}.csv"
                df.to_csv(filename, index=False, encoding='utf-8')
                print(f"✅ Сохранен файл: {filename} (строк: {len(df)})")