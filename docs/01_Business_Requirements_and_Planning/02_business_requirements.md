# Business Requirements Definition

## Introduction
According to the Kimball methodology, designing a data warehouse always begins with identifying business needs. This document consolidates the results of hypothetical interviews with our primary stakeholders—the heads of the three key departments: Shop, Garage, and Rental.

The goal of this document is to outline the business objectives of each department, formulate key analytical questions, and define the metrics (KPIs) that the Data Warehouse (DWH) must be able to calculate. These requirements serve as the foundation for selecting our core business processes and designing the Enterprise Data Warehouse Bus Matrix.

---

## 1. Rental Department

**Stakeholder:** Operations Manager / Head of Rentals
**Primary Role:** Managing bike dispense and return processes, logging technical conditions, and providing customer support.

### Business Goals
*   Maximize Fleet Utilization — bikes should generate revenue on the road, not sit idle in parking lots.
*   Improve the overall customer experience and minimize on-road technical incidents.
*   Monitor equipment wear and tear to ensure fair deposit deductions upon return.

### Key Analytical Questions
1.  What is our fleet utilization rate (rented days / available days) broken down by bike models, months, client profiles, and specific locations?
2.  How often do clients request a bike swap during their rental period? What are the primary drivers (breakdowns, ergonomic discomfort)?
3.  How rapidly does the technical condition of various bike brands degrade relative to accumulated mileage and rental frequency?
4.  What is the booking seasonality, and how does it correlate with weather patterns in Bangkok?
5.  Which client segments are statistically the most reliable and trouble-free?

### Required KPIs
*   **Fleet Utilization Rate.**
*   **Average Order Value (AOV) and Average Rental Duration.**
*   **Bike Condition Degradation Index** (the delta between the condition scores logged at dispense and return).

---

## 2. Garage Department

**Stakeholder:** Head of Maintenance / Chief Mechanic
**Primary Role:** Scheduled maintenance of the rental fleet, repair of external client bikes (forwarded from the shop), and spare parts inventory tracking. This also encompasses field service dispatches for breakdowns.

### Business Goals
*   Minimize bike downtime (Repair Lead Time) to quickly return assets to the available rental fleet.
*   Reduce the operational costs associated with Field Service dispatches.
*   Ensure high-demand spare parts are consistently available in garage warehouses.
*   Optimize maintenance workflows and track mechanic productivity.

### Key Analytical Questions
1.  How long, on average, is the full repair cycle for a client's bike, from the moment it leaves the shop to its return?
2.  How frequently are our mechanics dispatched for on-road rescues (flat tires, dead batteries), and what is the average cost per dispatch? Are these incidents caused by client negligence or poor scheduled maintenance?
3.  Do we experience "out-of-stock" scenarios for critical consumables like brake pads or air filters? How often does this happen?
4.  What is the productivity of each mechanic (measured by completed repairs and field dispatches)?

### Required KPIs
*   **Field Service Rate** (as a percentage of total active rentals).
*   **Average Repair Lead Time.**
*   **Parts Availability Rate / Out-of-Stock Rate.**

---

## 3. Shop & Retail Department

**Stakeholder:** Retail & Procurement Manager
**Primary Role:** Retail sales of gear and spare parts, tuning services, and supply chain management (including vendor relations).

### Business Goals
*   Increase the profitability of retail sales and tuning services.
*   Optimize the Supply Chain: ensure timely procurement of bikes and parts at optimal prices.
*   Build a resilient and reliable vendor network.

### Key Analytical Questions
1.  Which spare parts and services (e.g., top box installation) yield the highest retail margins?
2.  What is the average duration of the procurement pipeline, from creating a vendor order to the actual arrival of the shipment at our locations?
3.  Which vendors are the most reliable (adhering strictly to delivery SLAs), and which ones frequently delay shipments?
4.  Which client segments tend to combine buying spare parts with ordering comprehensive repairs through our tuning department (cross-sell)?

### Required KPIs
*   **Retail Revenue and Average Ticket Size (AOV).**
*   **On-Time Delivery Rate by vendor.**
*   **Inventory Turnover Ratio.**

---

## Summary for Dimensional Modeling
Based on the gathered requirements, we can isolate the key Business Processes that will translate into Fact Tables within our DWH:
1.  **Bike Rental Process** (dispense, usage, return).
2.  **Shop Purchases and Tuning**.
3.  **Inventory Snapshot** (weekly snapshots of spare parts balances across garages).
4.  **Procurement Pipeline** (tracking the stages of product delivery from vendors).
5.  **Client Bike Repair Pipeline**.
6.  **Field Service Events**.

The core Conformed Dimensions linking these processes will undeniably be: **Date (Calendar), Client, Employee, Location, and Product/Bike**.