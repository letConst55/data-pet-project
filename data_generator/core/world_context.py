from datetime import datetime, timezone

class WorldContext:
    """
    Движок контекста мира: управляет органическим ростом бизнеса,
    климатической сезонностью Бангкока и расписанием катаклизмов / промо-акций.
    """
    def __init__(self):
        self.start_dt = datetime(2024, 3, 1, 0, 0, 0, tzinfo=timezone.utc)
        
        # Детерминированное расписание "Черных лебедей" и маркетинговых кампаний,
        # чтобы при каждом перезапуске пайплайна на дашбордах читалась четкая история
        self.special_events = [
            {
                "code": "songkran_festival",
                "title": "Фестиваль Сонгкран (Тайский Новый год)",
                "ranges": [
                    ("2024-04-11", "2024-04-17"),
                    ("2025-04-11", "2025-04-17"),
                    ("2026-04-11", "2026-04-17")
                ],
                "traffic_mult": 1.75
            },
            {
                "code": "monsoon_flood",
                "title": "🌊 Тропический шторм и наводнение в Бангкоке",
                "ranges": [
                    ("2024-09-14", "2024-09-28"),
                    ("2025-10-03", "2025-10-18")
                ],
                "traffic_mult": 0.40
            },
            {
                "code": "grand_promo",
                "title": "🎉 Масштабная промо-кампания Top Bikes Expo",
                "ranges": [
                    ("2024-12-01", "2024-12-18"),
                    ("2025-11-15", "2025-12-05")
                ],
                "traffic_mult": 1.65
            },
            {
                "code": "supply_chain_crisis",
                "title": "🚢 Логистический кризис и задержка судов в порту",
                "ranges": [
                    ("2025-02-10", "2025-03-15"),
                    ("2026-06-01", "2026-07-05")
                ],
                "traffic_mult": 0.95
            },
            {
                "code": "extreme_heatwave",
                "title": "☀️ Аномальная тепловая волна в Бангкоке (+43°C)",
                "ranges": [
                    ("2025-04-20", "2025-05-08"),
                    ("2026-04-19", "2026-05-06")
                ],
                "traffic_mult": 0.70
            }
        ]

    def get_growth_multiplier(self, current_dt: datetime) -> float:
        """Органический рост стартапа: от 0.65x в марте 2024 до ~1.60x к концу 2026 года"""
        days_since_start = max(0, (current_dt - self.start_dt).days)
        # За ~1000 дней бизнес плавно вырастает почти в 2.5 раза относительно старта
        growth = 0.65 + (days_since_start / 1000.0) * 0.95
        return round(min(1.75, growth), 3)

    def get_season_info(self, current_dt: datetime) -> dict:
        """Климатическая сезонность Бангкока (согласована с dim_calendar)"""
        month = current_dt.month
        # Выходные дни дают небольшой буст трафика (+15%)
        weekend_boost = 1.15 if current_dt.isoweekday() in (6, 7) else 1.0

        if month in (11, 12, 1, 2):
            return {
                "season_code": "high_season",
                "season_name": "Cool & Dry (High Season)",
                "season_mult": round(1.40 * weekend_boost, 3)
            }
        elif month in (3, 4, 5):
            return {
                "season_code": "hot_season",
                "season_name": "Hot Season",
                "season_mult": round(1.05 * weekend_boost, 3)
            }
        else:
            # Июнь - Октябрь: Сезон дождей (муссонов)
            return {
                "season_code": "low_season",
                "season_name": "Monsoon / Rainy (Low Season)",
                "season_mult": round(0.65 * weekend_boost, 3)
            }

    def get_active_event(self, current_dt: datetime) -> dict:
        """Проверяет, действует ли в текущую дату катаклизм или промо-акция"""
        date_str = current_dt.date().isoformat()
        for event in self.special_events:
            for start_str, end_str in event["ranges"]:
                if start_str <= date_str <= end_str:
                    return {
                        "code": event["code"],
                        "title": event["title"],
                        "traffic_mult": event["traffic_mult"]
                    }
        return {
            "code": "normal",
            "title": "Штатный режим работы",
            "traffic_mult": 1.0
        }

    def get_context(self, current_dt: datetime) -> dict:
        """Возвращает полный слепок состояния среды на текущий момент симуляции"""
        growth_mult = self.get_growth_multiplier(current_dt)
        season = self.get_season_info(current_dt)
        event = self.get_active_event(current_dt)

        # Итоговый множитель интенсивности потока событий
        total_traffic_mult = round(growth_mult * season["season_mult"] * event["traffic_mult"], 3)
        # Ограничиваем разумными пределами (от 0.25x в шторм на старте до 3.5x на пике)
        total_traffic_mult = max(0.25, min(3.50, total_traffic_mult))

        return {
            "growth_mult": growth_mult,
            "season_code": season["season_code"],
            "season_name": season["season_name"],
            "season_mult": season["season_mult"],
            "event_code": event["code"],
            "event_title": event["title"],
            "event_mult": event["traffic_mult"],
            "total_traffic_mult": total_traffic_mult
        }