import os
import json
import random
from datetime import datetime, timedelta, timezone, date
from core.world_context import WorldContext

class SimulationState:
    def __init__(self, state_file="generator_state.json"):
        self.state_file = state_file
        self.world = WorldContext()
        self.last_logged_event_code = "normal"
        self.state = self._default_state()
        self._load_state()

    def _default_state(self):
        # Get started from 1 march 2024
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
            "active_repairs": [],
            "last_snapshot_week": None
        }

    def get_world_context(self):
        """Returns the current modifiers for seasonality, growth, and cataclysms"""
        return self.world.get_context(self.state["current_sim_time"])

    def advance_time(self, is_pandas_mode=False):
        """Advances the virtual clock, accounting for seasonality and cataclysms."""
        now_utc = datetime.now(timezone.utc)
        
        if not self.state["is_realtime"]:
            ctx = self.get_world_context()
            traffic_mult = ctx["total_traffic_mult"]
            
            if ctx["event_code"] != self.last_logged_event_code:
                self.last_logged_event_code = ctx["event_code"]
                dt_str = self.state["current_sim_time"].date().isoformat()
                print(f"\n🌍 [{dt_str}] CHANGE OF ENVIRONMENT MODE: {ctx['event_title']} (Traffic: x{traffic_mult})\n", flush=True)

            # Base gap (90..330 minutes) divide by traffic coef:
            # At the peak of the season, the interval shrinks. (many events per day),
            base_minutes = random.randint(90, 330)
            scaled_minutes = int(base_minutes / traffic_mult)
            clamped_minutes = max(25, min(600, scaled_minutes))
            
            step = timedelta(minutes=clamped_minutes, seconds=random.randint(0, 59))
            if self.state["current_sim_time"] + step < now_utc:
                self.state["current_sim_time"] += step
            else:
                self.state["current_sim_time"] = now_utc
                self.state["is_realtime"] = True
                print("\n Historical data generated! Switching to real-time mode....\n", flush=True)
        else:
            self.state["current_sim_time"] = now_utc
            
        return self.state["current_sim_time"]


    def save(self):
        """Generate JSON state"""
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
            "active_repairs": [self._serialize_dates(r) for r in self.state.get("active_repairs", [])],
            "last_snapshot_week": self.state.get("last_snapshot_week")
        }
        temp_file = self.state_file + ".tmp"
        with open(temp_file, "w", encoding="utf-8") as f:
            json.dump(serializable, f, ensure_ascii=False, indent=2)
        os.replace(temp_file, self.state_file)

    def _load_state(self):
        if not os.path.exists(self.state_file):
            return

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
        self.state["active_repairs"] = [self._deserialize_dates(r) for r in data.get("active_repairs", [])]
        self.state["last_snapshot_week"] = data.get("last_snapshot_week")

    def _serialize_dates(self, obj):
        res = obj.copy()
        for k, v in res.items():
            if isinstance(v, (datetime, date)):
                res[k] = v.isoformat()
        return res

    def _deserialize_dates(self, obj):
        res = obj.copy()
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
        
        if entity_type not in self.state["counters"]:
            self.state["counters"][entity_type] = 1000
        self.state["counters"][entity_type] += 1
        return self.state["counters"][entity_type]

    def get_employee(self, req_flag, location_id=None):
        """Returns a random active employee with the required clearance level"""
        eligible_local = []
        eligible_anywhere = []
        
        for eid, data in self.state.get("employees", {}).items():
            if not data.get("is_active"): continue
            
            # If permission is granted, add to the global list
            if data.get(req_flag):
                eligible_anywhere.append(eid)
                # If the location matches, add it to the local one
                if location_id and data.get("assigned_location_id") == location_id:
                    eligible_local.append(eid)
                    
        # Priority 1: Employee at the right location
        if eligible_local:
            return random.choice(eligible_local)
            
        # Priority 2: An employee with the required clearance at any other location (on a business trip)
        if eligible_anywhere:
            return random.choice(eligible_anywhere)
            
        # Priority 3: Fallback to the CEO (it is always initialized first)
        ceo_list = [eid for eid, data in self.state.get("employees", {}).items() 
                    if data.get("is_active") and data.get("manager_employee_id") is None]
        
        if ceo_list:
            return ceo_list[0]
            
        return "emp_sys_fallback"