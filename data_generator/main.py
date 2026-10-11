import os
import time
import random
import signal
import pandas as pd

from core.state import SimulationState
from core.publisher import EventPublisher
from modules.rent_api import RentAPI
from modules.garage_api import GarageAPI
from modules.shop_api import ShopAPI
from modules.hr_api import HrAPI
from modules.inventory_api import InventoryAPI

stop_requested = False

# Определяем абсолютный путь к папке data_generator
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def handle_shutdown(signum, frame):
    global stop_requested
    print(f"\n⚠️ Получен сигнал остановки ({signum}). Завершаем текущий шаг и сохраняем состояние...")
    stop_requested = True

signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

def load_csv_safe(relative_path):
    """Загружает CSV относительно папки data_generator"""
    filepath = os.path.join(BASE_DIR, relative_path)
    df = pd.read_csv(filepath)
    df.columns = df.columns.str.strip()
    return df

def main(mode="pandas", duration_seconds=60):
    print(f"Запуск оркестратора симуляции (Режим: {mode.upper()})")
    
    # 1. Загрузка справочников (Сотрудники больше не грузятся из хардкода)
    try:
        df_bikes = load_csv_safe('data/df_bikes.csv')
        BIKES = df_bikes['bike_id'].tolist()
        BIKE_MODELS = df_bikes['title'].unique().tolist()

        df_locations = load_csv_safe('data/df_locations.csv')
        LOCATIONS = df_locations['location_id'].tolist()

        df_carriers = load_csv_safe('data/dim_carrier.csv')
        CARRIERS = df_carriers['carrier_id'].tolist()

        df_products = load_csv_safe('data/dim_product.csv')
        PRODUCTS = df_products.to_dict('records')

        df_vendors = load_csv_safe('data/dim_vendor.csv')
        VENDORS = df_vendors['vendor_id'].tolist()

    except Exception as e:
        print(f"❌ Ошибка загрузки справочников из папки data/: {e}")
        return

    # 2. Инициализация ядра
    state_file_path = os.path.join(BASE_DIR, "generator_state.json")
    sim_state = SimulationState(state_file=state_file_path)
    publisher = EventPublisher(mode=mode)
    
    # 3. Инициализация модулей (Обрати внимание: EMPLOYEES больше не передаются)
    hr_api = HrAPI(sim_state, publisher, LOCATIONS)
    rent_api = RentAPI(sim_state, publisher, BIKES, LOCATIONS)
    garage_api = GarageAPI(sim_state, publisher, LOCATIONS, CARRIERS, BIKE_MODELS)
    shop_api = ShopAPI(sim_state, publisher, LOCATIONS, PRODUCTS)
    inventory_api = InventoryAPI(sim_state, publisher, LOCATIONS, PRODUCTS, VENDORS, CARRIERS)
    
    start_time = time.time()
    events_counter = 0

    while not stop_requested:
        if mode == "pandas" and (time.time() - start_time) > duration_seconds:
            break

        sim_state.advance_time(is_pandas_mode=(mode=="pandas"))
        
        # Добавляем кадровые перестановки в пул событий (вероятность 3%)
        action = random.choices(
            [
                hr_api.manage_hr_events,
                rent_api.generate_client, 
                rent_api.book_bike, 
                rent_api.dispense_bike, 
                rent_api.return_bike,
                garage_api.perform_field_service,
                garage_api.accept_external_repair,
                garage_api.finish_external_repair,
                shop_api.make_purchase,
                inventory_api.perform_procurement,   # НОВОЕ
                inventory_api.take_weekly_snapshot   # НОВОЕ
            ],
            weights=[3, 15, 20, 15, 15, 6, 4, 4, 13, 3, 2], # Сумма весов 100
            k=1
        )[0]
        action()

        if sim_state.state["is_realtime"]:
            publisher.flush()

        events_counter += 1
        if events_counter % 50 == 0:
            sim_state.save()

        # Контроль скорости
        if mode == "pandas":
            time.sleep(random.uniform(0.005, 0.02))
        elif not sim_state.state["is_realtime"]:
            time.sleep(random.uniform(0.05, 0.15))
        else:
            time.sleep(random.uniform(2.0, 5.0))

    sim_state.save()
    publisher.export_to_csv()
    publisher.close()
    print("✅ Оркестратор успешно остановлен.")

if __name__ == "__main__":
    main(mode="kafka")