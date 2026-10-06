import time
import json
import random
from datetime import datetime, timedelta, timezone
import pandas as pd
from faker import Faker

try:
    from kafka import KafkaProducer
except ImportError:
    KafkaProducer = None

fake = Faker()

def run_generator(mode="pandas", duration_seconds=60):
    print(f"Инициализация генератора (Режим: {mode.upper()})")
    
    # 1. Загрузка справочника байков из CSV
    try:
        df_bikes = pd.read_csv('df_bikes.csv')
        BIKES = df_bikes['bike_id'].tolist()
        print(f"✅ Успешно загружен справочник байков: {len(BIKES)} шт.")
    except Exception as e:
        print(f"❌ Ошибка загрузки df_bikes.csv. Убедитесь, что файл лежит в корне проекта. Ошибка: {e}")
        return

    # 2. Настройка получателя данных (Kafka или словари для Pandas)
    producer = None
    if mode == "kafka":
        if KafkaProducer is None:
            print("❌ Библиотека kafka-python не установлена.")
            return
        try:
            producer = KafkaProducer(
                bootstrap_servers=['localhost:9092'],
                value_serializer=lambda v: json.dumps(v).encode('utf-8')
            )
            print("✅ Успешно подключено к Redpanda (Kafka)")
        except Exception as e:
            print(f"❌ Ошибка подключения к Kafka: {e}")
            return
            
    # Внутреннее хранилище для Pandas
    pandas_store = {
        'client_profile_updated': [],
        'rental_booked': [],
        'bike_dispensed': [],
        'field_service_performed': [],
        'bike_returned': []
    }

    # 3. Состояние в памяти (State Machine)
    # Начинаем генерацию с 1 марта 2024 года
    sim_start_dt = datetime(2024, 3, 1, 9, 0, 0, tzinfo=timezone.utc)
    
    state = {
        "current_sim_time": sim_start_dt,
        "is_realtime": False,   # Флаг перехода из исторического режима в реалтайм
        "clients": {},          # client_id -> dict с профилем
        "pending_rentals": [],  # Ожидают выдачи
        "active_rentals": [],   # В активной аренде
        "busy_bikes": set(),    # Занятые байки
        "bike_mileage": {b: random.randint(1000, 15000) for b in BIKES}
    }

    LOCATIONS = ["loc_bkk_phra_khanong", "loc_bkk_bang_na", "loc_bkk_asoke", "loc_bkk_sathorn"]
    MECHANICS = ["mech_01", "mech_02", "mech_03", "mech_04"]

    # Сдвиг виртуальных часов: ~5.5 часов за шаг в режиме истории (~10 минут на 2.5 года)
    def advance_sim_time():
        now_utc = datetime.now(timezone.utc)
        
        if not state["is_realtime"]:
            # Средний шаг ~5.5 часов (от 1 до 10 часов) позволяет пройти ~945 дней за ~4000 событий
            step = timedelta(hours=random.randint(1, 10), minutes=random.randint(0, 59))
            if state["current_sim_time"] + step < now_utc:
                state["current_sim_time"] += step
            else:
                state["current_sim_time"] = now_utc
                state["is_realtime"] = True
                print("\n🎉 Исторические данные сгенерированы! Переход в режим реального времени (Real-time)...\n", flush=True)
        else:
            # В режиме реального времени синхронизируемся с текущими часами
            state["current_sim_time"] = datetime.now(timezone.utc)
            
        return state["current_sim_time"]

    # 4. Функция маршрутизации событий
    def send_event(topic, event_type, payload, event_dt=None):
        if event_dt is None:
            event_dt = state["current_sim_time"]
            
        timestamp_str = event_dt.isoformat()
        event_id = f"evt_{fake.uuid4()}"
        
        if mode == "kafka":
            event = {
                "event_id": event_id,
                "event_type": event_type,
                "timestamp": timestamp_str,
                "payload": payload
            }
            producer.send(topic, event)
            # В режиме реалтайма делаем flush сразу, а в режиме истории батчим для скорости
            if state["is_realtime"]:
                producer.flush()
            entity_key = payload.get('rental_id') or payload.get('client_id')
            mode_tag = "LIVE" if state["is_realtime"] else "HIST"
            print(f"[{mode_tag} | {timestamp_str[:10]}] [{topic}] {event_type} -> {entity_key}", flush=True)
        
        elif mode == "pandas":
            row = {
                "event_id": event_id,
                "event_type": event_type,
                "timestamp": timestamp_str
            }
            row.update(payload)
            pandas_store[event_type].append(row)
            print(f"[{timestamp_str[:10]}] [Pandas] Сгенерировано событие: {event_type}")

    # 5. Логика генерации бизнес-событий
    def generate_client():
        event_dt = advance_sim_time()
        
        # 30% шанс обновить существующего клиента (для SCD2 в dim_clients)
        if state["clients"] and random.random() < 0.30:
            client_id = random.choice(list(state["clients"].keys()))
            profile = state["clients"][client_id].copy()
            profile["residential_address"] = fake.address().replace('\n', ', ')
            profile["preferred_payment_method"] = random.choice(["cash", "credit_card", "promptpay", "alipay"])
            profile["drive_license_verified"] = True
            profile["rating_score"] = round(min(5.0, max(1.0, profile["rating_score"] + random.uniform(-0.3, 0.3))), 1)
            state["clients"][client_id] = profile
            payload = profile
        else:
            client_id = f"cl_{fake.unique.random_int(min=10000, max=99999)}"
            gender = random.choice(["Male", "Female"])
            payload = {
                "client_id": client_id,
                "full_name": fake.name_male() if gender == "Male" else fake.name_female(),
                "gender": gender,
                "birthday": fake.date_of_birth(minimum_age=18, maximum_age=60).isoformat(),
                "salutation": "Mr." if gender == "Male" else random.choice(["Ms.", "Mrs."]),
                "phone": fake.phone_number(),
                "email": fake.email(),
                "nationality": random.choice(["Russian", "Thai", "British", "American", "German", "French"]),
                "residential_address": fake.address().replace('\n', ', '),
                "preferred_payment_method": random.choice(["cash", "credit_card", "promptpay", "alipay"]),
                "driving_experience_years": random.randint(1, 15),
                "drive_license_category": random.choice(["local", "international"]),
                "drive_license_verified": random.choice([True, True, False]),
                "rating_score": round(random.uniform(3.8, 5.0), 1)
            }
            state["clients"][client_id] = payload

        send_event('client_app_events', 'client_profile_updated', payload, event_dt=event_dt)

    def generate_booking():
        if not state["clients"]:
            return
        
        available_bikes = [b for b in BIKES if b not in state["busy_bikes"]]
        if not available_bikes:
            return

        booking_dt = advance_sim_time()
        rental_id = f"rnt_{fake.unique.random_int(min=5000, max=99999)}"
        client_id = random.choice(list(state["clients"].keys()))
        bike_id = random.choice(available_bikes)
        state["busy_bikes"].add(bike_id)

        planned_start_date = (booking_dt + timedelta(days=random.randint(0, 5))).date()
        rental_days = random.randint(1, 14)
        planned_end_date = planned_start_date + timedelta(days=rental_days)

        rental_price_daily = random.choice([15.00, 20.00, 25.00])
        discount_amount = random.choice([0.00, 0.00, 5.00, 10.00])
        location_id = random.choice(LOCATIONS)

        rental_ctx = {
            "rental_id": rental_id,
            "client_id": client_id,
            "bike_id": bike_id,
            "booking_dt": booking_dt,
            "planned_start_date": planned_start_date,
            "planned_end_date": planned_end_date,
            "rental_price_daily": rental_price_daily,
            "deposit_amount": 200.00,
            "discount_amount": discount_amount
        }
        state["pending_rentals"].append(rental_ctx)

        payload = {
            "rental_id": rental_id,
            "client_id": client_id,
            "bike_id": bike_id,
            "location_id": location_id,
            "planned_start_date": planned_start_date.isoformat(),
            "planned_end_date": planned_end_date.isoformat(),
            "rental_price_daily": rental_price_daily,
            "deposit_amount": 200.00,
            "discount_amount": discount_amount
        }
        send_event('client_app_events', 'rental_booked', payload, event_dt=booking_dt)

    def generate_dispense():
        if not state["pending_rentals"]:
            return
            
        rental_ctx = state["pending_rentals"].pop(0)
        
        delay_days = random.choices([0, 1], weights=[85, 15], k=1)[0]
        fact_start_date = rental_ctx["planned_start_date"] + timedelta(days=delay_days)
        
        dispense_dt = datetime.combine(
            fact_start_date,
            datetime.min.time(),
            tzinfo=timezone.utc
        ) + timedelta(hours=random.randint(9, 18), minutes=random.randint(0, 59))
        
        if dispense_dt <= rental_ctx["booking_dt"]:
            dispense_dt = rental_ctx["booking_dt"] + timedelta(hours=random.randint(1, 4))
            fact_start_date = dispense_dt.date()

        bike_id = rental_ctx["bike_id"]
        start_mileage = state["bike_mileage"][bike_id]
        pre_score = random.randint(7, 10)
        fuel_start = random.choice([50, 75, 100])

        rental_ctx["fact_start_date"] = fact_start_date
        rental_ctx["dispense_dt"] = dispense_dt
        rental_ctx["actual_start_mileage"] = start_mileage
        rental_ctx["pre_rental_condition_score"] = pre_score
        rental_ctx["field_service_flag"] = False
        state["active_rentals"].append(rental_ctx)

        payload = {
            "rental_id": rental_ctx["rental_id"],
            "mechanic_id": random.choice(MECHANICS),
            "location_id": random.choice(LOCATIONS),
            "fact_start_date": fact_start_date.isoformat(),
            "actual_start_mileage": start_mileage,
            "fuel_level_percent": fuel_start,
            "pre_rental_condition_score": pre_score,
            "helmets_issued_qty": random.randint(1, 2),
            "actual_payment_method": random.choice(["cash", "credit_card", "promptpay"])
        }
        send_event('mechanic_app_events', 'bike_dispensed', payload, event_dt=dispense_dt)

    def generate_field_service():
        if not state["active_rentals"]:
            return
            
        rental_ctx = random.choice(state["active_rentals"])
        rental_ctx["field_service_flag"] = True

        days_active = max(1, (rental_ctx["planned_end_date"] - rental_ctx["fact_start_date"]).days)
        service_offset = random.randint(0, days_active)
        service_dt = rental_ctx["dispense_dt"] + timedelta(
            days=service_offset,
            hours=random.randint(1, 6)
        )

        payload = {
            "rental_id": rental_ctx["rental_id"],
            "client_id": rental_ctx["client_id"],
            "bike_id": rental_ctx["bike_id"],
            "event_date": service_dt.date().isoformat(),
            "mechanic_id": random.choice(MECHANICS),
            "issue_category": random.choice(["dead_battery", "flat_tire", "engine_check", "lost_key"]),
            "resolution_action": random.choice(["fixed_on_site", "bike_replaced", "towed_to_shop"]),
            "service_cost_usd": round(random.uniform(20.0, 100.0), 2),
            "client_fault_flag": random.choice([True, False])
        }
        send_event('mechanic_app_events', 'field_service_performed', payload, event_dt=service_dt)

    def generate_return():
        if not state["active_rentals"]:
            return
            
        rental_ctx = state["active_rentals"].pop(0)
        bike_id = rental_ctx["bike_id"]

        rent_extend_flag = random.choices([False, True], weights=[80, 20], k=1)[0]
        if rent_extend_flag:
            extra_days = random.randint(1, 5)
            fact_end_date = rental_ctx["planned_end_date"] + timedelta(days=extra_days)
        else:
            early_shift = random.choices([0, -1], weights=[90, 10], k=1)[0]
            candidate_end = rental_ctx["planned_end_date"] + timedelta(days=early_shift)
            fact_end_date = max(rental_ctx["fact_start_date"] + timedelta(days=1), candidate_end)

        return_dt = datetime.combine(
            fact_end_date,
            datetime.min.time(),
            tzinfo=timezone.utc
        ) + timedelta(hours=random.randint(10, 20), minutes=random.randint(0, 59))

        if return_dt <= rental_ctx["dispense_dt"]:
            return_dt = rental_ctx["dispense_dt"] + timedelta(hours=random.randint(6, 24))
            fact_end_date = return_dt.date()

        actual_days = max(1, (fact_end_date - rental_ctx["fact_start_date"]).days)
        distance_ridden = sum(random.randint(15, 80) for _ in range(actual_days))
        end_mileage = rental_ctx["actual_start_mileage"] + distance_ridden
        state["bike_mileage"][bike_id] = end_mileage

        # ГАРАНТИЯ: post_rental_condition_score всегда СТРОГО меньше или равен pre_rental_condition_score
        # Здесь стоит строгое снижение на 1-3 балла (post < pre), но не ниже 1:
        pre_score = rental_ctx["pre_rental_condition_score"]
        wear_drop = random.choices([1, 2, 3], weights=[70, 20, 10], k=1)[0]
        post_score = max(1, pre_score - wear_drop)

        helmet_damage_flag = random.choices([False, True], weights=[92, 8], k=1)[0]

        # Штраф начисляем при сильном износе (падение >= 2 баллов) или повреждении шлема
        if wear_drop >= 2 or helmet_damage_flag:
            deposit_deducted = random.choice([30.00, 45.00, 100.00, 150.00])
            deduction_reason = "helmet_damage" if (helmet_damage_flag and wear_drop < 2) else random.choice(["damage_scratch", "broken_mirror", "plastic_crack"])
        else:
            deposit_deducted = 0.00
            deduction_reason = "none"

        total_amount = round(
            max(0.0, (actual_days * rental_ctx["rental_price_daily"]) - rental_ctx["discount_amount"] + deposit_deducted),
            2
        )

        state["busy_bikes"].discard(bike_id)

        payload = {
            "rental_id": rental_ctx["rental_id"],
            "mechanic_id": random.choice(MECHANICS),
            "location_id": random.choice(LOCATIONS),
            "fact_end_date": fact_end_date.isoformat(),
            "actual_end_mileage": end_mileage,
            "fuel_level_percent": random.choice([10, 25, 50, 75, 100]),
            "post_rental_condition_score": post_score,
            "helmet_damage_flag": helmet_damage_flag,
            "field_service_flag": rental_ctx["field_service_flag"],
            "rent_extend_flag": rent_extend_flag,
            "deposit_deducted_amount": deposit_deducted,
            "deduction_reason_code": deduction_reason,
            "total_amount": total_amount
        }
        send_event('mechanic_app_events', 'bike_returned', payload, event_dt=return_dt)

    # 6. Главный цикл генерации
    start_time = time.time()
    
    if mode == "pandas":
        print(f"Сбор данных запущен. Скрипт автоматически остановится через {duration_seconds} секунд...")
    else:
        print("Запуск быстрой генерации истории с марта 2024 (~10 минут до текущего момента)...")
        
    try:
        while True:
            if mode == "pandas" and (time.time() - start_time) > duration_seconds:
                break
                
            action = random.choices(
                [generate_client, generate_booking, generate_dispense, generate_field_service, generate_return],
                weights=[20, 30, 22, 6, 22],
                k=1
            )[0]
            action()
            
            # Настройка паузы в зависимости от режима:
            if mode == "pandas":
                sleep_time = random.uniform(0.01, 0.05)
            elif not state["is_realtime"]:
                # Турбо-режим истории: в среднем 0.15 сек на событие (~4000 событий за 10 минут)
                sleep_time = random.uniform(0.10, 0.20)
            else:
                # Режим реального времени после того, как догнали сегодняшнюю дату:
                sleep_time = random.uniform(2.0, 5.0)
                
            time.sleep(sleep_time)
            
    except KeyboardInterrupt:
        print("\n🛑 Остановка по требованию пользователя.")
    finally:
        if producer is not None:
            producer.flush()
            producer.close()
        
    # 7. Выгрузка в CSV (только для Pandas)
    if mode == "pandas":
        print("\n💾 Формирование CSV файлов...")
        for event_type, rows in pandas_store.items():
            if rows:
                df = pd.DataFrame(rows)
                filename = f"sample_{event_type}.csv"
                df.to_csv(filename, index=False, encoding='utf-8')
                print(f"✅ Сохранен файл: {filename} (строк: {len(df)})")
        print("🎉 Готово! Можете проверять CSV файлы.")

if __name__ == "__main__":
    run_generator(mode="kafka")