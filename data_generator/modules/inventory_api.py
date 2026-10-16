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
        self.PHYSICAL_PRODUCTS = [p for p in products_list if not p.get("is_tuning_flag", False)]
        
        if "inventory" not in self.state_mgr.state:
            self.state_mgr.state["inventory"] = {}
            
        # Завозим стартовые остатки на локации
        if not self.state_mgr.state["inventory"]:
            self._init_starting_inventory()

    def _send(self, topic, event_type, payload):
        event_dt = self.state_mgr.state["current_sim_time"]
        event_id = f"evt_{fake.uuid4()}"
        self.publisher.publish(topic, event_type, payload, event_dt, event_id)
        
        # Для снапшота ключа может не быть, печатаем только лог
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
        """Закупка товаров (fct_procurement) - восполняем запасы, которые упали"""
        event_dt = self.state_mgr.state["current_sim_time"]
        inv = self.state_mgr.state["inventory"]
        
        needs_restock = []
        for prod_id, loc_data in inv.items():
            for loc_id, qty in loc_data.items():
                if qty < 10:
                    needs_restock.append((prod_id, loc_id, qty))
                    
        if not needs_restock:
            return

        shipment_id = f"shp_{self.state_mgr.get_counter('procurement')}"
        vendor_id = random.choice(self.VENDORS)
        carrier_id = random.choice(self.CARRIERS)
        
        departure_dt = event_dt + timedelta(days=random.randint(1, 3))
        arrival_dt = departure_dt + timedelta(days=random.randint(2, 7))
        
        for prod_id, loc_id, current_qty in needs_restock[:5]:
            # ИСПРАВЛЕНИЕ: Динамический расчет закупки. 
            # Компенсируем минус (если он есть) и добавляем резерв.
            target_stock = random.randint(30, 60)
            order_qty = target_stock + abs(current_qty) if current_qty < 0 else random.randint(20, 50)
            
            inv[prod_id][loc_id] = current_qty + order_qty
            
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
                "payment_amount": round(random.uniform(500.0, 3000.0), 2),
                "product_quantity": order_qty
            }
            self._send('inventory_events', 'procurement_created', payload)

    def take_weekly_snapshot(self):
        """Еженедельный срез складских остатков (fct_inventory_snapshot)"""
        event_dt = self.state_mgr.state["current_sim_time"]
        
        # Снапшот делаем только раз в неделю (например, по воскресеньям)
        # Если сегодня не воскресенье (isoweekday == 7) - пропускаем
        if event_dt.isoweekday() != 7:
            return
            
        week_year = f"{event_dt.isocalendar()[1]}-{event_dt.year}"
        
        # Защита от дублей: если мы уже делали снапшот на этой неделе, выходим
        last_snapshot = self.state_mgr.state.get("last_snapshot_week")
        if last_snapshot == week_year:
            return
            
        self.state_mgr.state["last_snapshot_week"] = week_year
        inv = self.state_mgr.state["inventory"]

        for prod_id, loc_data in inv.items():
            for loc_id, qty in loc_data.items():
                payload = {
                    "week_year": week_year,
                    "product_id": prod_id,
                    "location_id": loc_id,
                    "product_quantity": qty,
                    "available_flag": qty > 0,
                    "isin_shipment_flag": qty < 10, # Если мало, значит скорее всего заказан
                    "planned_delivery_date": (event_dt + timedelta(days=5)).date().isoformat() if qty < 10 else None
                }
                self._send('inventory_events', 'inventory_snapshot_taken', payload)