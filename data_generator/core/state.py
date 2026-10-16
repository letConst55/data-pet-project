import os
import json
import random
from datetime import datetime, timedelta, timezone, date

class SimulationState:
    def __init__(self, state_file="generator_state.json"):
        self.state_file = state_file
        self.state = self._default_state()
        self._load_state()

    def _default_state(self):
        # Стартуем 1 марта 2024
        return {
            "current_sim_time": datetime(2024, 3, 1, 9, 0, 0, tzinfo=timezone.utc),
            "is_realtime": False,
            "counters": {
                "client": 10000,
                "rental": 5000,
                "order": 1000,
                "repair": 100,
                "procurement": 50
            },
            "clients": {},
            "bikes": {
                "busy": [],           
                "in_repair": [],      
                "mileage": {}         
            },
            "rentals": {
                "pending": [],        
                "active": []          
            },
            "inventory": {},
            "active_repairs": []      # НОВОЕ: Инициализируем хранилище ремонтов
        }

    def advance_time(self, is_pandas_mode=False):
        """Сдвигает виртуальные часы вперед."""
        now_utc = datetime.now(timezone.utc)
        
        if not self.state["is_realtime"]:
            # В историческом режиме шагаем от 1 до 6 часов вперед
            step = timedelta(hours=random.randint(1, 6), minutes=random.randint(0, 59))
            if self.state["current_sim_time"] + step < now_utc:
                self.state["current_sim_time"] += step
            else:
                self.state["current_sim_time"] = now_utc
                self.state["is_realtime"] = True
                print("\n🎉 Исторические данные сгенерированы! Переход в режим реального времени...\n", flush=True)
        else:
            self.state["current_sim_time"] = now_utc
            
        return self.state["current_sim_time"]

    def get_counter(self, entity_type):
        """Безопасная генерация инкрементальных ID"""
        self.state["counters"][entity_type] += 1
        return self.state["counters"][entity_type]

    def save(self):
        """Сериализация состояния в JSON."""
        serializable = {
            "current_sim_time": self.state["current_sim_time"].isoformat(),
            "is_realtime": self.state["is_realtime"],
            "counters": self.state["counters"],
            "clients": self.state["clients"],
            "employees": self.state.get("employees", {}),
            "bikes": self.state["bikes"],
            "inventory": self.state["inventory"],
            "rentals": {
                "pending": [self._serialize_dates(r) for r in self.state["rentals"]["pending"]],
                "active": [self._serialize_dates(r) for r in self.state["rentals"]["active"]]
            },
            # НОВОЕ: Сохраняем активные ремонты
            "active_repairs": [self._serialize_dates(r) for r in self.state.get("active_repairs", [])]
        }
        temp_file = self.state_file + ".tmp"
        with open(temp_file, "w", encoding="utf-8") as f:
            json.dump(serializable, f, ensure_ascii=False, indent=2)
        os.replace(temp_file, self.state_file)

    def _load_state(self):
        if not os.path.exists(self.state_file):
            print("🆕 Файл состояния не найден. Инициализация новой истории с 1 марта 2024...")
            return

        print(f"♻️ Загрузка сохраненного состояния из {self.state_file}...")
        with open(self.state_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.state["current_sim_time"] = datetime.fromisoformat(data["current_sim_time"])
        self.state["is_realtime"] = data.get("is_realtime", False)
        self.state["counters"] = data["counters"]
        self.state["clients"] = data["clients"]
        self.state["employees"] = data.get("employees", {})
        self.state["bikes"] = data["bikes"]
        self.state["inventory"] = data.get("inventory", {})
        
        self.state["rentals"] = {
            "pending": [self._deserialize_dates(r) for r in data["rentals"]["pending"]],
            "active": [self._deserialize_dates(r) for r in data["rentals"]["active"]]
        }
        # НОВОЕ: Восстанавливаем активные ремонты
        self.state["active_repairs"] = [self._deserialize_dates(r) for r in data.get("active_repairs", [])]

    def _serialize_dates(self, obj):
        res = obj.copy()
        for k, v in res.items():
            if isinstance(v, (datetime, date)):
                res[k] = v.isoformat()
        return res

    def _deserialize_dates(self, obj):
        res = obj.copy()
        # НОВОЕ: Добавлены поля дат из garage_api
        date_fields = [
            'planned_start_date', 'planned_end_date', 'fact_start_date',
            'transportation_start_date', 'repair_start_date', 'repair_end_date', 'transportation_end_date'
        ]
        dt_fields = ['booking_dt', 'dispense_dt', 'planned_finish_dt']
        
        for k in date_fields:
            if k in res and res[k]: res[k] = date.fromisoformat(res[k])
        for k in dt_fields:
            if k in res and res[k]: res[k] = datetime.fromisoformat(res[k])
        return res
    
    def get_counter(self, entity_type):
        """Безопасная генерация инкрементальных ID (автосоздание ключа, если его нет)"""
        if entity_type not in self.state["counters"]:
            self.state["counters"][entity_type] = 1000
        self.state["counters"][entity_type] += 1
        return self.state["counters"][entity_type]

    def get_employee(self, req_flag, location_id=None):
        """Возвращает случайного активного сотрудника с нужным допуском"""
        eligible_local = []
        eligible_anywhere = []
        
        for eid, data in self.state.get("employees", {}).items():
            if not data.get("is_active"): continue
            
            # Если допуск есть, добавляем в глобальный список
            if data.get(req_flag):
                eligible_anywhere.append(eid)
                # Если локация совпадает, добавляем в локальный
                if location_id and data.get("assigned_location_id") == location_id:
                    eligible_local.append(eid)
                    
        # Приоритет 1: Сотрудник на нужной локации
        if eligible_local:
            return random.choice(eligible_local)
            
        # Приоритет 2: Сотрудник с нужным допуском на любой другой локации (командировка)
        if eligible_anywhere:
            return random.choice(eligible_anywhere)
            
        # Приоритет 3: Фолбэк на CEO (он всегда инициализируется первым)
        ceo_list = [eid for eid, data in self.state.get("employees", {}).items() 
                    if data.get("is_active") and data.get("manager_employee_id") is None]
        
        if ceo_list:
            return ceo_list[0]
            
        # Если вообще никого нет (баг инициализации)
        return "emp_sys_fallback"