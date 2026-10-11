from kafka import KafkaConsumer
import boto3
import json
from datetime import datetime
import time

# 1. Настройки S3
s3_client = boto3.client('s3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id='minioadmin',
    aws_secret_access_key='miniopassword',
    region_name='us-east-1'
)
bucket_name = 'raw-events'

try:
    s3_client.create_bucket(Bucket=bucket_name)
except Exception:
    pass

# 2. Подписка на все 5 топиков новой архитектуры
TARGET_TOPICS = [
    'hr_app_events',
    'client_app_events', 
    'mechanic_app_events',
    'shop_app_events',
    'inventory_events'
]

consumer = KafkaConsumer(
    *TARGET_TOPICS,
    bootstrap_servers=['localhost:9092'],
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
    auto_offset_reset='earliest',
    enable_auto_commit=True,
    group_id='s3_data_lake_writer'
)

print(f"🎧 Консьюмер запущен. Слушаем топики: {', '.join(TARGET_TOPICS)}...")

batch = []
# Увеличиваем батч, так как событий стало больше (сохраняем каждые 50 сообщений)
BATCH_SIZE = 50 

for message in consumer:
    # Сохраняем само сообщение и имя топика, из которого оно пришло
    batch.append({
        "topic": message.topic,
        "data": message.value
    })
    
    print(f"[{message.topic}] Получено: {message.value.get('event_type')}")
    
    if len(batch) >= BATCH_SIZE:
        target_date = datetime.now().strftime('%Y-%m-%d')
        timestamp_file = int(time.time() * 1000) # Миллисекунды для защиты от коллизий имен файлов
        
        # Группируем накопившийся батч по топикам
        events_by_topic = {}
        for item in batch:
            t = item['topic']
            if t not in events_by_topic:
                events_by_topic[t] = []
            events_by_topic[t].append(item['data'])
            
        # Отправляем в S3, раскладывая по папкам топиков
        for t_name, t_events in events_by_topic.items():
            file_key = f"events/{t_name}/date={target_date}/batch_{timestamp_file}.json"
            ndjson_data = "\n".join([json.dumps(record) for record in t_events])
            
            s3_client.put_object(Bucket=bucket_name, Key=file_key, Body=ndjson_data)
            print(f"✅ Файл {file_key} сохранен в S3 (Событий: {len(t_events)})")
            
        batch.clear()