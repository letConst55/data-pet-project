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

# Define the absolute path to the data_generator folder
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def handle_shutdown(signum, frame):
    global stop_requested
    print(f"\n⚠️ Shutdown signal received ({signum}). Finishing the current step and saving state...")
    stop_requested = True

signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

def load_csv_safe(relative_path):
    """Loads a CSV file relative to the data_generator folder"""
    filepath = os.path.join(BASE_DIR, relative_path)
    df = pd.read_csv(filepath)
    df.columns = df.columns.str.strip()
    return df

def get_dynamic_weights(ctx):
    """
    Returns dynamic weights for the 10 orchestrator actions depending on the season and cataclysms.
    Action order:
    [hr, gen_client, book, dispense, return, field_srv, accept_rep, finish_rep, shop_buy, procurement]
    """
    season = ctx["season_code"]
    event = ctx["event_code"]

    # 1. Base profile based on climatic season
    if season == "high_season":
        # High tourist season (November - February): boom in rentals and purchases
        weights = [3, 18, 24, 22, 22, 5, 4, 4, 16, 4]
    elif season == "low_season":
        # Monsoon season (June - October): drop in rentals, rise in breakdowns and repairs
        weights = [3, 12, 14, 15, 16, 10, 6, 6, 11, 3]
    else:
        # Hot season (March - May): baseline balance
        weights = [3, 15, 20, 18, 18, 6, 4, 4, 13, 3]

    # 2. Weight overrides during cataclysms and special events
    if event == "monsoon_flood":
        # Flood: new bookings drop, massive mechanic dispatches and returns
        weights = [2, 5, 5, 8, 18, 24, 10, 10, 6, 3]
    elif event == "songkran_festival":
        # Songkran: peak demand for rentals and riding gear
        weights = [2, 22, 28, 25, 24, 8, 4, 4, 18, 4]
    elif event == "grand_promo":
        # Promo campaign: surge in new registrations and retail store sales
        weights = [3, 25, 22, 20, 20, 5, 4, 4, 28, 6]
    elif event == "supply_chain_crisis":
        # Supply chain crisis: procurements are blocked (weight = 1), warehouse empties
        weights = [3, 15, 20, 18, 18, 6, 5, 5, 16, 1]
    elif event == "extreme_heatwave":
        # Extreme heatwave: fewer day trips, more frequent engine overheating
        weights = [3, 10, 12, 14, 16, 14, 7, 7, 11, 3]

    return weights

def main(mode="pandas", duration_seconds=60):
    print(f"Starting the simulation orchestrator (Mode: {mode.upper()})")
    
    # 1. Loading reference dictionaries
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
        print(f"❌ Error loading reference dictionaries from the data/ folder: {e}")
        return

    # 2. Core initialization
    state_file_path = os.path.join(BASE_DIR, "generator_state.json")
    sim_state = SimulationState(state_file=state_file_path)
    publisher = EventPublisher(mode=mode)
    
    # 3. Module initialization 
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
        
        # Deterministic check for the weekly snapshot (triggers once every Sunday)
        inventory_api.take_weekly_snapshot()
        
        # Get dynamic weights for the current season and active cataclysm/promo
        world_ctx = sim_state.get_world_context()
        current_weights = get_dynamic_weights(world_ctx)
        
        action = random.choices(actions, weights=current_weights, k=1)[0]
        action()

        events_counter += 1
        if events_counter % 50 == 0 or sim_state.state["is_realtime"]:
            publisher.flush()
            sim_state.save()

        # Speed control
        if mode == "pandas":
            time.sleep(random.uniform(0.005, 0.02))
        elif not sim_state.state["is_realtime"]:
            time.sleep(random.uniform(0.05, 0.15))
        else:
            time.sleep(random.uniform(2.0, 5.0))

    sim_state.save()
    publisher.export_to_csv()
    publisher.close()
    print("✅ Orchestrator stopped successfully.")

if __name__ == "__main__":
    main(mode="kafka")