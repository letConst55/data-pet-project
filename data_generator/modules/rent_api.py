import random
from datetime import timedelta, datetime, timezone
from faker import Faker

fake = Faker()

class RentAPI:
    def __init__(self, sim_state, publisher, bikes_list, locations_list):
        self.state_mgr = sim_state
        self.publisher = publisher
        self.BIKES = bikes_list
        self.LOCATIONS = locations_list
        
        # Инициализация пробега для новых байков
        for b in self.BIKES:
            if b not in self.state_mgr.state["bikes"]["mileage"]:
                self.state_mgr.state["bikes"]["mileage"][b] = random.randint(1000, 15000)

    def _send(self, topic, event_type, payload):
        event_dt = self.state_mgr.state["current_sim_time"]
        event_id = f"evt_{fake.uuid4()}"
        self.publisher.publish(topic, event_type, payload, event_dt, event_id)
        
        entity_key = payload.get('rental_id') or payload.get('client_id')
        mode_tag = "LIVE" if self.state_mgr.state["is_realtime"] else "HIST"
        print(f"[{mode_tag} | {event_dt.isoformat()[:16]}] [{topic}] {event_type} -> {entity_key}", flush=True)

    def generate_client(self):
        clients_dict = self.state_mgr.state["clients"]
        
        # SCD2: обновление существующего клиента
        if clients_dict and random.random() < 0.30:
            client_id = random.choice(list(clients_dict.keys()))
            profile = clients_dict[client_id].copy()
            profile["residential_address"] = fake.address().replace('\n', ', ')
            profile["preferred_payment_method"] = random.choice(["cash", "credit_card", "promptpay", "alipay"])
            profile["rating_score"] = round(min(5.0, max(1.0, profile["rating_score"] + random.uniform(-0.3, 0.3))), 1)
            clients_dict[client_id] = profile
            payload = profile
        else:
            client_id = f"cl_{self.state_mgr.get_counter('client')}"
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
            clients_dict[client_id] = payload

        self._send('client_app_events', 'client_profile_updated', payload)

    def book_bike(self):
        if not self.state_mgr.state["clients"]: return
        
        busy_bikes = self.state_mgr.state["bikes"]["busy"] + self.state_mgr.state["bikes"]["in_repair"]
        available_bikes = [b for b in self.BIKES if b not in busy_bikes]
        if not available_bikes: return

        booking_dt = self.state_mgr.state["current_sim_time"]
        rental_id = f"rnt_{self.state_mgr.get_counter('rental')}"
        client_id = random.choice(list(self.state_mgr.state["clients"].keys()))
        bike_id = random.choice(available_bikes)
        
        self.state_mgr.state["bikes"]["busy"].append(bike_id)

        planned_start_date = (booking_dt + timedelta(days=random.randint(0, 5))).date()
        rental_days = random.randint(1, 14)
        planned_end_date = planned_start_date + timedelta(days=rental_days)

        rental_price_daily = random.choice([15.00, 20.00, 25.00])
        discount_amount = random.choice([0.00, 0.00, 5.00, 10.00])

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
        self.state_mgr.state["rentals"]["pending"].append(rental_ctx)

        payload = {
            "rental_id": rental_id,
            "client_id": client_id,
            "bike_id": bike_id,
            "location_id": random.choice(self.LOCATIONS),
            "planned_start_date": planned_start_date.isoformat(),
            "planned_end_date": planned_end_date.isoformat(),
            "rental_price_daily": rental_price_daily,
            "deposit_amount": 200.00,
            "discount_amount": discount_amount
        }
        self._send('client_app_events', 'rental_booked', payload)

    def dispense_bike(self):
        if not self.state_mgr.state["rentals"]["pending"]: return
            
        rental_ctx = self.state_mgr.state["rentals"]["pending"].pop(0)
        dispense_dt = self.state_mgr.state["current_sim_time"]
        fact_start_date = dispense_dt.date()

        bike_id = rental_ctx["bike_id"]
        start_mileage = self.state_mgr.state["bikes"]["mileage"][bike_id]
        pre_score = random.randint(7, 10)

        # Сначала генерируем локацию выдачи
        location_dis_id = random.choice(self.LOCATIONS)

        rental_ctx["fact_start_date"] = fact_start_date
        rental_ctx["dispense_dt"] = dispense_dt
        rental_ctx["actual_start_mileage"] = start_mileage
        rental_ctx["pre_rental_condition_score"] = pre_score
        rental_ctx["field_service_flag"] = False
        rental_ctx["location_dis_id"] = location_dis_id # Теперь переменная существует
        
        self.state_mgr.state["rentals"]["active"].append(rental_ctx)

        payload = {
            "rental_id": rental_ctx["rental_id"],
            "employee_disp_id": self.state_mgr.get_employee("can_dispense_return_flg", location_dis_id),
            "location_dis_id": location_dis_id,
            "fact_start_date": fact_start_date.isoformat(),
            "fact_start_datetime": dispense_dt.isoformat(),
            "actual_start_mileage": start_mileage,
            "fuel_start_percent": random.choice([50, 75, 100]),
            "pre_rental_condition_score": pre_score,
            "helmets_issued_qty": random.randint(1, 2)
        }
        self._send('mechanic_app_events', 'bike_dispensed', payload)

    def return_bike(self):
        if not self.state_mgr.state["rentals"]["active"]: return
            
        rental_ctx = self.state_mgr.state["rentals"]["active"].pop(0)
        bike_id = rental_ctx["bike_id"]
        return_dt = self.state_mgr.state["current_sim_time"]
        fact_end_date = return_dt.date()

        # Защита от возврата в тот же день (чтобы аренда длилась хотя бы 1 день)
        if fact_end_date <= rental_ctx["fact_start_date"]:
            self.state_mgr.state["rentals"]["active"].append(rental_ctx)
            return

        rent_extend_flag = random.choices([False, True], weights=[85, 15], k=1)[0]
        actual_days = (fact_end_date - rental_ctx["fact_start_date"]).days
        
        distance_ridden = sum(random.randint(15, 80) for _ in range(actual_days))
        end_mileage = rental_ctx["actual_start_mileage"] + distance_ridden
        self.state_mgr.state["bikes"]["mileage"][bike_id] = end_mileage

        pre_score = rental_ctx["pre_rental_condition_score"]
        wear_drop = random.choices([1, 2, 3], weights=[70, 20, 10], k=1)[0]
        post_score = max(1, pre_score - wear_drop)

        helmet_damage_flag = random.choices([False, True], weights=[95, 5], k=1)[0]

        deposit_deducted = 0.00
        deduction_reason = "none"
        if wear_drop >= 2 or helmet_damage_flag:
            deposit_deducted = random.choice([30.00, 45.00, 100.00])
            deduction_reason = "helmet_damage" if (helmet_damage_flag and wear_drop < 2) else "damage_scratch"

        total_amount = round(max(0.0, (actual_days * rental_ctx["rental_price_daily"]) - rental_ctx["discount_amount"] + deposit_deducted), 2)

        self.state_mgr.state["bikes"]["busy"].remove(bike_id)

        location_return_id = random.choice(self.LOCATIONS)

        payload = {
            "rental_id": rental_ctx["rental_id"],
            "employee_return_id": self.state_mgr.get_employee("can_dispense_return_flg", location_return_id),
            "location_return_id": location_return_id,
            "fact_end_date": fact_end_date.isoformat(),
            "fact_end_datetime": return_dt.isoformat(),
            "actual_end_mileage": end_mileage,
            "fuel_end_percent": random.choice([10, 25, 50, 75, 100]),
            "post_rental_condition_score": post_score,
            "helmet_damage_flag": helmet_damage_flag,
            "field_service_flag": rental_ctx["field_service_flag"],
            "rent_extend_flag": rent_extend_flag,
            "bike_exchange_flag": False,
            "deposit_deducted_amount": deposit_deducted,
            "deduction_reason_code": deduction_reason,
            "total_amount": total_amount
        }
        self._send('mechanic_app_events', 'bike_returned', payload)