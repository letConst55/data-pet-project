from kafka import KafkaConsumer
import boto3
import json
from datetime import datetime
import time
import signal
import sys
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)

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

# 2. Подписка
TARGET_TOPICS = [
    'hr_app_events', 'client_app_events', 
    'mechanic_app_events', 'shop_app_events', 'inventory_events'
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
BATCH_SIZE = 500
batch_counter = 0

def flush_batch(batch_to_flush, is_emergency=False):
    """Отправляет батч в S3 с гарантированно уникальным именем файла."""
    global batch_counter
    if not batch_to_flush:
        return
        
    batch_counter += 1
    target_date = datetime.now().strftime('%Y-%m-%d')
    timestamp_file = int(time.time() * 1000)
    
    events_by_topic = {}
    for item in batch_to_flush:
        t = item['topic']
        if t not in events_by_topic:
            events_by_topic[t] = []
        events_by_topic[t].append(item['data'])
        
    for t_name, t_events in events_by_topic.items():
        tag = "_emergency" if is_emergency else ""
        file_key = f"events/{t_name}/date={target_date}/batch_{timestamp_file}_{batch_counter}{tag}.json"
        ndjson_data = "\n".join([json.dumps(record) for record in t_events])
        
        s3_client.put_object(Bucket=bucket_name, Key=file_key, Body=ndjson_data)
        print(f"{'🚨 Экстренно' if is_emergency else '✅'} сохранен файл {file_key} (Событий: {len(t_events)})", flush=True)

def handle_shutdown(signum, frame):
    """Перехватчик сигналов (SIGTERM/SIGINT) для безопасного завершения."""
    print(f"\n🛑 Сигнал остановки ({signum}). Сохранение последних {len(batch)} событий из буфера...", flush=True)
    flush_batch(batch, is_emergency=True)
    consumer.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

# 3. Основной цикл с автосбросом при паузах потока (> 1 сек)
while True:
    msg_pack = consumer.poll(timeout_ms=1000)
    
    if not msg_pack:
        # Если генератор перешел в LIVE режим или взял паузу, сразу сбрасываем хвост в S3
        if batch:
            flush_batch(batch)
            batch.clear()
        continue

    for tp, messages in msg_pack.items():
        for message in messages:
            batch.append({
                "topic": message.topic,
                "data": message.value
            })
            #print(f"[{message.topic}] Получено: {message.value.get('event_type')}", flush=True)
            
            if len(batch) >= BATCH_SIZE:
                flush_batch(batch)
                batch.clear()