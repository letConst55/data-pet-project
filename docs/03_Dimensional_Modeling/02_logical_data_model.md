## Core

The Gold layer ready for data analysis (the *core* schema in the database). At this stage, the model reflects the business processes outlined in the bus matrix and serves as the primary layer accessed by business users and BI applications. Let's describe each object of the data model individually.

### fct_client_bike_rent

The primary fact table, designed as an accumulating snapshot. Bike rental is a prolonged process, essentially a pipeline that can stretch across multiple weeks (but strictly no more than 28 days in our business). The granularity of this data mart is one client + one bike + rental datetime (effectively, this grain is defined by the `rental_id` key). A client can rent any number of bikes any number of times, but a specific bike can only be assigned to one client at a given moment. In other words, records for a specific client and bike cannot overlap in time. If a client extends the rental, a new record is created with a flag indicating that this rental period is an extension of the previous one. For analytical convenience, this mart also includes a flag attribute indicating whether a mechanic was dispatched to the client for technical assistance during the rental.

| column name                      | data type | description                                                   |
|----------------------------------|-----------|---------------------------------------------------------------|
| rental_id (PK) (DD)              | text      | Rental fact identifier                                        |
| client_sk (FK)                   | text      | Client identifier (surrogate key)                             |
| bike_sk (FK)                     | text      | Bike identifier (surrogate key)                               |
| location_dis_id (FK)             | text      | Dispense location identifier                                  |
| location_return_id (FK)          | text      | Return location identifier                                    |
| planned_start_date (FK)          | date      | Planned rental start date                                     |
| planned_end_date (FK)            | date      | Planned rental end date                                       |
| fact_start_date (FK)             | date      | Actual rental start date                                      |
| fact_start_datetime              | timestamp | Actual rental start date and time                             |
| fact_end_date (FK)               | date      | Actual rental end date                                        |
| fact_end_datetime                | timestamp | Actual rental end date and time                               |
| rental_price_daily               | numeric   | Daily rental price                                            |
| deposit_amount                   | numeric   | Deposit amount                                                |
| deposit_deducted_amount          | numeric   | Amount deducted from the deposit                              |
| deduction_reason_code (FK)       | text      | Reason code for deposit deduction                             |
| discount_amount                  | numeric   | Discount amount                                               |
| total_amount                     | numeric   | Total rental cost                                             |
| employee_disp_id (FK)            | text      | Identifier of the employee who dispensed the bike             |
| employee_return_id (FK)          | text      | Identifier of the employee who received the returned bike     |
| actual_start_mileage             | numeric   | Bike mileage at the start of the rental                       |
| actual_end_mileage               | numeric   | Bike mileage at the end of the rental                         |
| fuel_start_percent               | numeric   | Fuel level at the start of the rental                         |
| fuel_end_percent                 | numeric   | Fuel level at the end of the rental                           |
| pre_rental_condition_score (FK)  | int       | Technical condition score of the bike before dispense         |
| post_rental_condition_score (FK) | int       | Technical condition score of the bike upon return             |
| helmets_issued_qty               | int       | Number of helmets issued                                      |
| rental_junk_sk                   | text      | Foreign key referencing the junk dimension containing flags   |

### dim_bike

The bike dimension (reference table), with a granularity of one unique bike. We assume there is no need to track the history of attribute changes for bikes; this table is updated via full overwrite (SCD Type 1). The source data is provided as a CSV file loaded into the database via dbt seeds.

| column name               | data type | description                           |
|---------------------------|-----------|---------------------------------------|
| bike_sk (PK)              | text      | Bike identifier (surrogate key)       |
| bike_natural_key (NK)     | int       | Bike natural key                      |
| WIN_number                | text      | Bike VIN number                       |
| plate_number              | text      | License plate number                  |
| title                     | text      | Model title                           |
| type                      | text      | Bike type (class)                     |
| model_year                | int       | Model year                            |
| color                     | text      | Color                                 |
| brand                     | text      | Brand                                 |
| hourse_power              | numeric   | Horsepower (HP)                       |
| engine_volume_cc          | int       | Engine volume (cc)                    |
| gearbox_type              | text      | Gearbox type                          |
| usb_charging_availability | boolean   | Flag indicating USB charger presence  |
| procurement_price         | int       | Procurement price                     |

### dim_client

The client dimension, updated using the SCD Type 2 strategy. Granularity is one surrogate client key. The table includes technical fields to track the effective period of each record, as well as a boolean flag indicating the currently active version of the record.

