import random
from faker import Faker

fake = Faker()

class ShopAPI:
    def __init__(self, sim_state, publisher, locations_list, products_list):
        self.state_mgr = sim_state
        self.publisher = publisher
        self.LOCATIONS = locations_list
        
        self.PRODUCTS = []
        for p in products_list:
            price = round(random.uniform(20.0, 150.0), 2) if p["is_tuning_flag"] else round(random.uniform(5.0, 300.0), 2)
            self.PRODUCTS.append({
                "id": p["product_id"],
                "price": price,
                "is_tuning": p["is_tuning_flag"]
            })

    def _send(self, topic, event_type, payload):
        event_dt = self.state_mgr.state["current_sim_time"]
        event_id = f"evt_{fake.uuid4()}"
        self.publisher.publish(topic, event_type, payload, event_dt, event_id)
        
        entity_key = payload.get('order_id')
        mode_tag = "LIVE" if self.state_mgr.state["is_realtime"] else "HIST"
        print(f"[{mode_tag} | {event_dt.isoformat()[:16]}] [{topic}] {event_type} -> {entity_key}", flush=True)

    def make_purchase(self):
        clients_dict = self.state_mgr.state["clients"]
        if not clients_dict: return

        client_id = random.choice(list(clients_dict.keys()))
        order_id = f"ord_{self.state_mgr.get_counter('order')}"
        event_dt = self.state_mgr.state["current_sim_time"]
        location_id = random.choice(self.LOCATIONS)
        
        # Динамический поиск сотрудника магазина на этой локации
        employee_id = self.state_mgr.get_employee("can_sell_retail_flg", location_id)

        num_items = random.choices([1, 2, 3], weights=[60, 30, 10], k=1)[0]
        basket = random.sample(self.PRODUCTS, k=num_items)

        for item in basket:
            cnt = random.randint(1, 2) if not item["is_tuning"] else 1
            basic_amount = item["price"] * cnt
            discount = round(basic_amount * 0.1, 2) if random.random() < 0.15 else 0.0
            total_amount = round(basic_amount - discount, 2)

            if not item["is_tuning"]:
                inv = self.state_mgr.state.setdefault("inventory", {})
                prod_id = item["id"]
                loc_id = location_id
                
                if prod_id not in inv:
                    inv[prod_id] = {}
                # Если товара нет в словаре локации, допускаем уход в минус (как предзаказ), 
                # а закупка потом перекроет этот минус
                inv[prod_id][loc_id] = inv[prod_id].get(loc_id, 0) - cnt

            payload = {
                "order_id": order_id,
                "client_id": client_id,
                "employee_id": employee_id,
                "location_id": location_id,
                "product_id": item["id"],
                "order_date": event_dt.date().isoformat(),
                "order_datetime": event_dt.isoformat(),
                "total_amount": total_amount,
                "cnt_products": cnt,
                "discount_amount": discount,
                "basic_amount": basic_amount
            }
            self._send('shop_app_events', 'item_purchased', payload)