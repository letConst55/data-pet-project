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

def get_dynamic_weights(ctx):
    """
    Возвращает динамические веса для 10 действий оркестратора в зависимости от сезона и катаклизмов.
    Порядок действий:
    [hr, gen_client, book, dispense, return, field_srv, accept_rep, finish_rep, shop_buy, procurement]
    """
    season = ctx["season_code"]
    event = ctx["event_code"]

    # 1. Базовый профиль по климатическому сезону
    if season == "high_season":
        # Высокий туристический сезон (Ноябрь - Февраль): бум аренд и покупок
        weights = [3, 18, 24, 22, 22, 5, 4, 4, 16, 4]
    elif season == "low_season":
        # Сезон дождей (Июнь - Октябрь): спад аренд, рост поломок и ремонтов
        weights = [3, 12, 14, 15, 16, 10, 6, 6, 11, 3]
    else:
        # Жаркий сезон (Март - Май): эталонный баланс
        weights = [3, 15, 20, 18, 18, 6, 4, 4, 13, 3]

    # 2. Переопределение весов во время катаклизмов и специальных событий
    if event == "monsoon_flood":
        # Наводнение: новые брони падают, массовые выезды механиков и возвраты
        weights = [2, 5, 5, 8, 18, 24, 10, 10, 6, 3]
    elif event == "songkran_festival":
        # Сонгкран: максимальный спрос на прокат и экипировку
        weights = [2, 22, 28, 25, 24, 8, 4, 4, 18, 4]
    elif event == "grand_promo":
        # Промо-кампания: всплеск новых регистраций и продаж в магазине
        weights = [3, 25, 22, 20, 20, 5, 4, 4, 28, 6]
    elif event == "supply_chain_crisis":
        # Кризис поставок: закупки блокируются (вес = 1), склад пустеет
        weights = [3, 15, 20, 18, 18, 6, 5, 5, 16, 1]
    elif event == "extreme_heatwave":
        # Аномальная жара: меньше поездок днем, чаще перегрев двигателей
        weights = [3, 10, 12, 14, 16, 14, 7, 7, 11, 3]

    return weights

def main(mode="pandas", duration_seconds=60):
    print(f"Запуск оркестратора симуляции (Режим: {mode.upper()})")
    
    # 1. Загрузка справочников
    try:
        df_bikes = load_csv_safe('data/df_bikes.csv')
        BIKES = df_bikes['bike_id'].tolist()
        BIKE_MODELS = df_bikes['title'].unique().tolist()

        df_locations = load_csv_safe('data/df_locations.csv')
        LOCATIONS = df_locations['location_id'].tolist()
        
        RENT_LOCATIONS = df_locations[df_locations['is_warehouse_flag'].astype(str).str.lower().isin(['true', '1'])]['location_id'].tolist()
        GARAGE_LOCATIONS = df_locations[df_locations['is_garage_flag'].astype(str).str.lower().isin(['true', '1'])]['location_id'].tolist()
        SHOP_LOCATIONS = df_locations[df_locations['is_shop_flag'].astype(str).str.lower().isin(['true', '1'])]['location_id'].tolist()

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
    
    # 3. Инициализация модулей 
    hr_api = HrAPI(sim_state, publisher, LOCATIONS) 
    rent_api = RentAPI(sim_state, publisher, BIKES, RENT_LOCATIONS) 
    garage_api = GarageAPI(sim_state, publisher, GARAGE_LOCATIONS, CARRIERS, BIKE_MODELS, SHOP_LOCATIONS) 
    shop_api = ShopAPI(sim_state, publisher, SHOP_LOCATIONS, PRODUCTS) 
    inventory_api = InventoryAPI(sim_state, publisher, SHOP_LOCATIONS, PRODUCTS, VENDORS, CARRIERS)
    
    actions = [
        hr_api.manage_hr_events,
        rent_api.generate_client, 
        rent_api.book_bike, 
        rent_api.dispense_bike, 
        rent_api.return_bike,
        garage_api.perform_field_service,
        garage_api.accept_external_repair,
        garage_api.finish_external_repair,
        shop_api.make_purchase,
        inventory_api.perform_procurement
    ]

    start_time = time.time()
    events_counter = 0

    while not stop_requested:
        if mode == "pandas" and (time.time() - start_time) > duration_seconds:
            break

        sim_state.advance_time(is_pandas_mode=(mode=="pandas"))
        
        # Детерминированная проверка еженедельного снапшота (срабатывает 1 раз каждое воскресенье)
        inventory_api.take_weekly_snapshot()
        
        # Получаем динамические веса для текущего сезона и активного катаклизма/промо
        world_ctx = sim_state.get_world_context()
        current_weights = get_dynamic_weights(world_ctx)
        
        action = random.choices(actions, weights=current_weights, k=1)[0]
        action()

        events_counter += 1
        if events_counter % 50 == 0 or sim_state.state["is_realtime"]:
            publisher.flush()
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