| column name              | data type | description                                   |
|--------------------------|-----------|-----------------------------------------------|
| client_sk (PK)           | text      | Client identifier (surrogate key)             |
| client_natural_key (NK)  | text      | Client identifier (natural key)               |
| full_name                | text      | Client's full name                            |
| gender                   | text      | Gender                                        |
| birthday                 | date      | Date of birth                                 |
| salutation               | text      | Salutation form                               |
| preferred_payment_method | text      | Preferred payment method                      |
| phone                    | text      | Mobile phone number                           |
| email                    | text      | Email address                                 |
| nationality              | text      | Nationality                                   |
| residential_address      | text      | Residential address                           |
| driving_experience_years | int       | Years of driving experience                   |
| drive_license_category   | text      | Driving license category                      |
| drive_license_verified   | boolean   | Flag indicating a valid/verified license      |
| rating_score             | int       | Internal client rating score                  |
| row_effective_date       | date      | Record effective start date                   |
| row_expiration_date      | date      | Record expiration date                        |
| current_row_indicator    | boolean   | Current active record flag                    |

### dim_calendar

A classic calendar dimension encompassing various date attributes such as day of the week, holiday/weekend flags, week numbers, etc. Granularity is one day.

| column name         | data type | description                     |
|---------------------|-----------|---------------------------------|
| date (PK)           | date      | Date                            |
| month_year          | text      | Month-Year                      |
| quarter_year        | text      | Quarter-Year                    |
| week_number         | int       | Week number                     |
| dow_number          | int       | Day of week number              |
| dow_text            | text      | Day of week name                |
| is_holiday_flg      | boolean   | Holiday flag                    |
| holiday_name        | text      | Holiday name                    |
| date_key_int        | int       | Date key (integer)              |
| year_number         | int       | Year number                     |
| quarter_number      | int       | Quarter number                  |
| month_number        | int       | Month number                    |
| month_name          | text      | Month name                      |
| month_name_short    | text      | Short month name                |
| day_of_month        | int       | Day of the month                |
| day_of_year         | int       | Day of the year                 |
| dow_text_short      | text      | Short day of week name          |
| is_weekend_flag     | boolean   | Weekend flag                    |
| is_working_day_flag | boolean   | Working day flag                |
| bkk_weather_season  | text      | Current weather season in BKK   |
| week_start_date     | date      | Week start date                 |
| month_start_date    | date      | Month start date                |
| month_end_date      | date      | Last day of the month           |
| is_month_end_flag   | boolean   | Last day of the month flag      |

### dim_rental_junk

A classic junk dimension consolidating various low-cardinality boolean flags to avoid cluttering the fact table. `fct_client_bike_rent` stores a single surrogate key referencing this dimension. For ease of use in BI dashboards, flags are also grouped into logical categories based on data attributes.

| column name               | data type | description                                                                 |
|---------------------------|-----------|-----------------------------------------------------------------------------|
| rental_junk_sk (PK)       | text      | Surrogate key defining granularity                                          |
| helmet_damage_flag        | boolean   | Flag indicating damage to at least one helmet upon return                   |
| field_service_flag        | boolean   | Flag indicating at least one mechanic field dispatch during the rental      |
| rent_extend_flag          | boolean   | Flag indicating rental extension (after the current one ends)               |
| bike_exchange_flag        | boolean   | Flag indicating a bike swap along with a rental extension                   |
| return_status_category    | text      | Flag category descriptor                                                    |

### dim_employee

The company employee dimension. Granularity is one surrogate key, and attribute history is maintained using the SCD Type 2 strategy. The data model also includes a bridge table storing the employee hierarchy, which `dim_employee` references.

