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

    def _get_max_score_by_mileage(self, mileage):
        """Возвращает максимально возможную оценку состояния байка на основе его пробега"""
        if mileage >= 65000:
            return 1
        elif mileage >= 50000:
            return 2
        elif mileage >= 40000:
            return 3
        elif mileage >= 32000:
            return 4
        elif mileage >= 25000:
            return 5
        elif mileage >= 18000:
            return 6
        elif mileage >= 12000:
            return 7
        elif mileage >= 7000:
            return 8
        elif mileage >= 3000:
            return 9
        else:
            return 10

    def generate_client(self):
        clients_dict = self.state_mgr.state["clients"]
        ctx = self.state_mgr.get_world_context()
        season = ctx["season_code"]
        event = ctx["event_code"]
        
        # SCD2: обновление существующего клиента
        if clients_dict and random.random() < 0.30:
            client_id = random.choice(list(clients_dict.keys()))
            profile = clients_dict[client_id].copy()
            profile["residential_address"] = fake.address().replace('\n', ', ')
            profile["preferred_payment_method"] = random.choice(["cash", "credit_card", "promptpay", "alipay"])
            
            # В шторм рейтинг клиентов в среднем немного снижается из-за инцидентов, в промо - растет
            rating_delta = random.uniform(-0.4, 0.2) if event == "monsoon_flood" else random.uniform(-0.2, 0.3)
            profile["rating_score"] = round(min(5.0, max(1.0, profile["rating_score"] + rating_delta)), 1)
            clients_dict[client_id] = profile
            payload = profile
        else:
            client_id = f"cl_{self.state_mgr.get_counter('client')}"
            gender = random.choice(["Male", "Female"])
            
            # В высокий сезон и Сонгкран больше туристов-новичков (стаж 0 лет активирует сегмент Beginner в BI)
            if season == "high_season" or event == "songkran_festival":
                exp_years = random.choices([0, random.randint(1, 4), random.randint(5, 15)], weights=[30, 42, 28], k=1)[0]
                nat_weights = [25, 5, 20, 20, 15, 15]
            else:
                exp_years = random.choices([0, random.randint(1, 4), random.randint(5, 15)], weights=[18, 42, 40], k=1)[0]
                nat_weights = [20, 15, 18, 17, 15, 15]
                
            nationalities = ["Russian", "Thai", "British", "American", "German", "French"]
            nationality = random.choices(nationalities, weights=nat_weights, k=1)[0]
            
            payload = {
                "client_id": client_id,
                "full_name": fake.name_male() if gender == "Male" else fake.name_female(),
                "gender": gender,
                "birthday": fake.date_of_birth(minimum_age=18, maximum_age=60).isoformat(),
                "salutation": "Mr." if gender == "Male" else random.choice(["Ms.", "Mrs."]),
                "phone": fake.phone_number(),
                "email": fake.email(),
                "nationality": nationality,
                "residential_address": fake.address().replace('\n', ', '),
                "preferred_payment_method": random.choice(["cash", "credit_card", "promptpay", "alipay"]),
                "driving_experience_years": exp_years,
                "drive_license_category": "local" if nationality == "Thai" else random.choice(["local", "international"]),
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

        ctx = self.state_mgr.get_world_context()
        season = ctx["season_code"]
        event = ctx["event_code"]

        booking_dt = self.state_mgr.state["current_sim_time"]
        rental_id = f"rnt_{self.state_mgr.get_counter('rental')}"
        client_id = random.choice(list(self.state_mgr.state["clients"].keys()))
        bike_id = random.choice(available_bikes)
        
        self.state_mgr.state["bikes"]["busy"].append(bike_id)

        client_profile = self.state_mgr.state["clients"][client_id]
        exp_years = client_profile.get("driving_experience_years", 1)

        # ШАГ 1: Базовый срок аренды и тариф от водительского стажа клиента
        if exp_years == 0:
            # Новички берут простые скутеры на короткий срок (1-6 дней)
            base_days = random.randint(1, 6)
            rental_price_daily = random.choice([15.00, 20.00])
        elif exp_years <= 4:
            # Городские райдеры и любители берут байк на средний срок (2-12 дней)
            base_days = random.randint(2, 12)
            rental_price_daily = random.choice([15.00, 20.00, 25.00])
        else:
            # Опытные райдеры (5+ лет) берут мощные байки в долгие туры (6-20 дней)
            base_days = random.randint(6, 20)
            rental_price_daily = random.choice([20.00, 25.00, 30.00])

        # ШАГ 2: Модификатор сезона и катаклизмов (масштабирует базовый срок без его перезаписи)
        if event == "monsoon_flood":
            days_mult = 0.50
            discount_amount = random.choice([0.00, 5.00])
        elif event == "grand_promo":
            days_mult = 1.15
            discount_amount = 5.00
        elif season == "high_season" or event == "songkran_festival":
            days_mult = 1.35
            rental_price_daily += 5.00  # Сезонная наценка в пик спроса
            discount_amount = random.choice([0.00, 0.00, 0.00, 5.00])
        elif season == "low_season":
            days_mult = 0.75
            discount_amount = random.choice([0.00, 5.00])
        else:
            days_mult = 1.00
            discount_amount = random.choice([0.00, 0.00, 5.00])

        # Итоговый срок строго в границах от 1 до 28 дней
        rental_days = max(1, min(28, int(round(base_days * days_mult))))
        planned_start_date = (booking_dt + timedelta(days=random.randint(0, 5))).date()
        planned_end_date = planned_start_date + timedelta(days=rental_days)

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
        
        # Оценка ограничена пробегом
        max_score = self._get_max_score_by_mileage(start_mileage)
        pre_score = random.randint(max(1, max_score - 3), max_score)

        # Если это продление аренды, выдача происходит на той же точке, где байк вернули.
        # Для обычного бронирования точка выдачи выбирается независимо.
        location_dis_id = rental_ctx.get("extension_location_id") or random.choice(self.LOCATIONS)

        rental_ctx["fact_start_date"] = fact_start_date
        rental_ctx["dispense_dt"] = dispense_dt
        rental_ctx["actual_start_mileage"] = start_mileage
        rental_ctx["pre_rental_condition_score"] = pre_score
        rental_ctx["field_service_flag"] = False
        rental_ctx["location_dis_id"] = location_dis_id
        
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

        ctx = self.state_mgr.get_world_context()
        season = ctx["season_code"]
        event = ctx["event_code"]

        actual_days = (fact_end_date - rental_ctx["fact_start_date"]).days
        client_profile = self.state_mgr.state["clients"].get(rental_ctx["client_id"], {})
        exp_years = client_profile.get("driving_experience_years", 1)

        # ШАГ 1: Базовый профиль пробега и аккуратности вождения от стажа клиента
        if exp_years == 0:
            # Новички (Beginner): короткие поездки, но высокий риск царапин и падений
            base_km_min, base_km_max = 12, 32
            w1, w2, w3 = 48, 34, 18
            h_ok, h_dmg = 84, 16
        elif exp_years <= 4:
            # Любители (City / Traveller): средний пробег и умеренная аварийность
            base_km_min, base_km_max = 22, 55
            w1, w2, w3 = 74, 19, 7
            h_ok, h_dmg = 94, 6
        else:
            # Профи (Pro_rider, 5+ лет): дальние заезды и минимальный риск повреждений
            base_km_min, base_km_max = 45, 95
            w1, w2, w3 = 90, 8, 2
            h_ok, h_dmg = 98, 2

        # ШАГ 2: Погодные и сезонные модификаторы (накладываются поверх профиля водителя)
        if event == "monsoon_flood":
            km_mult = 0.45
            # В наводнение аварийность резко возрастает у всех категорий
            wear_weights = [max(10, int(w1 * 0.45)), int(w2 * 1.5) + 10, int(w3 * 2.2) + 10]
            helmet_dmg_weights = [max(70, h_ok - 12), h_dmg + 12]
            extend_weights = [95, 5]
        elif event == "songkran_festival":
            km_mult = 0.85
            wear_weights = [max(20, int(w1 * 0.8)), int(w2 * 1.2) + 5, int(w3 * 1.3) + 3]
            helmet_dmg_weights = [max(80, h_ok - 5), h_dmg + 5]
            extend_weights = [75, 25]
        elif event == "extreme_heatwave":
            km_mult = 0.65
            wear_weights = [max(20, int(w1 * 0.85)), int(w2 * 1.15) + 3, w3 + 3]
            helmet_dmg_weights = [h_ok, h_dmg]
            extend_weights = [90, 10]
        elif season == "high_season":
            km_mult = 1.20
            # В сухую погоду больше успешных поездок (Trouble-Free Ratio выше)
            wear_weights = [w1 + 10, max(2, int(w2 * 0.7)), max(1, int(w3 * 0.6))]
            helmet_dmg_weights = [min(99, h_ok + 2), max(1, h_dmg - 2)]
            extend_weights = [78, 22]
        elif season == "low_season":
            km_mult = 0.75
            wear_weights = [max(20, int(w1 * 0.8)), int(w2 * 1.25) + 4, int(w3 * 1.3) + 3]
            helmet_dmg_weights = [max(80, h_ok - 4), h_dmg + 4]
            extend_weights = [88, 12]
        else:
            km_mult = 1.00
            wear_weights = [w1, w2, w3]
            helmet_dmg_weights = [h_ok, h_dmg]
            extend_weights = [85, 15]

        daily_km_min = max(5, int(base_km_min * km_mult))
        daily_km_max = max(daily_km_min + 5, int(base_km_max * km_mult))

        rent_extend_flag = random.choices([False, True], weights=extend_weights, k=1)[0]
        
        distance_ridden = sum(random.randint(daily_km_min, daily_km_max) for _ in range(actual_days))
        end_mileage = rental_ctx["actual_start_mileage"] + distance_ridden
        self.state_mgr.state["bikes"]["mileage"][bike_id] = end_mileage

        pre_score = rental_ctx["pre_rental_condition_score"]
        wear_drop = random.choices([1, 2, 3], weights=wear_weights, k=1)[0]
        
        # Итоговая оценка ограничена новым пробегом
        max_post_score = self._get_max_score_by_mileage(end_mileage)
        post_score = min(max(1, pre_score - wear_drop), max_post_score)

        helmet_damage_flag = random.choices([False, True], weights=helmet_dmg_weights, k=1)[0]

        deposit_deducted = 0.00
        deduction_reason = "none"
        if wear_drop >= 2 or helmet_damage_flag:
            deposit_deducted = random.choice([30.00, 45.00, 100.00])
            deduction_reason = "helmet_damage" if (helmet_damage_flag and wear_drop < 2) else "damage_scratch"

        total_amount = round(max(0.0, (actual_days * rental_ctx["rental_price_daily"]) - rental_ctx["discount_amount"] + deposit_deducted), 2)

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

        # Логика непрерывного продления на той же локации
        if rent_extend_flag:
            new_rental_id = f"rnt_{self.state_mgr.get_counter('rental')}"
            
            if exp_years == 0:
                ext_base_days = random.randint(1, 6)
            elif exp_years <= 4:
                ext_base_days = random.randint(2, 12)
            else:
                ext_base_days = random.randint(6, 20)
                
            new_rental_days = max(1, min(28, int(round(ext_base_days * km_mult))))
            new_planned_end = fact_end_date + timedelta(days=new_rental_days)
            new_discount = random.choice([0.00, 0.00, 5.00])
            
            new_rental_ctx = {
                "rental_id": new_rental_id,
                "client_id": rental_ctx["client_id"],
                "bike_id": bike_id,
                "booking_dt": return_dt,
                "planned_start_date": fact_end_date,
                "planned_end_date": new_planned_end,
                "rental_price_daily": rental_ctx["rental_price_daily"],
                "deposit_amount": 200.00,
                "discount_amount": new_discount,
                "extension_location_id": location_return_id
            }
            self.state_mgr.state["rentals"]["pending"].append(new_rental_ctx)
            
            payload_booking = {
                "rental_id": new_rental_id,
                "client_id": rental_ctx["client_id"],
                "bike_id": bike_id,
                "location_id": location_return_id,
                "planned_start_date": fact_end_date.isoformat(),
                "planned_end_date": new_planned_end.isoformat(),
                "rental_price_daily": rental_ctx["rental_price_daily"],
                "deposit_amount": 200.00,
                "discount_amount": new_discount
            }
            self._send('client_app_events', 'rental_booked', payload_booking)
        else:
            self.state_mgr.state["bikes"]["busy"].remove(bike_id)