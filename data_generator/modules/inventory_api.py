import random
from datetime import timedelta
from faker import Faker

fake = Faker()

class InventoryAPI:
    def __init__(self, sim_state, publisher, locations_list, products_list, vendors_list, carriers_list):
        self.state_mgr = sim_state
        self.publisher = publisher
        self.LOCATIONS = locations_list
        self.VENDORS = vendors_list
        self.CARRIERS = carriers_list
        
        # Оставляем только физические товары (исключаем услуги тюнинга)
        self.PHYSICAL_PRODUCTS = []
        self.PRODUCT_META = {}
        
        for p in products_list:
            is_tuning = str(p.get("is_tuning_flag", False)).lower() in ("true", "1")
            if not is_tuning:
                prod_id = p["product_id"]
                self.PHYSICAL_PRODUCTS.append(p)
                
                # Привязываем товар к его реальному вендору из dim_product.csv
                raw_vendor = p.get("vendor")
                valid_vendor = raw_vendor if raw_vendor in self.VENDORS else random.choice(self.VENDORS)
                
                self.PRODUCT_META[prod_id] = {
                    "vendor_id": valid_vendor,
                    "unit_cost": round(random.uniform(8.0, 120.0), 2)
                }
        
        if "inventory" not in self.state_mgr.state:
            self.state_mgr.state["inventory"] = {}
            
        # Завозим стартовые остатки на локации
        if not self.state_mgr.state["inventory"]:
            self._init_starting_inventory()

    def _send(self, topic, event_type, payload):
        event_dt = self.state_mgr.state["current_sim_time"]
        event_id = f"evt_{fake.uuid4()}"
        self.publisher.publish(topic, event_type, payload, event_dt, event_id)
        
        entity_key = payload.get('shipment_id') or payload.get('product_id')
        mode_tag = "LIVE" if self.state_mgr.state["is_realtime"] else "HIST"
        print(f"[{mode_tag} | {event_dt.isoformat()[:16]}] [{topic}] {event_type} -> {entity_key}", flush=True)

    def _init_starting_inventory(self):
        """Заполняем склад начальными запасами"""
        for prod in self.PHYSICAL_PRODUCTS:
            prod_id = prod["product_id"]
            self.state_mgr.state["inventory"][prod_id] = {}
            for loc in self.LOCATIONS:
                self.state_mgr.state["inventory"][prod_id][loc] = random.randint(10, 50)

    def perform_procurement(self):
        """Закупка товаров (fct_procurement) - восполняем запасы с учетом логистической обстановки"""
        event_dt = self.state_mgr.state["current_sim_time"]
        ctx = self.state_mgr.get_world_context()
        season = ctx["season_code"]
        event = ctx["event_code"]
        inv = self.state_mgr.state["inventory"]
        
        # В высокий сезон и промо закупаем проактивно при остатке < 15
        restock_threshold = 15 if (season == "high_season" or event == "grand_promo") else 10

        needs_restock = []
        for prod_id, loc_data in inv.items():
            for loc_id, qty in loc_data.items():
                if qty < restock_threshold:
                    needs_restock.append((prod_id, loc_id, qty))
                    
        if not needs_restock:
            return

        shipment_id = f"shp_{self.state_mgr.get_counter('procurement')}"
        carrier_id = random.choice(self.CARRIERS)
        
        # В период логистического кризиса увеличиваются сроки доставки и стоимость фрахта (+25%)
        if event == "supply_chain_crisis":
            departure_dt = event_dt + timedelta(days=random.randint(3, 7))
            arrival_dt = departure_dt + timedelta(days=random.randint(10, 21))
            max_lines = 3
            cost_multiplier = 1.25
        elif event == "monsoon_flood":
            departure_dt = event_dt + timedelta(days=random.randint(2, 5))
            arrival_dt = departure_dt + timedelta(days=random.randint(5, 12))
            max_lines = 4
            cost_multiplier = 1.15
        else:
            departure_dt = event_dt + timedelta(days=random.randint(1, 3))
            arrival_dt = departure_dt + timedelta(days=random.randint(2, 7))
            max_lines = 6
            cost_multiplier = 1.0

        for prod_id, loc_id, current_qty in needs_restock[:max_lines]:
            if season == "high_season" or event == "grand_promo":
                target_stock = random.randint(45, 75)
            else:
                target_stock = random.randint(30, 60)

            order_qty = target_stock + abs(current_qty) if current_qty < 0 else random.randint(25, 55)
            inv[prod_id][loc_id] = current_qty + order_qty
            
            meta = self.PRODUCT_META.get(prod_id, {})
            vendor_id = meta.get("vendor_id") or random.choice(self.VENDORS)
            unit_cost = meta.get("unit_cost", 25.0)
            payment_amount = round(order_qty * unit_cost * cost_multiplier, 2)
            
            payload = {
                "shipment_id": shipment_id,
                "product_id": prod_id,
                "vendor_id": vendor_id,
                "carrier_id": carrier_id,
                "order_date": event_dt.date().isoformat(),
                "shipment_departure_date": departure_dt.date().isoformat(),
                "shipment_arrival_date": arrival_dt.date().isoformat(),
                "arrival_location_id": loc_id,
                "vendor_invoice_number": f"INV-{random.randint(1000, 9999)}",
                "payment_check_number": f"CHK-{random.randint(1000, 9999)}",
                "payment_amount": payment_amount,
                "product_quantity": order_qty
            }
            self._send('inventory_events', 'procurement_created', payload)

    def take_weekly_snapshot(self):
        """Еженедельный срез складских остатков (fct_inventory_snapshot)"""
        event_dt = self.state_mgr.state["current_sim_time"]
        
        # Снапшот делаем только раз в неделю по воскресеньям (isoweekday == 7)
        if event_dt.isoweekday() != 7:
            return
            
        week_year = f"{event_dt.isocalendar()[1]}-{event_dt.year}"
        
        # Защита от дублей: если уже делали снапшот на этой неделе, выходим
        last_snapshot = self.state_mgr.state.get("last_snapshot_week")
        if last_snapshot == week_year:
            return
            
        self.state_mgr.state["last_snapshot_week"] = week_year
        ctx = self.state_mgr.get_world_context()
        lead_days = 14 if ctx["event_code"] == "supply_chain_crisis" else 5
        inv = self.state_mgr.state["inventory"]

        for prod_id, loc_data in inv.items():
            for loc_id, qty in loc_data.items():
                payload = {
                    "week_year": week_year,
                    "product_id": prod_id,
                    "location_id": loc_id,
                    "product_quantity": qty,
                    "available_flag": qty > 0,
                    "isin_shipment_flag": qty < 10,
                    "planned_delivery_date": (event_dt + timedelta(days=lead_days)).date().isoformat() if qty < 10 else None
                }
                self._send('inventory_events', 'inventory_snapshot_taken', payload)