| column name               | data type | description                                                                           |
|---------------------------|-----------|---------------------------------------------------------------------------------------|
| employee_sk (PK)          | text      | Employee identifier (surrogate key)                                                   |
| employee_natural_key (NK) | text      | Employee identifier (natural key)                                                     |
| full_name                 | text      | Employee's full name                                                                  |
| phone                     | text      | Mobile phone number                                                                   |
| email                     | text      | Email address                                                                         |
| position_title            | text      | Employee's job title                                                                  |
| grade_level               | text      | Employee's grade level (junior, middle, etc.)                                         |
| assigned_location_id      | text      | Primary location the employee is assigned to                                          |
| department                | text      | Department name                                                                       |
| can_dispense_return_flg   | boolean   | Flag indicating clearance to dispense/receive bikes to/from clients                   |
| can_field_service_flg     | boolean   | Flag indicating clearance for field service dispatches (on-road support)              |
| can_workshop_repair_flg   | boolean   | Flag indicating clearance to perform workshop bike repairs                            |
| can_sell_retail_flg       | boolean   | Flag indicating clearance to work in the retail shop                                  |
| row_effective_date        | date      | Record effective start date                                                           |
| row_expiration_date       | date      | Record expiration date                                                                |
| manager_employee_id       | text      | Manager's (supervisor's) identifier                                                   |
| is_active_flag            | boolean   | Flag indicating if the employee is currently active/employed                          |
| current_row_indicator     | boolean   | Current active record flag                                                            |

### brg_emp_hierarchy

