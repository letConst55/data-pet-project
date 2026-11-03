import random
from datetime import timedelta
from faker import Faker

fake = Faker()

class HrAPI:
    def __init__(self, sim_state, publisher, locations_list):
        self.state_mgr = sim_state
        self.publisher = publisher
        self.LOCATIONS = locations_list
        
        # Если блок сотрудников пуст (первый запуск), генерируем ядро штата
        if "employees" not in self.state_mgr.state:
            self.state_mgr.state["employees"] = {}
            
        if not self.state_mgr.state["employees"]:
            self._init_core_staff()

    def _send(self, payload):
        event_dt = self.state_mgr.state["current_sim_time"]
        event_id = f"evt_{fake.uuid4()}"
        self.publisher.publish('hr_app_events', 'employee_profile_updated', payload, event_dt, event_id)
        
        entity_key = payload.get('employee_id')
        mode_tag = "LIVE" if self.state_mgr.state["is_realtime"] else "HIST"
        print(f"[{mode_tag} | {event_dt.isoformat()[:16]}] [hr_app_events] employee_profile_updated -> {entity_key}", flush=True)

    def _create_employee(self, dept, role, grade, loc, manager_id, flags):
        emp_id = f"emp_{self.state_mgr.get_counter('employee')}"
        gender = random.choice(["Male", "Female"])
        
        # Сдвигаем время на 1 секунду для каждого события HR,
        # чтобы гарантировать 100% уникальность event_timestamp для SCD2 окон.
        self.state_mgr.state["current_sim_time"] += timedelta(seconds=1)
        
        payload = {
            "employee_id": emp_id,
            "employee_natural_key": f"NK-{emp_id.upper()}",
            "full_name": fake.name_male() if gender == "Male" else fake.name_female(),
            "phone": fake.phone_number(),
            "email": fake.email(),
            "department": dept,
            "position_title": role,
            "grade_level": grade,
            "assigned_location_id": loc,
            "manager_employee_id": manager_id,
            "can_dispense_return_flg": flags.get("dispense", False),
            "can_field_service_flg": flags.get("field", False),
            "can_workshop_repair_flg": flags.get("repair", False),
            "can_sell_retail_flg": flags.get("sell", False),
            "is_active": True 
        }
        self.state_mgr.state["employees"][emp_id] = payload
        self._send(payload)
        return emp_id

    def _init_core_staff(self):
        """Генерация базовой иерархии при старте симуляции"""
        ceo_id = self._create_employee("Management", "CEO", "C-Level", None, None, {})
        
        for loc in self.LOCATIONS:
            mgr_id = self._create_employee("Operations", "Location Manager", "Senior", loc, ceo_id, {"dispense": True, "sell": True})
            
            # Нанимаем механиков на локацию
            for _ in range(random.randint(2, 4)):
                self._create_employee("Garage", "Mechanic", random.choice(["Junior", "Middle"]), loc, mgr_id, 
                                      {"dispense": True, "field": True, "repair": True})
                
            # Нанимаем продавцов/кассиров на локацию
            for _ in range(random.randint(2, 3)):
                self._create_employee("Shop", "Sales Assistant", random.choice(["Junior", "Middle"]), loc, mgr_id, 
                                      {"dispense": True, "sell": True})
        self.publisher.flush()

    def _get_location_manager(self, loc):
        """Находит активного Location Manager для указанной локации (с фолбэком на CEO)"""
        employees = self.state_mgr.state["employees"]
        for eid, data in employees.items():
            if (data.get("is_active") 
                and data.get("position_title") == "Location Manager" 
                and data.get("assigned_location_id") == loc):
                return eid
                
        # Фолбэк на CEO, если менеджер локации не найден
        for eid, data in employees.items():
            if data.get("is_active") and data.get("manager_employee_id") is None:
                return eid
        return None

    def manage_hr_events(self):
        """Динамические события SCD2: найм, перевод, увольнение (только для линейного персонала)"""
        employees = self.state_mgr.state["employees"]
        
        # Выбираем только активных линейных сотрудников, чтобы не разрушить каркас иерархии (CEO -> Location Manager)
        active_line_emps = [
            eid for eid, data in employees.items()
            if data.get("is_active") and data.get("position_title") in ("Mechanic", "Sales Assistant")
        ]
        if not active_line_emps:
            return

        action = random.choices(["hire", "transfer", "fire"], weights=[40, 50, 10])[0]

        # Защита от вымывания штата: если линейных сотрудников меньше 25, вместо увольнения делаем перевод
        if action == "fire" and len(active_line_emps) <= 25:
            action = "transfer"

        if action == "hire":
            loc = random.choice(self.LOCATIONS)
            manager_id = self._get_location_manager(loc)
            role_type = random.choice(["Mechanic", "Sales"])
            if role_type == "Mechanic":
                self._create_employee("Garage", "Mechanic", "Junior", loc, manager_id, 
                                      {"dispense": True, "field": True, "repair": True})
            else:
                self._create_employee("Shop", "Sales Assistant", "Junior", loc, manager_id, 
                                      {"dispense": True, "sell": True})
                
        elif action == "transfer":
            emp_id = random.choice(active_line_emps)
            emp = employees[emp_id].copy()
            
            # Выбираем новую локацию (отличную от текущей, если локаций больше одной)
            other_locs = [l for l in self.LOCATIONS if l != emp.get("assigned_location_id")]
            new_loc = random.choice(other_locs) if other_locs else emp.get("assigned_location_id")
            
            emp["assigned_location_id"] = new_loc
            emp["manager_employee_id"] = self._get_location_manager(new_loc)
            
            # Вероятность повышения грейда при переводе
            if emp["grade_level"] == "Junior" and random.random() < 0.4:
                emp["grade_level"] = "Middle"
            elif emp["grade_level"] == "Middle" and random.random() < 0.2:
                emp["grade_level"] = "Senior"
                
            self.state_mgr.state["current_sim_time"] += timedelta(seconds=1)
            employees[emp_id] = emp
            self._send(emp)
            
        elif action == "fire":
            emp_id = random.choice(active_line_emps)
            emp = employees[emp_id].copy()
            emp["is_active"] = False
            
            self.state_mgr.state["current_sim_time"] += timedelta(seconds=1)
            employees[emp_id] = emp
            self._send(emp)