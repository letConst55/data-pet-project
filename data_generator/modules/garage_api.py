import random
from datetime import timedelta
from faker import Faker

fake = Faker()

class GarageAPI:
    def __init__(self, sim_state, publisher, locations_list, carriers_list, bike_models_list):
        self.state_mgr = sim_state
        self.publisher = publisher
        self.LOCATIONS = locations_list
        self.CARRIERS = carriers_list
        self.BIKE_MODELS = bike_models_list
        
        if "active_repairs" not in self.state_mgr.state:
            self.state_mgr.state["active_repairs"] = []

    def _send(self, topic, event_type, payload):
        event_dt = self.state_mgr.state["current_sim_time"]
        event_id = f"evt_{fake.uuid4()}"
        self.publisher.publish(topic, event_type, payload, event_dt, event_id)
        
        entity_key = payload.get('repair_id') or payload.get('service_event_id')
        mode_tag = "LIVE" if self.state_mgr.state["is_realtime"] else "HIST"
        print(f"[{mode_tag} | {event_dt.isoformat()[:16]}] [{topic}] {event_type} -> {entity_key}", flush=True)

    def perform_field_service(self):
        """Выезд механика к клиенту по аренде (fct_service_events)"""
        active_rentals = self.state_mgr.state["rentals"]["active"]
        if not active_rentals:
            return
            
        rental_ctx = random.choice(active_rentals)
        rental_ctx["field_service_flag"] = True

        event_dt = self.state_mgr.state["current_sim_time"]
        
        # ИСПРАВЛЕНИЕ: Выбираем локацию (мастерскую) выезда
        location_id = random.choice(self.LOCATIONS)
        
        payload = {
            "service_event_id": f"se_{self.state_mgr.get_counter('repair')}",
            "rental_id": rental_ctx["rental_id"],
            "client_id": rental_ctx["client_id"],
            "bike_id": rental_ctx["bike_id"],
            "event_date": event_dt.date().isoformat(),
            "event_datetime": event_dt.isoformat(),
            # ИСПРАВЛЕНИЕ: Добавили локацию и ищем механика именно на ней
            "location_id": location_id, 
            "employee_id": self.state_mgr.get_employee("can_field_service_flg", location_id),
            "issue_category": random.choice(["dead_battery", "flat_tire", "engine_check", "lost_key"]),
            "resolution_action": random.choice(["fixed_on_site", "bike_replaced", "towed_to_shop"]),
            "service_cost_usd": round(random.uniform(20.0, 100.0), 2),
            "client_fault_flag": random.choice([True, False])
        }
        self._send('mechanic_app_events', 'field_service_performed', payload)

    def accept_external_repair(self):
        """Клиент сдает свой личный байк в ремонт через магазин"""
        clients_dict = self.state_mgr.state["clients"]
        if not clients_dict or not self.CARRIERS:
            return

        client_id = random.choice(list(clients_dict.keys()))
        repair_id = f"rep_{self.state_mgr.get_counter('repair')}"
        event_dt = self.state_mgr.state["current_sim_time"]
        
        transport_start = event_dt + timedelta(hours=random.randint(2, 24))
        repair_start = transport_start + timedelta(hours=random.randint(1, 12))
        repair_end = repair_start + timedelta(days=random.randint(1, 7))
        transport_end = repair_end + timedelta(hours=random.randint(2, 24))

        # Сначала выбираем локацию магазина
        location_shop_id = random.choice(self.LOCATIONS)

        repair_ctx = {
            "repair_id": repair_id,
            "client_id": client_id,
            "bike_name": random.choice(self.BIKE_MODELS),
            "employee_id": self.state_mgr.get_employee("can_workshop_repair_flg", location_shop_id),
            "location_shop_id": location_shop_id,
            "location_garage_id": random.choice(self.LOCATIONS),
            "carrier_id": random.choice(self.CARRIERS),
            "transportation_start_date": transport_start.date(),
            "repair_start_date": repair_start.date(),
            "repair_end_date": repair_end.date(),
            "transportation_end_date": transport_end.date(),
            "planned_finish_dt": transport_end
        }
        self.state_mgr.state["active_repairs"].append(repair_ctx)

    def finish_external_repair(self):
        """Завершение ремонта личного байка клиента (fct_repair)"""
        active_repairs = self.state_mgr.state.get("active_repairs", [])
        if not active_repairs:
            return

        current_time = self.state_mgr.state["current_sim_time"]
        
        finished_repairs = [r for r in active_repairs if current_time >= r["planned_finish_dt"]]
        if not finished_repairs:
            return

        repair_ctx = finished_repairs[0]
        self.state_mgr.state["active_repairs"].remove(repair_ctx)

        invoice_total = round(random.uniform(50.0, 500.0), 2)
        invoice_discount = random.choice([0.0, 0.0, 10.0, 25.0])

        payload = {
            "repair_id": repair_ctx["repair_id"],
            "order_id": None,
            "employee_id": repair_ctx["employee_id"],
            "client_id": repair_ctx["client_id"],
            "carrier_id": repair_ctx["carrier_id"],
            "bike_name": repair_ctx["bike_name"],
            "location_shop_id": repair_ctx["location_shop_id"],
            "location_garage_id": repair_ctx["location_garage_id"],
            "transportation_start_date": repair_ctx["transportation_start_date"].isoformat(),
            "transportation_end_date": repair_ctx["transportation_end_date"].isoformat(),
            "repair_start_date": repair_ctx["repair_start_date"].isoformat(),
            "repair_end_date": repair_ctx["repair_end_date"].isoformat(),
            "invoice_total_amount": invoice_total,
            "invoice_discount_amount": invoice_discount,
            "event_datetime": current_time.isoformat()
        }
        self._send('mechanic_app_events', 'external_repair_completed', payload)