A bridge table containing employee hierarchy data. This table pre-calculates transitive closure (all "Manager-Subordinate" relationships at any depth, including an employee's relationship to themselves at level 0). It also tracks the number of steps (depth) between employees and flags top-level and bottom-level positions.

| column name                  | data type | description                                                 |
|------------------------------|-----------|-------------------------------------------------------------|
| manager_employee_id (FK)     | text      | Manager's natural key                                       |
| subordinate_employee_id (FK) | text      | Subordinate's natural key                                   |
| hierarchy_depth (FK)         | int       | Hierarchy depth (number of steps between the two employees) |
| is_top_level_flg             | boolean   | Top-level position flag                                     |
| is_bottom_level_flg          | boolean   | Bottom-level position flag                                  |

### dim_location

The location dimension, with a granularity of one unique facility. A location can be solely a workshop, a rental spot, a shop, or a combination of all departments. For instance, a rental spot and a shop can be combined and physically situated in the same building (the same location).

| column name               | data type | description                              |
|---------------------------|-----------|------------------------------------------|
| location_sk (PK)          | text      | Location identifier (surrogate key)      |
| location_natural_key (NK) | text      | Location identifier (natural key)        |
| title                     | text      | Location title/name                      |
| full_address              | text      | Physical address                         |
| post_index                | text      | Zip/Postal code                          |
| is_garage_flag            | boolean   | Flag indicating presence of a workshop   |
| is_shop_flag              | boolean   | Flag indicating presence of a shop       |
| is_warehouse_flag         | boolean   | Flag indicating presence of a rental spot|

### dim_bike_condition

We add a bike condition key to the `client_bike_rent` fact table (effectively using the condition score field as the key), which references a separate mini-dimension consisting of 10 rows. Each row describes what a condition score (e.g., a 7) physically means. It includes several attributes: engine condition, suspension condition, plastic/bodywork condition, and a mileage band (e.g., "less than 1000 km"). Essentially, this mini-dimension acts as a mechanic's checklist for scoring the bike's technical condition. We track the history of these changes through the main `client_bike_rent` fact table. Note that the rental fact table is populated with scores that take the bike's return mileage into account. Meaning, if a score of 7 dictates a mileage band of 3000 to 7000 km, and the returning bike has crossed 7000 km on the odometer, its condition score can no longer mathematically exceed 6.

| column name                 | data type | description                              |
|-----------------------------|-----------|------------------------------------------|
| rental_condition_score (PK) | int       | Bike technical condition score key       |
| engine_condition            | text      | Engine condition description             |
| plastic_condition           | text      | Plastic/bodywork condition description   |
| suspension_condition        | text      | Suspension condition description         |
| mileage_band                | text      | Mileage band                             |

### dim_product

The dimension for all products and services. Granularity is one unique product or service. For example, this dimension can contain a row for a physical product (a helmet or gloves) as well as a row for a service (windshield installation). It encompasses regular merchandise (accessories) and bike spare parts. Based on this dimension, we create several subset views for ease of use across different product/service types (e.g., a separate `products` view for retail shop purchases and a `spare parts` view for procurement pipelines).

| column name              | data type | description                                          |
|--------------------------|-----------|------------------------------------------------------|
| product_sk (PK)          | text      | Product identifier (surrogate key)                   |
| product_natural_key (NK) | text      | Product identifier (natural key)                     |
| title                    | text      | Product/Service title                                |
| level1_category          | text      | Level 1 category name                                |
| level2_category          | text      | Level 2 category name                                |
| manufactory              | text      | Product manufacturer                                 |
| vendor (FK)              | text      | Product vendor key                                   |
| is_spare_flag            | boolean   | Flag indicating if the item is a spare part          |
| is_tuning_flag           | boolean   | Flag indicating if the "product" is a tuning service |

### dim_vendor

The dimension for merchandise and spare parts vendors. Granularity is one unique vendor.

| column name             | data type | description                                           |
|-------------------------|-----------|-------------------------------------------------------|
| vendor_sk (PK)          | text      | Vendor identifier (surrogate key)                     |
| vendor_natural_key (NK) | text      | Vendor identifier (natural key)                       |
| vendor_name             | text      | Vendor name                                           |
| is_foreign_flag         | boolean   | Flag indicating if the vendor is a foreign company    |
| vendor_score            | int       | Internal vendor rating score                          |
| vendor_zip_postal_code  | text      | Vendor zip/postal code                                |
| vendor_address          | text      | Vendor's physical corporate address                   |
| vendor_mobile           | text      | Vendor's phone or fax number                          |

### dim_carrier

The carrier (logistics) dimension. Granularity is one unique carrier. Carriers can be internal (company-owned cargo pickup trucks) or external representatives of other transport companies (typically used for delivering large batches of parts or overseas imports).

| column name              | data type | description                                    |
|--------------------------|-----------|------------------------------------------------|
| carrier_sk (PK)          | text      | Carrier identifier (surrogate key)             |
| carrier_natural_key (NK) | text      | Carrier identifier (natural key)               |
| carrier_name             | text      | Carrier name                                   |
| is_external_carrier_flag | boolean   | Flag indicating if the carrier is an external co.|
| carrier_type             | text      | Carrier type (vehicle class)                   |
| carrier_score            | int       | Internal carrier rating score                  |
| carrier_status           | text      | Current carrier status (available, busy)       |

### fct_shop_order

The fact table for retail merchandise purchases and tuning services in the shop. Fact type: Transactional table. Granularity is one unique receipt line item (i.e., one receipt + one unique product).

| column name        | data type | description                                            |
|--------------------|-----------|--------------------------------------------------------|
| shop_order_sk (PK) | text      | Receipt line item identifier (defines granularity)     |
| order_id (DD)      | text      | Shop receipt (order) identifier                        |
| client_sk (FK)     | text      | Client identifier, foreign key                         |
| employee_sk (FK)   | text      | Employee identifier, foreign key                       |
| location_sk (FK)   | text      | Location identifier, foreign key                       |
| product_sk (FK)    | text      | Product identifier, foreign key                        |
| order_date (FK)    | date      | Purchase date (reference to calendar)                  |
| event_datetime     | timestamp | Purchase date and time                                 |
| total_amount       | numeric   | Total line item cost                                   |
| cnt_products       | int       | Quantity of products in the line item                  |
| discount_amount    | numeric   | Line item discount amount                              |
| basic_amount       | numeric   | Base line item cost                                    |

### fct_procurement

The fact table for product and spare parts procurement events from vendors, designed as an accumulating snapshot. Granularity is one shipment identifier + product/part line item. Each shipment pipeline can span several days or weeks, during which the event attributes are progressively populated. For instance, the order creation date is populated first, followed by the actual departure date from the vendor's warehouse, and so on.

| column name                  | data type | description                                                            |
|------------------------------|-----------|------------------------------------------------------------------------|
| procurement_sk (PK)          | text      | Procurement identifier, primary key, defines granularity               |
| shipment_id (PK) (DD)        | text      | Shipment identifier                                                    |
| product_sk (FK)              | text      | Product line item identifier                                           |
| vendor_sk (FK)               | text      | Vendor identifier                                                      |
| carrier_sk (FK)              | text      | Carrier identifier                                                     |
| order_date (FK)              | date      | Procurement order agreement date                                       |
| event_timestamp              | timestamp | Procurement order agreement date and time                              |
| shipment_departure_date (FK) | date      | Actual start date of the delivery pipeline (departure from vendor)     |
| shipment_arrival_date (FK)   | date      | Date the shipment arrived at the location                              |
| arrival_location_sk (FK)     | text      | Identifier of the location receiving the shipment                      |
| vendor_invoice_number (DD)   | text      | Vendor invoice identifier                                              |
| payment_check_number (DD)    | text      | Payment receipt identifier                                             |
| payment_amount               | numeric   | Payment amount for this specific line item                             |
| product_quantity             | int       | Quantity of products in the line item                                  |

### fct_repair

A fact table (accumulating snapshot) with a granularity of one individual bike repair order fact. It tracks the repair pipeline for a bike brought in by an external client for maintenance (this applies strictly to external client bikes, not the rental fleet). In this scenario, the client drops the bike off at the shop, where they can immediately purchase required parts; the bike is then transported to the garage alongside the parts.

| column name                    | data type | description                                                                                       |
|--------------------------------|-----------|---------------------------------------------------------------------------------------------------|
| repair_sk (PK)                 | text      | Repair pipeline identifier (primary key, defines granularity)                                     |
| repair_id (PK) (DD)            | text      | Repair pipeline identifier                                                                        |
| order_id (DD)                  | text      | Identifier of the receipt used to purchase required repair parts (can be Null)                    |
| employee_sk (FK)               | text      | Identifier of the employee who received the client's bike at the shop                             |
| client_sk (FK)                 | text      | Client identifier                                                                                 |
| carrier_sk (FK)                | text      | Carrier identifier (the internal cargo truck transporting the bike to the garage)                 |
| bike_name                      | text      | Bike model name                                                                                   |
| location_shop_sk (FK)          | text      | Shop location identifier                                                                          |
| location_garage_sk (FK)        | text      | Garage location identifier where the bike is ultimately repaired                                  |
| transportation_start_date (FK) | date      | Date the bike was transported from the shop to the garage                                         |
| transportation_end_date (FK)   | date      | Date the bike was transported from the garage back to the shop                                    |
| repair_start_date (FK)         | date      | Actual repair start date                                                                          |
| repair_end_date (FK)           | date      | Actual repair completion date                                                                     |
| invoice_total_amount           | numeric   | Total repair cost                                                                                 |
| invoice_discount_amount        | numeric   | Discount amount provided to the client                                                            |
| event_datetime                 | timestamp | Date and time the event was registered                                                            |

### fct_service_events

A fact table (transactional table) with a granularity of one mechanic field dispatch fact. This data captures instances when mechanics are dispatched to clients due to emergent technical issues on the road, such as flat tires, dead batteries, etc.

| column name                | data type | description                                                     |
|----------------------------|-----------|-----------------------------------------------------------------|
| service_event_sk (PK)      | text      | Event identifier, primary key, defines granularity              |
| service_event_id (PK) (DD) | text      | Mechanic dispatch event identifier                              |
| rental_id (FK)             | text      | Identifier of the active rental triggering the dispatch         |
| client_sk (FK)             | text      | Client identifier                                               |
| bike_sk (FK)               | text      | Bike identifier                                                 |
| event_date (FK)            | date      | Event date                                                      |
| employee_sk (FK)           | text      | Mechanic identifier                                             |
| issue_category             | text      | Technical issue category                                        |
| resolution_action          | text      | Resolution outcome                                              |
| service_cost_usd           | numeric   | Cost of the dispatch and issue resolution                       |
| client_fault_flag          | boolean   | Flag indicating if the issue was caused by client negligence    |
| event_datetime             | timestamp | Event date and time                                             |

### fct_inventory_snapshot

A data mart tracking product availability (stock balances) across garages and shops. The granularity is product + location + week (periodic snapshot). At the end of each week, the table is appended with a new snapshot capturing the actual product quantities and a flag indicating whether at least one unit is available (free). For example, a garage might start the week with two Honda Click engines, but during the week, a bike is brought in for an engine swap. The swap will take this week and the next (as it's a lengthy process), but one engine is placed on hold/reserved, meaning only one engine remains available at the end of the week. Furthermore, the end-of-week snapshot logs whether a replacement engine has already been ordered and the planned delivery date for the new batch.

| column name           | data type | description                                                            |
|-----------------------|-----------|------------------------------------------------------------------------|
| inventory_snapshot_sk (PK) | text      | Unique snapshot identifier                                             |
| snapshot_date_key     | text      | Snapshot date key                                                      |
| week_year             | text      | Week number - Year                                                     |
| product_sk (FK)       | text      | Product identifier                                                     |
| location_sk (FK)      | text      | Location identifier (garage or shop)                                   |
| product_quantity      | int       | Product quantity on hand at the end of the week                        |
| available_flag        | boolean   | Flag indicating if at least one unit is free (available)               |
| isin_shipment_flag    | boolean   | Flag indicating if this product is currently on order at week's end    |
| planned_delivery_date | date      | Planned product delivery date                                          |