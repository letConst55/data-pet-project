import streamlit as st
import psycopg2
import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
from datetime import datetime

# ==============================================================================
# НАСТРОЙКА СТРАНИЦЫ И SESSION STATE
# ==============================================================================
st.set_page_config(
    page_title="Top Bikes Bangkok — Operations & Commercial Dashboard",
    page_icon="🏍️",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Инициализация состояний в сессии для каждого блока отдельно
if "db_connected" not in st.session_state:
    st.session_state.db_connected = False
if "conn_message" not in st.session_state:
    st.session_state.conn_message = None
for i in range(1, 7):
    if f"show_block_{i}" not in st.session_state:
        st.session_state[f"show_block_{i}"] = False

# ==============================================================================
# САЙДБАР (СЛЕВА): БЛОК ПОДКЛЮЧЕНИЯ К БАЗЕ ДАННЫХ
# ==============================================================================
with st.sidebar:
    st.header("🔌 Database Connection")
    st.caption("Enter PostgreSQL credentials to access DWH marts.")
    
    db_host = st.text_input("Host", value="localhost")
    db_port = st.text_input("Port", value="5432")
    db_name = st.text_input("Database", value="pet_dwh")
    db_user = st.text_input("Username", value="pet_user")
    db_password = st.text_input("Password", value="pet_password", type="password")
    
    if st.button("Test Connection", use_container_width=True, type="primary"):
        try:
            conn = psycopg2.connect(
                dbname=db_name,
                user=db_user,
                password=db_password,
                host=db_host,
                port=db_port,
                connect_timeout=5
            )
            conn.close()
            st.session_state.db_connected = True
            st.session_state.conn_message = ("success", "✅ Database connection established successfully!")
        except Exception as e:
            st.session_state.db_connected = False
            st.session_state.conn_message = ("error", f"❌ Connection failed: {str(e)}")

    if st.session_state.conn_message:
        msg_type, msg_text = st.session_state.conn_message
        if msg_type == "success":
            st.success(msg_text)
        else:
            st.error(msg_text)

# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ РАБОТЫ С БД
# ==============================================================================
def get_db_config():
    return {
        "dbname": db_name,
        "user": db_user,
        "password": db_password,
        "host": db_host,
        "port": db_port
    }

def get_table_schema(cur, table_name):
    """Автоматический поиск схемы таблицы в БД"""
    cur.execute("""
        SELECT table_schema 
        FROM information_schema.tables 
        WHERE table_name = %s 
        LIMIT 1;
    """, (table_name,))
    row = cur.fetchone()
    if not row:
        raise ValueError(f"Table '{table_name}' not found in the database!")
    return row[0]

@st.cache_data(ttl=60, show_spinner=False)
def fetch_block_1_kpis(db_config):
    """Загрузка показателей для Блока 1 (Карточки KPI)"""
    with psycopg2.connect(**db_config) as conn:
        with conn.cursor() as cur:
            # 1. Общее количество локаций бизнеса (всех типов)
            schema_loc = get_table_schema(cur, "dim_location")
            cur.execute(f"SELECT COUNT(DISTINCT location_natural_key) FROM {schema_loc}.dim_location;")
            total_locations = cur.fetchone()[0]

            # 2. Общее количество байков и доля в эксплуатации (по последнему полному месяцу)
            schema_ops = get_table_schema(cur, "agg_monthly_ops_kpis")
            cur.execute(f"""
                SELECT report_month, total_fleet_bikes, active_bikes_cnt, fleet_utilization_rate
                FROM {schema_ops}.agg_monthly_ops_kpis
                ORDER BY report_month DESC
                OFFSET 1 LIMIT 1;
            """)
            ops_row = cur.fetchone()
            if not ops_row:
                cur.execute(f"""
                    SELECT report_month, total_fleet_bikes, active_bikes_cnt, fleet_utilization_rate
                    FROM {schema_ops}.agg_monthly_ops_kpis
                    ORDER BY report_month DESC
                    LIMIT 1;
                """)
                ops_row = cur.fetchone()
            
            report_month, total_bikes, active_bikes, util_rate = ops_row
            active_bikes_share = (active_bikes / total_bikes * 100.0) if total_bikes else 0.0

            # 3. Общее количество актуальных сотрудников (за исключением CEO)
            schema_emp = get_table_schema(cur, "dim_employee")
            cur.execute(f"""
                SELECT COUNT(DISTINCT employee_natural_key)
                FROM {schema_emp}.dim_employee
                WHERE current_row_indicator = true
                  AND is_active_flg = true
                  AND COALESCE(position_title, '') NOT ILIKE '%%CEO%%'
                  AND manager_employee_id IS NOT NULL;
            """)
            total_employees_no_ceo = cur.fetchone()[0]

            # 4. Общее количество уникальных наименований товаров в справочнике dim_product
            schema_prod = get_table_schema(cur, "dim_product")
            cur.execute(f"""
                SELECT 
                    COUNT(*) AS total_rows,
                    COUNT(CASE WHEN is_tuning_flag = false THEN 1 END) AS physical_goods_cnt,
                    COUNT(CASE WHEN is_tuning_flag = true THEN 1 END) AS tuning_services_cnt
                FROM {schema_prod}.dim_product;
            """)
            total_products, physical_goods, tuning_services = cur.fetchone()

    return {
        "total_locations": total_locations,
        "report_month": report_month,
        "total_bikes": total_bikes,
        "active_bikes": active_bikes,
        "active_bikes_share": active_bikes_share,
        "fleet_util_rate": float(util_rate) * 100.0 if util_rate else 0.0,
        "total_employees_no_ceo": total_employees_no_ceo,
        "total_products": total_products,
        "physical_goods": physical_goods,
        "tuning_services": tuning_services
    }

@st.cache_data(ttl=60, show_spinner=False)
def load_clean_mart(db_config, table_name):
    """Загрузка любой ежемесячной витрины с отсечением незавершенного последнего месяца"""
    with psycopg2.connect(**db_config) as conn:
        with conn.cursor() as cur:
            schema = get_table_schema(cur, table_name)
        df = pd.read_sql(f"SELECT * FROM {schema}.{table_name}", conn)
    
    df['report_month'] = pd.to_datetime(df['report_month'])
    if len(df['report_month'].unique()) > 1:
        max_complete_month = df['report_month'].max() - pd.DateOffset(months=1)
        df = df[df['report_month'] <= max_complete_month]
    return df.sort_values('report_month').reset_index(drop=True)

# ==============================================================================
# ФУНКЦИИ ПОСТРОЕНИЯ ГРАФИКОВ БЛОКОВ 2, 3 И 4 (PLOTLY)
# ==============================================================================
def get_common_chart_layout(title_text, show_x_grid=True):
    """Единый чистый шаблон верстки для графиков (легенда снизу, без наложений)"""
    return dict(
        title=dict(
            text=f"<b>{title_text}</b>",
            font=dict(size=14, color="#2c3e50"),
            x=0,
            xanchor="left",
            y=0.95,
            yanchor="top"
        ),
        template="plotly_white",
        height=440,
        margin=dict(l=55, r=55, t=50, b=95),
        legend=dict(
            orientation="h",
            yanchor="top",
            y=-0.20,
            xanchor="center",
            x=0.5,
            font=dict(size=10.5),
            bgcolor="rgba(255,255,255,0)"
        ),
        hovermode="x unified",
        xaxis=dict(showgrid=show_x_grid)
    )

def add_ops_event_bands(fig):
    """Добавляет вертикальные зоны погодных и логистических катаклизмов на график Plotly"""
    events = [
        ("2024-09-01", "2024-10-01", "rgba(231, 76, 60, 0.16)", "🌊 Monsoon Flood", True),
        ("2025-10-01", "2025-11-01", "rgba(231, 76, 60, 0.16)", "🌊 Monsoon Flood", False),
        ("2025-02-01", "2025-03-20", "rgba(243, 156, 18, 0.22)", "🚢 Supply Chain Crisis", True),
        ("2026-06-01", "2026-07-05", "rgba(243, 156, 18, 0.22)", "🚢 Supply Chain Crisis", False),
    ]
    for start, end, color, name, show_leg in events:
        fig.add_vrect(
            x0=start, x1=end,
            fillcolor=color,
            layer="below",
            line_width=0,
        )
        if show_leg:
            fig.add_trace(go.Scatter(
                x=[None], y=[None],
                mode="markers",
                marker=dict(size=9, color=color.replace("0.16", "0.6").replace("0.22", "0.7"), symbol="square"),
                name=name,
                showlegend=True
            ))

def build_block_2_figures(df_ops):
    """Блок 2: Утилизация автопарка и Выездной сервис"""
    # 1. North Star: Fleet Utilization Rate (%)
    fig1 = go.Figure()
    util_pct = df_ops['fleet_utilization_rate'] * 100
    mean_util = util_pct.mean()

    fig1.add_trace(go.Scatter(
        x=df_ops['report_month'], y=util_pct,
        mode="lines+markers",
        name="Fleet Utilization (%)",
        line=dict(color="#2980b9", width=2.5),
        marker=dict(size=7, symbol="circle"),
        hovertemplate="%{y:.1f}%<extra></extra>"
    ))
    fig1.add_hline(
        y=mean_util,
        line_dash="dash", line_color="gray", opacity=0.8,
        annotation_text=f"Avg: {mean_util:.1f}%",
        annotation_position="top left",
        annotation_font=dict(size=11, color="#555")
    )
    add_ops_event_bands(fig1)
    fig1.update_layout(
        yaxis_title="Fleet Utilization (%)",
        **get_common_chart_layout("1. North Star: Fleet Utilization Rate (%)")
    )
    fig1.update_xaxes(tickformat="%Y-%m", tickangle=-25)

    # 2. Breakdown Intensity (Dispatches per 1,000 km) & Field Service Cost ($)
    fig2 = make_subplots(specs=[[{"secondary_y": True}]])
    fig2.add_trace(
        go.Bar(
            x=df_ops['report_month'],
            y=df_ops['total_field_service_cost_usd'],
            name="Service Cost ($)",
            marker_color="rgba(230, 126, 34, 0.28)",
            hovertemplate="$%{y:,.0f}<extra></extra>"
        ),
        secondary_y=True
    )
    fig2.add_trace(
        go.Scatter(
            x=df_ops['report_month'],
            y=df_ops['field_services_per_1000km'],
            mode="lines+markers",
            name="Dispatches / 1,000 km",
            line=dict(color="#c0392b", width=2.5),
            marker=dict(size=7, symbol="square"),
            hovertemplate="%{y:.2f} / 1k km<extra></extra>"
        ),
        secondary_y=False
    )
    add_ops_event_bands(fig2)
    fig2.update_layout(**get_common_chart_layout("2. Breakdown Intensity (/1k km) & Service Cost ($)"))
    fig2.update_xaxes(tickformat="%Y-%m", tickangle=-25)
    fig2.update_yaxes(title_text="Dispatches per 1,000 km", title_font=dict(color="#c0392b", size=12), secondary_y=False)
    fig2.update_yaxes(title_text="Field Service Cost ($)", title_font=dict(color="#d35400", size=12), showgrid=False, secondary_y=True)

    return fig1, fig2

def build_block_3_figures(df_ops):
    """Блок 3: Lead Time цепочек и Оборачиваемость склада"""
    # 3. Lead Time: Procurement vs External Repairs (days)
    fig3 = go.Figure()
    fig3.add_trace(go.Scatter(
        x=df_ops['report_month'],
        y=df_ops['avg_procurement_lead_time_days'],
        mode="lines+markers",
        name="Procurement Lead Time (days)",
        line=dict(color="#8e44ad", width=2.5),
        marker=dict(size=8, symbol="triangle-up"),
        connectgaps=False,
        hovertemplate="%{y:.2f} days<extra></extra>"
    ))
    fig3.add_trace(go.Scatter(
        x=df_ops['report_month'],
        y=df_ops['avg_repair_total_lead_time_days'],
        mode="lines+markers",
        name="External Repair Lead Time (days)",
        line=dict(color="#16a085", width=2.2),
        marker=dict(size=7, symbol="diamond"),
        connectgaps=False,
        hovertemplate="%{y:.2f} days<extra></extra>"
    ))
    add_ops_event_bands(fig3)
    fig3.update_layout(
        yaxis_title="Average Cycle Time (days)",
        **get_common_chart_layout("3. Pipeline Duration: Procurement & Repair Lead Time")
    )
    fig3.update_xaxes(tickformat="%Y-%m", tickangle=-25)

    # 4. Inventory Turnover Ratio (%) vs Out-of-Stock Rate (%)
    fig4 = make_subplots(specs=[[{"secondary_y": True}]])
    fig4.add_trace(
        go.Scatter(
            x=df_ops['report_month'],
            y=df_ops['avg_sku_turnover_ratio'] * 100,
            mode="lines+markers",
            name="Avg SKU Turnover (%)",
            line=dict(color="#27ae60", width=2.5),
            marker=dict(size=7, symbol="circle"),
            hovertemplate="%{y:.2f}%<extra></extra>"
        ),
        secondary_y=False
    )
    oos_pct = df_ops['warehouse_out_of_stock_rate'] * 100
    fig4.add_trace(
        go.Scatter(
            x=df_ops['report_month'],
            y=oos_pct,
            mode="lines+markers",
            name="Out-of-Stock Rate (%)",
            line=dict(color="#e74c3c", width=2.0, dash="dash"),
            marker=dict(size=7, symbol="x"),
            hovertemplate="%{y:.2f}%<extra></extra>"
        ),
        secondary_y=True
    )
    add_ops_event_bands(fig4)
    fig4.update_layout(**get_common_chart_layout("4. Inventory Turnover (%) vs Out-of-Stock Rate (%)"))
    fig4.update_xaxes(tickformat="%Y-%m", tickangle=-25)
    fig4.update_yaxes(title_text="Turnover Ratio (%)", title_font=dict(color="#27ae60", size=12), secondary_y=False)
    
    max_oos = float(oos_pct.max()) if len(oos_pct) > 0 else 0.0
    oos_range = [-0.5, max(5.0, max_oos * 1.2)]
    fig4.update_yaxes(
        title_text="Weeks in Out-of-Stock (%)",
        title_font=dict(color="#e74c3c", size=12),
        range=oos_range,
        tickformat=".1f",
        showgrid=False,
        secondary_y=True
    )

    return fig3, fig4

def build_block_4_figures(df_fleet, df_bikes):
    """Блок 4: Средний Lifetime ROI по классам байков и Эволюция технического состояния парка"""
    # 1. Average Lifetime ROI by Bike Class (на актуальном закрытом месяце)
    latest_month = df_fleet['report_month'].max()
    latest_fleet = df_fleet[df_fleet['report_month'] == latest_month]
    roi_by_type = (
        latest_fleet.groupby('bike_type', as_index=False)['avg_model_roi_ratio']
        .mean()
        .sort_values('avg_model_roi_ratio', ascending=False)
    )
    roi_by_type['roi_pct'] = roi_by_type['avg_model_roi_ratio'] * 100.0

    viridis_colors = ["#3b528b", "#21918c", "#5ec962", "#fde725"]
    bar_colors = viridis_colors[:len(roi_by_type)]

    fig_roi = go.Figure()
    fig_roi.add_trace(go.Bar(
        x=roi_by_type['bike_type'],
        y=roi_by_type['roi_pct'],
        text=[f"<b>{v:.0f}%</b>" for v in roi_by_type['roi_pct']],
        textposition="outside",
        marker=dict(color=bar_colors, line=dict(color="#1a252f", width=1.2)),
        name="Avg Lifetime ROI (%)",
        hovertemplate="Class: <b>%{x}</b><br>Avg ROI: %{y:.1f}%<extra></extra>",
        showlegend=False
    ))
    # Порог окупаемости 100% (добавляем как линию в легенду)
    fig_roi.add_hline(
        y=100,
        line_dash="dash",
        line_color="#e74c3c",
        line_width=2
    )
    fig_roi.add_trace(go.Scatter(
        x=[None], y=[None],
        mode="lines",
        line=dict(color="#e74c3c", width=2, dash="dash"),
        name="Break-Even Threshold (100%)",
        showlegend=True
    ))

    max_roi_val = float(roi_by_type['roi_pct'].max()) if len(roi_by_type) > 0 else 100.0
    fig_roi.update_layout(
        yaxis=dict(title="Return on Investment (ROI, %)", range=[0, max(130.0, max_roi_val * 1.16)]),
        **get_common_chart_layout(
            f"1. Average Lifetime ROI by Bike Class (as of {latest_month.strftime('%Y-%m')})",
            show_x_grid=False
        )
    )
    fig_roi.update_xaxes(title_text="Bike Class (bike_type)", tickangle=0)

    # 2. Эволюция технического состояния парка по месяцам (100% Stacked Area по fleet_health_status)
    health_order = [
        'Optimal (Score 8-10)', 
        'Standard Wear (Score 5-7)', 
        'Needs Overhaul (Score 3-4)', 
        'Critical / Decommission Risk (Score 1-2)'
    ]
    health_colors = {
        'Optimal (Score 8-10)': '#2ecc71',
        'Standard Wear (Score 5-7)': '#f1c40f',
        'Needs Overhaul (Score 3-4)': '#e67e22',
        'Critical / Decommission Risk (Score 1-2)': '#e74c3c'
    }

    health_pivot = (
        df_bikes.groupby(['report_month', 'fleet_health_status'])['bike_natural_key']
        .count()
        .unstack(fill_value=0)
    )
    existing_health = [h for h in health_order if h in health_pivot.columns]
    health_pct = health_pivot[existing_health].div(health_pivot[existing_health].sum(axis=1), axis=0) * 100.0

    fig_health = go.Figure()
    for status in existing_health:
        fig_health.add_trace(go.Scatter(
            x=health_pct.index,
            y=health_pct[status],
            mode="lines",
            line=dict(width=0.5, color=health_colors[status]),
            fillcolor=health_colors[status],
            stackgroup="one",
            name=status,
            hovertemplate=f"<b>{status}</b>: %{{y:.1f}}%<extra></extra>"
        ))

    fig_health.update_layout(
        yaxis=dict(title="Fleet Share (%)", range=[0, 100], ticksuffix="%"),
        **get_common_chart_layout("2. Fleet Technical Condition Evolution (SCD4 Condition)")
    )
    fig_health.update_xaxes(tickformat="%Y-%m", tickangle=-25)

    return fig_roi, fig_health

def build_block_5_figures(df_sup):
    """Блок 5: Анатомия «Бутылочных горлышек» в ремонтах (fct_repair) и поставках (fct_procurement)"""
    # 1. Декомпозиция времени ремонта по месяцам (Inbound Transport + Active Workshop + Outbound Transport)
    rep_valid = df_sup[df_sup['completed_repairs_cnt'] > 0].copy()
    rep_records = []
    for month, grp in rep_valid.groupby('report_month'):
        w = grp['completed_repairs_cnt']
        rep_records.append({
            'report_month_str': month.strftime('%Y-%m'),
            'inbound_days': np.average(grp['avg_inbound_transport_days'], weights=w),
            'active_repair_days': np.average(grp['avg_active_repair_days'], weights=w),
            'outbound_days': np.average(grp['avg_outbound_transport_days'], weights=w)
        })
    rep_monthly_stages = pd.DataFrame(rep_records)

    fig_rep = go.Figure()
    if not rep_monthly_stages.empty:
        stages_config = [
            ('inbound_days', '1. Inbound Transport (to Garage)', '#3498db'),
            ('active_repair_days', '2. Active Workshop Repair', '#e67e22'),
            ('outbound_days', '3. Outbound Transport (to Shop)', '#2ecc71')
        ]
        for col, label, color in stages_config:
            fig_rep.add_trace(go.Bar(
                x=rep_monthly_stages['report_month_str'],
                y=rep_monthly_stages[col],
                name=label,
                marker=dict(color=color, line=dict(color="#1a252f", width=0.8)),
                hovertemplate=f"<b>{label}</b>: %{{y:.2f}} days<extra></extra>"
            ))

    fig_rep.update_layout(
        barmode="stack",
        yaxis=dict(title="Average Stage Duration (days)"),
        **get_common_chart_layout("1. Repair Lead Time Breakdown by Month (Stacked Bar, days)", show_x_grid=False)
    )
    fig_rep.update_xaxes(title_text="Reporting Month", type="category", tickangle=-35)

    # 2. Декомпозиция времени закупки по локациям (Vendor Processing vs Carrier Transit)
    proc_valid = df_sup[df_sup['total_procured_qty'] > 0].copy()
    proc_records = []
    for loc, grp in proc_valid.groupby('location_title'):
        w = grp['total_procured_qty']
        vendor_days = np.average(grp['avg_vendor_processing_days'], weights=w)
        carrier_days = np.average(grp['avg_carrier_transit_days'], weights=w)
        proc_records.append({
            'location_title': loc,
            'vendor_days': vendor_days,
            'carrier_days': carrier_days
        })
    loc_proc_stages = pd.DataFrame(proc_records).sort_values(by='carrier_days', ascending=True)

    fig_proc = go.Figure()
    if not loc_proc_stages.empty:
        fig_proc.add_trace(go.Bar(
            y=loc_proc_stages['location_title'],
            x=loc_proc_stages['vendor_days'],
            name="Vendor Processing",
            orientation="h",
            marker=dict(color="#9b59b6", line=dict(color="#1a252f", width=1.0)),
            hovertemplate="<b>Vendor Processing</b>: %{x:.2f} days<extra></extra>"
        ))
        fig_proc.add_trace(go.Bar(
            y=loc_proc_stages['location_title'],
            x=loc_proc_stages['carrier_days'],
            name="Carrier Transit",
            orientation="h",
            marker=dict(color="#1abc9c", line=dict(color="#1a252f", width=1.0)),
            hovertemplate="<b>Carrier Transit</b>: %{x:.2f} days<extra></extra>"
        ))

    layout_proc = get_common_chart_layout("2. Procurement Lead Time by Location (Vendor vs Carrier, days)", show_x_grid=True)
    layout_proc["hovermode"] = "y unified"
    layout_proc["margin"] = dict(l=210, r=40, t=50, b=95)

    fig_proc.update_layout(
        barmode="stack",
        xaxis_title="Average Delivery Time (days)",
        yaxis_title="Shop / Warehouse Location",
        **layout_proc
    )

    return fig_rep, fig_proc


def build_block_6_figures(df_inv, df_bikes):
    """Блок 6: Оборачиваемость подкатегорий товаров и Bubble-матрица эффективности моделей байков"""
    # 1. Среднемесячная оборачиваемость и объем продаж по подкатегориям 2-го уровня (level2_category)
    cat_stats = (
        df_inv.groupby('level2_category', as_index=False)
        .agg(
            avg_turnover=('inventory_turnover_ratio', 'mean'),
            total_sold=('mtd_sold_qty', 'sum')
        )
        .sort_values('avg_turnover', ascending=True)
    )
    cat_stats['turnover_pct'] = cat_stats['avg_turnover'] * 100.0
    cat_stats['label_text'] = [
        f"<b>{v:.1f}%</b> ({s:,} pcs)" 
        for v, s in zip(cat_stats['turnover_pct'], cat_stats['total_sold'])
    ]

    fig_cat = go.Figure()
    fig_cat.add_trace(go.Bar(
        y=cat_stats['level2_category'],
        x=cat_stats['turnover_pct'],
        orientation="h",
        text=cat_stats['label_text'],
        textposition="outside",
        marker=dict(
            color=cat_stats['turnover_pct'],
            colorscale="YlGnBu",
            line=dict(color="#1a252f", width=0.8)
        ),
        hovertemplate=(
            "Subcategory: <b>%{y}</b><br>"
            "Avg Monthly Turnover: %{x:.2f}%<br>"
            "Total Sold: %{customdata:,} units<extra></extra>"
        ),
        customdata=cat_stats['total_sold'],
        showlegend=False
    ))

    max_turn = float(cat_stats['turnover_pct'].max()) if not cat_stats.empty else 1.0
    layout_cat = get_common_chart_layout("1. Avg Monthly Inventory Turnover by Product Subcategory", show_x_grid=True)
    layout_cat["height"] = 540
    layout_cat["margin"] = dict(l=180, r=60, t=50, b=60)
    layout_cat["hovermode"] = "closest"

    fig_cat.update_layout(**layout_cat)
    fig_cat.update_xaxes(title_text="Monthly Turnover Ratio (%) & Units Sold", range=[0, max_turn * 1.32], showgrid=True)
    fig_cat.update_yaxes(title_text="Product Subcategory (level2_category)")

    # 2. Bubble Chart по моделям байков: Repair Cost (X) vs Procurement Price (Y) vs Avg Monthly Revenue (Size)
    monthly_rev_by_model = (
        df_bikes.groupby('bike_title', as_index=False)['mtd_rental_revenue']
        .mean()
        .rename(columns={'mtd_rental_revenue': 'avg_monthly_rev_per_bike'})
    )

    latest_bikes = df_bikes.sort_values('report_month').groupby('bike_natural_key').last().reset_index()
    model_summary = (
        latest_bikes.groupby(['bike_title', 'bike_type', 'brand'], as_index=False)
        .agg(
            bikes_cnt=('bike_natural_key', 'count'),
            avg_repair_cost_usd=('lifetime_service_cost_usd', 'mean'),
            procurement_price_thb=('procurement_price', 'mean'),
            avg_roi_ratio=('lifetime_roi_ratio', 'mean')
        )
    )
    model_summary['procurement_price_usd'] = model_summary['procurement_price_thb'] / 35.0
    model_summary['avg_roi_pct'] = model_summary['avg_roi_ratio'] * 100.0
    model_summary = model_summary.merge(monthly_rev_by_model, on='bike_title', how='left')

    type_colors = {
        'city bike': '#2980b9',
        'offroad': '#e67e22',
        'touring': '#27ae60'
    }

    fig_bubble = go.Figure()
    if not model_summary.empty:
        max_rev = float(model_summary['avg_monthly_rev_per_bike'].max())
        min_rev = float(model_summary['avg_monthly_rev_per_bike'].min())
        
        for b_type, grp in model_summary.groupby('bike_type'):
            if max_rev > min_rev:
                marker_sizes = 18 + ((grp['avg_monthly_rev_per_bike'] - min_rev) / (max_rev - min_rev)) * 28
            else:
                marker_sizes = [30] * len(grp)

            fig_bubble.add_trace(go.Scatter(
                x=grp['avg_repair_cost_usd'],
                y=grp['procurement_price_usd'],
                mode="markers+text",
                name=f"Class: {b_type}",
                text=grp['bike_title'],
                textposition="top center",
                textfont=dict(size=10.5, color="#1a252f"),
                marker=dict(
                    size=marker_sizes,
                    color=type_colors.get(b_type, "#8e44ad"),
                    opacity=0.82,
                    line=dict(color="#1a252f", width=1.5)
                ),
                customdata=np.stack([
                    grp['brand'],
                    grp['bikes_cnt'],
                    grp['avg_monthly_rev_per_bike'],
                    grp['procurement_price_thb'],
                    grp['avg_roi_pct']
                ], axis=-1),
                hovertemplate=(
                    "<b>%{text}</b> (%{customdata[0]})<br>"
                    "Fleet Units: %{customdata[1]} bikes<br>"
                    "Avg Repair Cost / Bike: <b>$%{x:,.0f}</b><br>"
                    "Procurement Price: <b>$%{y:,.0f}</b> (฿%{customdata[3]:,.0f})<br>"
                    "Avg Monthly Revenue / Bike (Bubble Size): <b>$%{customdata[2]:,.1f}/mo</b><br>"
                    "Avg Lifetime ROI: %{customdata[4]:.0f}%<extra></extra>"
                )
            ))

        mean_x = float(model_summary['avg_repair_cost_usd'].mean())
        mean_y = float(model_summary['procurement_price_usd'].mean())
        fig_bubble.add_vline(x=mean_x, line_dash="dot", line_color="gray", opacity=0.6)
        fig_bubble.add_hline(y=mean_y, line_dash="dot", line_color="gray", opacity=0.6)

        x_pad = float(model_summary['avg_repair_cost_usd'].max() - model_summary['avg_repair_cost_usd'].min()) * 0.18 + 20
        y_pad = float(model_summary['procurement_price_usd'].max() - model_summary['procurement_price_usd'].min()) * 0.18 + 150

        x_range = [
            float(model_summary['avg_repair_cost_usd'].min()) - x_pad,
            float(model_summary['avg_repair_cost_usd'].max()) + x_pad
        ]
        y_range = [
            float(model_summary['procurement_price_usd'].min()) - y_pad,
            float(model_summary['procurement_price_usd'].max()) + y_pad * 1.2
        ]
    else:
        x_range, y_range = None, None

    layout_bub = get_common_chart_layout("2. Model Efficiency: Repair Cost vs Purchase Price (Size = Monthly Rev)", show_x_grid=True)
    layout_bub["height"] = 540
    layout_bub["margin"] = dict(l=65, r=40, t=50, b=95)
    layout_bub["hovermode"] = "closest"

    fig_bubble.update_layout(**layout_bub)
    fig_bubble.update_xaxes(title_text="Avg Cumulative Repair Cost per Bike ($)", range=x_range, showgrid=True)
    fig_bubble.update_yaxes(title_text="Bike Procurement Price ($ USD)", range=y_range, showgrid=True)

    return fig_cat, fig_bubble


# ==============================================================================
# ФУНКЦИЯ ГЕНЕРАЦИИ АВТОНОМНОГО HTML-ФАЙЛА ДЛЯ СКАЧИВАНИЯ
# ==============================================================================
def generate_html_report(kpis_data=None, block2_figs=None, block3_figs=None, block4_figs=None, block5_figs=None, block6_figs=None):
    """Формирует единый HTML-файл со всеми открытыми блоками дашборда"""
    html_parts = [
        "<!DOCTYPE html><html><head><meta charset='utf-8'>",
        "<title>Top Bikes Bangkok — Operations & Commercial Report</title>",
        "<script src='https://cdn.plot.ly/plotly-latest.min.js'></script>",
        "<style>",
        "body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 30px; background: #f8f9fa; color: #2c3e50; }",
        "h1 { color: #1a252f; border-bottom: 2px solid #2980b9; padding-bottom: 10px; }",
        "h2 { color: #2c3e50; margin-top: 35px; border-left: 4px solid #2980b9; padding-left: 10px; }",
        ".kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-top: 20px; margin-bottom: 30px; }",
        ".kpi-card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); border-left: 5px solid #2980b9; }",
        ".kpi-title { font-size: 14px; color: #7f8c8d; text-transform: uppercase; font-weight: 600; }",
        ".kpi-value { font-size: 28px; font-weight: 700; color: #2c3e50; margin: 10px 0 5px 0; }",
        ".kpi-sub { font-size: 13px; color: #27ae60; font-weight: 500; }",
        ".charts-row-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 20px; margin-top: 20px; }",
        ".chart-box { background: white; padding: 15px; border-radius: 10px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }",
        "</style></head><body>",
        "<h1>🏍️ Top Bikes Bangkok — Operations & Commercial Dashboard</h1>",
        f"<p>Generated at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>"
    ]

    if kpis_data and st.session_state.show_block_1:
        html_parts.append("<h2>Block 1: Business Scale & Asset KPIs</h2>")
        html_parts.append(f"""
        <div class='kpi-grid'>
            <div class='kpi-card'>
                <div class='kpi-title'>📍 Total Business Locations</div>
                <div class='kpi-value'>{kpis_data['total_locations']}</div>
                <div class='kpi-sub'>Shops, Garages & Warehouses</div>
            </div>
            <div class='kpi-card'>
                <div class='kpi-title'>🛵 Total Fleet Bikes</div>
                <div class='kpi-value'>{kpis_data['total_bikes']} units</div>
                <div class='kpi-sub'>{kpis_data['active_bikes_share']:.1f}% in operation ({kpis_data['active_bikes']} active in {kpis_data['report_month']})</div>
            </div>
            <div class='kpi-card'>
                <div class='kpi-title'>👥 Active Employees (excl. CEO)</div>
                <div class='kpi-value'>{kpis_data['total_employees_no_ceo']}</div>
                <div class='kpi-sub'>Current active staff</div>
            </div>
            <div class='kpi-card'>
                <div class='kpi-title'>📦 Unique Catalog SKUs</div>
                <div class='kpi-value'>{kpis_data['total_products']}</div>
                <div class='kpi-sub'>{kpis_data['physical_goods']} goods | {kpis_data['tuning_services']} tuning services</div>
            </div>
        </div>
        """)

    if block2_figs and st.session_state.show_block_2:
        html_parts.append("<h2>Block 2: Fleet Utilization & Field Service Dynamics</h2>")
        html_parts.append("<div class='charts-row-2'>")
        for fig in block2_figs:
            html_parts.append(f"<div class='chart-box'>{fig.to_html(full_html=False, include_plotlyjs=False)}</div>")
        html_parts.append("</div>")

    if block3_figs and st.session_state.show_block_3:
        html_parts.append("<h2>Block 3: Supply Chain Lead Time & Inventory Efficiency</h2>")
        html_parts.append("<div class='charts-row-2'>")
        for fig in block3_figs:
            html_parts.append(f"<div class='chart-box'>{fig.to_html(full_html=False, include_plotlyjs=False)}</div>")
        html_parts.append("</div>")

    if block4_figs and st.session_state.show_block_4:
        html_parts.append("<h2>Block 4: Fleet ROI by Class & Technical Condition Evolution</h2>")
        html_parts.append("<div class='charts-row-2'>")
        for fig in block4_figs:
            html_parts.append(f"<div class='chart-box'>{fig.to_html(full_html=False, include_plotlyjs=False)}</div>")
        html_parts.append("</div>")

    if block5_figs and st.session_state.show_block_5:
        html_parts.append("<h2>Block 5: Bottleneck Anatomy in Repairs & Procurements</h2>")
        html_parts.append("<div class='charts-row-2'>")
        for fig in block5_figs:
            html_parts.append(f"<div class='chart-box'>{fig.to_html(full_html=False, include_plotlyjs=False)}</div>")
        html_parts.append("</div>")

    if block6_figs and st.session_state.show_block_6:
        html_parts.append("<h2>Block 6: Category Inventory Turnover & Bike Model Efficiency Matrix</h2>")
        html_parts.append("<div class='charts-row-2'>")
        for fig in block6_figs:
            html_parts.append(f"<div class='chart-box'>{fig.to_html(full_html=False, include_plotlyjs=False)}</div>")
        html_parts.append("</div>")

    if not any([st.session_state[f"show_block_{i}"] for i in range(1, 7)]):
        html_parts.append("<p><i>No visualization blocks were expanded prior to export. Click 'Show plots' and download again.</i></p>")

    html_parts.append("</body></html>")
    return "\n".join(html_parts)

# ==============================================================================
# ПОДГОТОВКА ДАННЫХ ДЛЯ ОТКРЫТЫХ БЛОКОВ
# ==============================================================================
kpis_data = None
db_error_b1 = None
if st.session_state.show_block_1:
    try:
        kpis_data = fetch_block_1_kpis(get_db_config())
    except Exception as e:
        db_error_b1 = str(e)

block2_figs = None
db_error_b2 = None
if st.session_state.show_block_2:
    try:
        df_ops_clean = load_clean_mart(get_db_config(), "agg_monthly_ops_kpis")
        block2_figs = build_block_2_figures(df_ops_clean)
    except Exception as e:
        db_error_b2 = str(e)

block3_figs = None
db_error_b3 = None
if st.session_state.show_block_3:
    try:
        df_ops_clean = load_clean_mart(get_db_config(), "agg_monthly_ops_kpis")
        block3_figs = build_block_3_figures(df_ops_clean)
    except Exception as e:
        db_error_b3 = str(e)

block4_figs = None
db_error_b4 = None
if st.session_state.show_block_4:
    try:
        df_fleet_clean = load_clean_mart(get_db_config(), "agg_monthly_fleet_utilization")
        df_bikes_clean = load_clean_mart(get_db_config(), "stats_by_bikes")
        block4_figs = build_block_4_figures(df_fleet_clean, df_bikes_clean)
    except Exception as e:
        db_error_b4 = str(e)

block5_figs = None
db_error_b5 = None
if st.session_state.show_block_5:
    try:
        df_sup_clean = load_clean_mart(get_db_config(), "agg_monthly_supply_and_repairs")
        block5_figs = build_block_5_figures(df_sup_clean)
    except Exception as e:
        db_error_b5 = str(e)

block6_figs = None
db_error_b6 = None
if st.session_state.show_block_6:
    try:
        df_inv_clean = load_clean_mart(get_db_config(), "stats_by_inventory")
        df_bikes_clean = load_clean_mart(get_db_config(), "stats_by_bikes")
        block6_figs = build_block_6_figures(df_inv_clean, df_bikes_clean)
    except Exception as e:
        db_error_b6 = str(e)

# ==============================================================================
# ОСНОВНАЯ ЧАСТЬ СТРАНИЦЫ (СПРАВА): ШАПКА + БЛОКИ ВИЗУАЛИЗАЦИЙ
# ==============================================================================
header_col1, header_col2 = st.columns([4, 1], vertical_alignment="center")
with header_col1:
    st.title("🏍️ Top Bikes Bangkok — Operations & Commercial")
    st.markdown("Interactive analytical dashboard powered by **PostgreSQL DWH**, **dbt**, and **Streamlit**.")

with header_col2:
    html_report_bytes = generate_html_report(kpis_data, block2_figs, block3_figs, block4_figs, block5_figs, block6_figs).encode("utf-8")
    st.download_button(
        label="📥 Download HTML",
        data=html_report_bytes,
        file_name=f"top_bikes_ops_dashboard_{datetime.now().strftime('%Y%m%d_%H%M')}.html",
        mime="text/html",
        use_container_width=True,
        help="Download the currently opened dashboard blocks as a standalone interactive HTML file."
    )

st.divider()

# ------------------------------------------------------------------------------
# БЛОК 1: КАРТОЧКИ KPI (МАСШТАБ БИЗНЕСА И АКТИВОВ)
# ------------------------------------------------------------------------------
st.subheader("1️⃣ Block 1: Business Scale & Asset KPIs")

if st.button("📊 Show plots (Block 1: KPI Cards)", key="btn_block_1"):
    st.session_state.show_block_1 = True
    st.rerun()

if st.session_state.show_block_1:
    if db_error_b1:
        st.error(f"Error loading KPI data from database: {db_error_b1}. Please check your credentials in the left sidebar.")
    elif kpis_data:
        col1, col2, col3, col4 = st.columns(4)
        
        with col1:
            st.metric(
                label="📍 Total Business Locations",
                value=f"{kpis_data['total_locations']}",
                delta="All facility types",
                delta_color="off"
            )
            st.caption("Includes retail shops, workshops (garages), and rental spots.")

        with col2:
            st.metric(
                label="🛵 Fleet Size & Active Share",
                value=f"{kpis_data['total_bikes']} bikes",
                delta=f"{kpis_data['active_bikes_share']:.1f}% in operation ({kpis_data['active_bikes']} active)",
                delta_color="normal"
            )
            st.caption(f"Based on latest closed month ({kpis_data['report_month']}) | Time Utilization: {kpis_data['fleet_util_rate']:.1f}%")

        with col3:
            st.metric(
                label="👥 Active Employees (excl. CEO)",
                value=f"{kpis_data['total_employees_no_ceo']}",
                delta="Operational staff",
                delta_color="off"
            )
            st.caption("Active current employees in dim_employee excluding CEO.")

        with col4:
            st.metric(
                label="📦 Unique Catalog Items",
                value=f"{kpis_data['total_products']} SKUs",
                delta=f"{kpis_data['physical_goods']} goods / {kpis_data['tuning_services']} services",
                delta_color="off"
            )
            st.caption("Total unique rows in dim_product reference table.")

st.divider()

# ------------------------------------------------------------------------------
# БЛОК 2: УТИЛИЗАЦИЯ АВТОПАРКА И ВЫЕЗДНОЙ СЕРВИС (ГРАФИКИ 1 И 2)
# ------------------------------------------------------------------------------
st.subheader("2️⃣ Block 2: Fleet Utilization & Field Service Dynamics")

if st.button("📈 Show plots (Block 2: Fleet & Field Service)", key="btn_block_2"):
    st.session_state.show_block_2 = True
    st.rerun()

if st.session_state.show_block_2:
    if db_error_b2:
        st.error(f"Error loading Block 2 data: {db_error_b2}")
    elif block2_figs:
        fig1, fig2 = block2_figs
        b2_col1, b2_col2 = st.columns(2)
        with b2_col1:
            st.plotly_chart(fig1, use_container_width=True)
        with b2_col2:
            st.plotly_chart(fig2, use_container_width=True)

st.divider()

# ------------------------------------------------------------------------------
# БЛОК 3: ДЛИТЕЛЬНОСТЬ ЦЕПОЧЕК (LEAD TIME) И ОБОРАЧИВАЕМОСТЬ СКЛАДА (ГРАФИКИ 3 И 4)
# ------------------------------------------------------------------------------
st.subheader("3️⃣ Block 3: Supply Chain Lead Time & Inventory Efficiency")

if st.button("📦 Show plots (Block 3: Supply Chain & Inventory)", key="btn_block_3"):
    st.session_state.show_block_3 = True
    st.rerun()

if st.session_state.show_block_3:
    if db_error_b3:
        st.error(f"Error loading Block 3 data: {db_error_b3}")
    elif block3_figs:
        fig3, fig4 = block3_figs
        b3_col1, b3_col2 = st.columns(2)
        with b3_col1:
            st.plotly_chart(fig3, use_container_width=True)
        with b3_col2:
            st.plotly_chart(fig4, use_container_width=True)

st.divider()

# ------------------------------------------------------------------------------
# БЛОК 4: ОКУПАЕМОСТЬ ПО КЛАССАМ БАЙКОВ (ROI) И ТЕХНИЧЕСКАЯ ДЕГРАДАЦИЯ ПАРКА
# ------------------------------------------------------------------------------
st.subheader("4️⃣ Block 4: Fleet ROI by Class & Technical Condition Evolution")

if st.button("🏍️ Show plots (Block 4: Fleet ROI & Technical Health)", key="btn_block_4"):
    st.session_state.show_block_4 = True
    st.rerun()

if st.session_state.show_block_4:
    if db_error_b4:
        st.error(f"Error loading Block 4 data: {db_error_b4}")
    elif block4_figs:
        fig_roi, fig_health = block4_figs
        b4_col1, b4_col2 = st.columns(2)
        with b4_col1:
            st.plotly_chart(fig_roi, use_container_width=True)
        with b4_col2:
            st.plotly_chart(fig_health, use_container_width=True)


st.divider()

# ------------------------------------------------------------------------------
# БЛОК 5: АНАЛИЗ «БУТЫЛОЧНЫХ ГОРЛЫШЕК» (LEAD TIME РЕМОНТОВ И ПОСТАВОК)
# ------------------------------------------------------------------------------
st.subheader("5️⃣ Block 5: Bottleneck Anatomy in Repairs & Procurements")

if st.button("🔧 Show plots (Block 5: Repair & Supply Bottlenecks)", key="btn_block_5"):
    st.session_state.show_block_5 = True
    st.rerun()

if st.session_state.show_block_5:
    if db_error_b5:
        st.error(f"Error loading Block 5 data: {db_error_b5}")
    elif block5_figs:
        fig_rep, fig_proc = block5_figs
        b5_col1, b5_col2 = st.columns(2)
        with b5_col1:
            st.plotly_chart(fig_rep, use_container_width=True)
        with b5_col2:
            st.plotly_chart(fig_proc, use_container_width=True)


st.divider()

# ------------------------------------------------------------------------------
# БЛОК 6: ОБОРАЧИВАЕМОСТЬ КАТЕГОРИЙ ТОВАРОВ И МАТРИЦА ЭФФЕКТИВНОСТИ МОДЕЛЕЙ БАЙКОВ
# ------------------------------------------------------------------------------
st.subheader("6️⃣ Block 6: Subcategory Turnover & Bike Model Efficiency Matrix")

if st.button("🎯 Show plots (Block 6: Subcategory Turnover & Model Matrix)", key="btn_block_6"):
    st.session_state.show_block_6 = True
    st.rerun()

if st.session_state.show_block_6:
    if db_error_b6:
        st.error(f"Error loading Block 6 data: {db_error_b6}")
    elif block6_figs:
        fig_cat, fig_bubble = block6_figs
        b6_col1, b6_col2 = st.columns(2)
        with b6_col1:
            st.plotly_chart(fig_cat, use_container_width=True)
        with b6_col2:
            st.plotly_chart(fig_bubble, use_container_width=True)