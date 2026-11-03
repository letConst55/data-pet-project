import random
from datetime import timedelta
from faker import Faker

fake = Faker()

class GarageAPI:
    def __init__(self, sim_state, publisher, locations_list, carriers_list, bike_models_list, shop_locations_list):
        self.state_mgr = sim_state
        self.publisher = publisher
        self.LOCATIONS = locations_list           # Гаражи (для ремонта и выездов)
        self.SHOP_LOCATIONS = shop_locations_list # Магазины (для приемки)
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

        weights_srv = []
        for r in active_rentals:
            exp = self.state_mgr.state["clients"].get(r["client_id"], {}).get("driving_experience_years", 1)
            weights_srv.append(4.0 if exp == 0 else (2.0 if exp <= 3 else 0.6))
        rental_ctx = random.choices(active_rentals, weights=weights_srv, k=1)[0]
        rental_ctx["field_service_flag"] = True

        event_dt = self.state_mgr.state["current_sim_time"]
        ctx = self.state_mgr.get_world_context()
        event = ctx["event_code"]
        
        location_id = random.choice(self.LOCATIONS)
        
        issues = ["dead_battery", "flat_tire", "engine_check", "lost_key"]
        resolutions = ["fixed_on_site", "bike_replaced", "towed_to_shop"]

        # Специфика поломок и стоимости выезда в зависимости от погодных аномалий
        if event == "monsoon_flood":
            issue_cat = random.choices(issues, weights=[35, 10, 50, 5], k=1)[0]
            res_action = random.choices(resolutions, weights=[15, 35, 50], k=1)[0]
            cost = round(random.uniform(45.0, 140.0), 2)
            client_fault = random.choices([True, False], weights=[30, 70], k=1)[0]
        elif event == "extreme_heatwave":
            issue_cat = random.choices(issues, weights=[30, 15, 50, 5], k=1)[0]
            res_action = random.choices(resolutions, weights=[40, 30, 30], k=1)[0]
            cost = round(random.uniform(30.0, 110.0), 2)
            client_fault = False
        elif event == "songkran_festival":
            issue_cat = random.choices(issues, weights=[20, 30, 15, 35], k=1)[0]
            res_action = random.choices(resolutions, weights=[60, 25, 15], k=1)[0]
            cost = round(random.uniform(25.0, 95.0), 2)
            client_fault = random.choices([True, False], weights=[75, 25], k=1)[0]
        else:
            issue_cat = random.choice(issues)
            res_action = random.choice(resolutions)
            cost = round(random.uniform(20.0, 100.0), 2)
            client_fault = random.choice([True, False])

        payload = {
            "service_event_id": f"se_{self.state_mgr.get_counter('repair')}",
            "rental_id": rental_ctx["rental_id"],
            "client_id": rental_ctx["client_id"],
            "bike_id": rental_ctx["bike_id"],
            "event_date": event_dt.date().isoformat(),
            "event_datetime": event_dt.isoformat(),
            "location_id": location_id, 
            "employee_id": self.state_mgr.get_employee("can_field_service_flg", location_id),
            "issue_category": issue_cat,
            "resolution_action": res_action,
            "service_cost_usd": cost,
            "client_fault_flag": client_fault
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
        ctx = self.state_mgr.get_world_context()
        event = ctx["event_code"]
        
        # В кризис поставок и наводнение сроки транспортировки и ремонта растягиваются
        if event in ("supply_chain_crisis", "monsoon_flood"):
            transport_start = event_dt + timedelta(hours=random.randint(12, 48))
            repair_start = transport_start + timedelta(hours=random.randint(6, 24))
            repair_end = repair_start + timedelta(days=random.randint(5, 14))
            transport_end = repair_end + timedelta(hours=random.randint(12, 48))
        else:
            transport_start = event_dt + timedelta(hours=random.randint(2, 24))
            repair_start = transport_start + timedelta(hours=random.randint(1, 12))
            repair_end = repair_start + timedelta(days=random.randint(1, 7))
            transport_end = repair_end + timedelta(hours=random.randint(2, 24))

        location_shop_id = random.choice(self.SHOP_LOCATIONS)

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

        ctx = self.state_mgr.get_world_context()
        event = ctx["event_code"]

        # При сложных ремонтах после шторма или дефицита запчастей средний чек выше
        if event in ("monsoon_flood", "supply_chain_crisis"):
            invoice_total = round(random.uniform(140.0, 650.0), 2)
            invoice_discount = random.choice([0.0, 0.0, 10.0])
        elif event == "grand_promo":
            invoice_total = round(random.uniform(80.0, 500.0), 2)
            invoice_discount = random.choice([15.0, 25.0, 40.0])
        else:
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