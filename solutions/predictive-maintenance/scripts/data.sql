/*************************************************************************************************/
-- PREDICTIVE MAINTENANCE: Demo Data
-- Run this AFTER setup.sql (DDL + schema creation) has completed.
-- Inserts sample data across Bronze, Silver, and Gold layers.
/*************************************************************************************************/
USE ROLE SF_SOLUTIONS_ROLE;
USE WAREHOUSE SF_SOLUTIONS_WH;

/*************************************************************************************************/
-- Step 2: Insert Sample Data (DML)
/*************************************************************************************************/

-- Insert into BRONZE Layer
USE SCHEMA SF_SOLUTIONS.MPM_BRONZE;
INSERT INTO RAW_EQUIPMENT_MASTER (EQUIPMENT_DATA)
SELECT PARSE_JSON(column1) FROM VALUES
('{ "serialNumber": "eq_pump_001", "model": "HydroFlow 5000",'
    || ' "oem": "FlowServe", "installDate": "2022-01-15",'
    || ' "assetType": "Centrifugal Pump",'
    || ' "plant": "Davidson NC"}'),
('{ "serialNumber": "eq_motor_007", "model": "IronHorse 75HP",'
    || ' "oem": "Siemens", "installDate": "2021-11-20",'
    || ' "assetType": "Induction Motor",'
    || ' "plant": "Davidson NC"}');

INSERT INTO RAW_IOT_TELEMETRY (RAW_PAYLOAD, SOURCE_TIMESTAMP)
SELECT PARSE_JSON(column1), column2::TIMESTAMP_NTZ FROM VALUES
-- Normal readings for Pump 001
('{ "deviceId": "eq_pump_001_vib", "metric": "vibration", "value": 0.51, "unit": "mm/s" }', '2025-09-22 10:00:00'),
('{ "deviceId": "eq_pump_001_tmp", "metric": "temperature", "value": 65.2, "unit": "C" }', '2025-09-22 10:00:00'),
('{ "deviceId": "eq_pump_001_vib", "metric": "vibration", "value": 0.55, "unit": "mm/s" }', '2025-09-22 11:00:00'),
-- Anomalous reading
('{ "deviceId": "eq_pump_001_vib", "metric": "vibration", "value": 2.15, "unit": "mm/s" }', '2025-09-23 08:00:00'),
('{ "deviceId": "eq_pump_001_tmp", "metric": "temperature", "value": 75.8, "unit": "C" }', '2025-09-23 08:00:00');

INSERT INTO RAW_MAINTENANCE_LOGS (LOG_DATA)
SELECT PARSE_JSON(column1) FROM VALUES
('{ "workOrderId": "WO-9987", "assetId": "eq_pump_001",'
    || ' "type": "CM",'
    || ' "notes": "High vibration detected.'
    || ' Found bearing misalignment.",'
    || ' "downtimeHours": 4, "laborCost": 600,'
    || ' "partsCost": 250, "failure": true,'
    || ' "date": "2025-09-23"}');


-- Insert into SILVER Layer
USE SCHEMA SF_SOLUTIONS.MPM_SILVER;
-- Populate Dimensions first
SET (START_DATE, END_DATE) = ('1995-01-01', '2030-12-31');
SET GENERATOR_RECORD_COUNT = (SELECT DATEDIFF(DAY, $START_DATE, $END_DATE) + 1);
INSERT OVERWRITE INTO DIM_DATE (DATE_SK, FULL_DATE, DAY_OF_WEEK, MONTH_NAME, QUARTER, YEAR)
SELECT 
    TO_NUMBER(TO_CHAR(d.DATE, 'YYYYMMDD')) AS DATE_SK,
    d.DATE AS FULL_DATE,
    DAYNAME(d.DATE) AS DAY_OF_WEEK,
    TO_CHAR(TO_DATE(d.DATE), 'MMMM') AS MONTH_NAME,
    QUARTER(d.DATE) AS QUARTER,
    YEAR(d.DATE) AS YEAR
FROM (
    SELECT DATEADD(DAY, SEQ4(), $START_DATE) AS DATE
    FROM TABLE(GENERATOR(ROWCOUNT => $GENERATOR_RECORD_COUNT))
) d;

-- Plant and Line Hierarchy
INSERT INTO DIM_PLANT (PLANT_ID, PLANT_NAME, LOCATION, PLANT_UNS_NK) VALUES
(1, 'Davidson Manufacturing', 'Davidson NC', 'snowcore_industries/davidson_nc'),
(2, 'Charlotte Assembly', 'Charlotte NC', 'snowcore_industries/charlotte_nc');

INSERT INTO DIM_LINE (LINE_ID, PLANT_ID, LINE_NAME, HOURLY_REVENUE, LINE_UNS_NK) VALUES
(101, 1, 'Production Line A', 15000.00, 'snowcore_industries/davidson_nc/production_line_a'),
(102, 1, 'Production Line B', 12000.00, 'snowcore_industries/davidson_nc/production_line_b'),
(103, 1, 'Production Line C', 14000.00, 'snowcore_industries/davidson_nc/production_line_c'),
(201, 2, 'Assembly Line 1', 18000.00, 'snowcore_industries/charlotte_nc/assembly_line_1'),
(202, 2, 'Assembly Line 2', 16000.00, 'snowcore_industries/charlotte_nc/assembly_line_2'),
(203, 2, 'Assembly Line 3', 17500.00, 'snowcore_industries/charlotte_nc/assembly_line_3');

-- Manufacturing Processes (3 per line = 18 total processes)
INSERT INTO DIM_PROCESS (PROCESS_NK, PROCESS_NAME, PROCESS_TYPE, LINE_ID, PROCESS_UNS_NK, DESCRIPTION) VALUES
-- Production Line A Processes (Davidson Manufacturing)
('machining_process_a',
'Machining Operations',
'Manufacturing',
101,
'snowcore_industries/davidson_nc/production_line_a/machining_process',
'Primary machining operations including cutting, drilling, and shaping'),
('assembly_process_a',
'Assembly Operations',
'Assembly',
101,
'snowcore_industries/davidson_nc/production_line_a/assembly_process',
'Component assembly and integration operations'),
('testing_process_a',
'Quality Testing',
'Testing',
101,
'snowcore_industries/davidson_nc/production_line_a/testing_process',
'Quality control and testing operations'),

-- Production Line B Processes (Davidson Manufacturing)
('forming_process_b',
'Metal Forming',
'Manufacturing',
102,
'snowcore_industries/davidson_nc/production_line_b/forming_process',
'Metal forming and shaping operations'),
('welding_process_b',
'Welding Operations',
'Manufacturing',
102,
'snowcore_industries/davidson_nc/production_line_b/welding_process',
'Welding and joining operations'),
('finishing_process_b',
'Surface Finishing',
'Manufacturing',
102,
'snowcore_industries/davidson_nc/production_line_b/finishing_process',
'Surface treatment and finishing operations'),

-- Production Line C Processes (Davidson Manufacturing)
('molding_process_c',
'Plastic Molding',
'Manufacturing',
103,
'snowcore_industries/davidson_nc/production_line_c/molding_process',
'Plastic injection molding operations'),
('inspection_process_c',
'Quality Inspection',
'Testing',
103,
'snowcore_industries/davidson_nc/production_line_c/inspection_process',
'Quality inspection and verification'),
('packaging_process_c',
'Final Packaging',
'Assembly',
103,
'snowcore_industries/davidson_nc/production_line_c/packaging_process',
'Final packaging and preparation'),

-- Assembly Line 1 Processes (Charlotte Assembly)
('robot_assembly_1',
'Robotic Assembly',
'Assembly',
201,
'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly',
'Automated robotic assembly operations'),
('manual_assembly_1',
'Manual Assembly',
'Assembly',
201,
'snowcore_industries/charlotte_nc/assembly_line_1/manual_assembly',
'Manual assembly and hand operations'),
('quality_check_1',
'Quality Verification',
'Testing',
201,
'snowcore_industries/charlotte_nc/assembly_line_1/quality_check',
'Quality verification and testing'),

-- Assembly Line 2 Processes (Charlotte Assembly)
('welding_station_2',
'Welding Station',
'Manufacturing',
202,
'snowcore_industries/charlotte_nc/assembly_line_2/welding_station',
'Dedicated welding station operations'),
('heat_treatment_2',
'Heat Treatment',
'Manufacturing',
202,
'snowcore_industries/charlotte_nc/assembly_line_2/heat_treatment',
'Heat treatment and thermal processing'),
('final_inspection_2',
'Final Inspection',
'Testing',
202,
'snowcore_industries/charlotte_nc/assembly_line_2/final_inspection',
'Final quality inspection and approval'),

-- Assembly Line 3 Processes (Charlotte Assembly)
('sorting_process_3',
'Product Sorting',
'Assembly',
203,
'snowcore_industries/charlotte_nc/assembly_line_3/sorting_process',
'Product sorting and classification'),
('packaging_robot_3',
'Automated Packaging',
'Assembly',
203,
'snowcore_industries/charlotte_nc/assembly_line_3/packaging_robot',
'Automated packaging operations'),
('quality_scan_3',
'Quality Scanning',
'Testing',
203,
'snowcore_industries/charlotte_nc/assembly_line_3/quality_scan',
'Automated quality scanning and verification');

-- Asset Classifications
INSERT INTO DIM_ASSET_CLASS (ASSET_CLASS_ID, CLASS_NAME) VALUES
(1, 'Rotating Equipment'),
(2, 'Static Equipment'),
(3, 'Electrical Systems'),
(4, 'Control Systems');

-- Work Order Types (Enhanced)
INSERT INTO DIM_WORK_ORDER_TYPE (WO_TYPE_ID, WO_TYPE_NAME, WO_TYPE_CODE) VALUES
(1, 'Unplanned Emergency', 'UE'),
(2, 'Planned Predictive', 'PP'),
(3, 'Planned Preventive', 'PM'),
(4, 'Inspection', 'INSP');

-- Assets (formerly Equipment) - 3 per line across 6 lines = 18 total
INSERT INTO DIM_ASSET (ASSET_NK,
ASSET_NAME,
MODEL,
OEM_NAME,
PROCESS_ID,
PROCESS_SEQUENCE,
ASSET_CLASS_ID,
INSTALLATION_DATE,
DOWNTIME_IMPACT_PER_HOUR,
ASSET_UNS_NK,
SCD_START_DATE,
IS_CURRENT) VALUES
-- Line 101 Assets (Production Line A) - Machining Process
('eq_pump_001',
'Primary Coolant Pump',
'HydroFlow 5000',
'FlowServe',
1,
1,
1,
'2022-01-15',
7500.00,
'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_pump_001',
'2022-01-15',
TRUE),
('eq_motor_007',
'Conveyor Drive Motor',
'IronHorse 75HP',
'Siemens',
1,
2,
1,
'2021-11-20',
5000.00,
'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_motor_007',
'2021-11-20',
TRUE),
('eq_comp_101',
'Air Compressor Unit',
'CompMax 200',
'Atlas Copco',
1,
3,
1,
'2022-03-10',
6000.00,
'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_comp_101',
'2022-03-10',
TRUE),

-- Line 102 Assets (Production Line B) - Forming Process
('eq_pump_102',
'Hydraulic Pump System',
'PowerFlow 3000',
'Bosch Rexroth',
4,
1,
1,
'2021-08-15',
4500.00,
'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_pump_102',
'2021-08-15',
TRUE),
('eq_motor_102',
'Main Drive Motor',
'PowerMax 50HP',
'ABB',
4,
2,
1,
'2021-09-20',
4000.00,
'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_motor_102',
'2021-09-20',
TRUE),
('eq_fan_102',
'Cooling Fan Assembly',
'AeroMax 1200',
'Ziehl-Abegg',
4,
3,
3,
'2022-01-05',
2500.00,
'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_fan_102',
'2022-01-05',
TRUE),

-- Line 103 Assets (Production Line C) - Molding Process
('eq_pump_103',
'Process Circulation Pump',
'FlowTech 4000',
'Grundfos',
7,
1,
1,
'2021-12-12',
5500.00,
'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_pump_103',
'2021-12-12',
TRUE),
('eq_motor_103',
'Conveyor Motor Assembly',
'DriveForce 60HP',
'Siemens',
7,
2,
1,
'2022-02-18',
4800.00,
'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_motor_103',
'2022-02-18',
TRUE),
('eq_valve_103',
'Control Valve System',
'PrecisionFlow 500',
'Emerson',
7,
3,
2,
'2022-04-22',
3200.00,
'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_valve_103',
'2022-04-22',
TRUE),

-- Line 201 Assets (Assembly Line 1) - Robot Assembly Process
('eq_robot_201',
'Assembly Robot Arm',
'FlexArm 6000',
'KUKA',
10,
1,
4,
'2021-06-30',
9000.00,
'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_robot_201',
'2021-06-30',
TRUE),
('eq_motor_201',
'Conveyor Drive System',
'MegaDrive 100HP',
'Schneider Electric',
10,
2,
1,
'2021-07-15',
6500.00,
'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_motor_201',
'2021-07-15',
TRUE),
('eq_press_201',
'Pneumatic Press Unit',
'PowerPress 5000',
'SMC',
10,
3,
2,
'2021-08-01',
7200.00,
'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_press_201',
'2021-08-01',
TRUE),

-- Line 202 Assets (Assembly Line 2) - Welding Station Process
('eq_robot_202',
'Welding Robot System',
'WeldMaster Pro',
'Fanuc',
13,
1,
4,
'2021-09-10',
8500.00,
'snowcore_industries/charlotte_nc/assembly_line_2/welding_station/eq_robot_202',
'2021-09-10',
TRUE),
('eq_motor_202',
'Material Handling Motor',
'FlexDrive 80HP',
'Rockwell',
13,
2,
1,
'2021-10-05',
5800.00,
'snowcore_industries/charlotte_nc/assembly_line_2/welding_station/eq_motor_202',
'2021-10-05',
TRUE),
('eq_heat_202',
'Heat Treatment Furnace',
'ThermoPro 3000',
'Despatch',
14,
1,
2,
'2021-11-12',
8000.00,
'snowcore_industries/charlotte_nc/assembly_line_2/heat_treatment/eq_heat_202',
'2021-11-12',
TRUE),

-- Line 203 Assets (Assembly Line 3) - Sorting and Packaging Processes
('eq_robot_203',
'Packaging Robot',
'PackBot 2000',
'ABB Robotics',
16,
1,
4,
'2022-01-20',
7800.00,
'snowcore_industries/charlotte_nc/assembly_line_3/packaging_robot/eq_robot_203',
'2022-01-20',
TRUE),
('eq_motor_203',
'Sorting System Motor',
'SortDrive 45HP',
'Baldor',
15,
1,
1,
'2022-02-14',
4200.00,
'snowcore_industries/charlotte_nc/assembly_line_3/sorting_process/eq_motor_203',
'2022-02-14',
TRUE),
('eq_scan_203',
'Quality Control Scanner',
'VisionScan Pro',
'Cognex',
18,
1,
4,
'2022-03-18',
6200.00,
'snowcore_industries/charlotte_nc/assembly_line_3/quality_scan/eq_scan_203',
'2022-03-18',
TRUE);

-- Populate Technicians
INSERT INTO DIM_TECHNICIAN (EMPLOYEE_NK, TECHNICIAN_NAME, CRAFT, SHIFT, HIRE_DATE, IS_ACTIVE) VALUES
('EMP001', 'John Martinez', 'Mechanic', 'Day', '2020-03-15', TRUE),
('EMP002', 'Sarah Chen', 'Electrician', 'Day', '2019-08-22', TRUE),
('EMP003', 'Mike Johnson', 'Instrumentation', 'Day', '2021-01-10', TRUE),
('EMP004', 'Lisa Rodriguez', 'Mechanic', 'Evening', '2020-11-05', TRUE),
('EMP005', 'David Kim', 'Electrician', 'Evening', '2018-09-18', TRUE),
('EMP006', 'Angela Thompson', 'Instrumentation', 'Evening', '2022-04-12', TRUE),
('EMP007', 'Robert Wilson', 'Mechanic', 'Night', '2019-12-03', TRUE),
('EMP008', 'Maria Garcia', 'Electrician', 'Night', '2021-06-28', TRUE),
('EMP009', 'James Lee', 'Instrumentation', 'Night', '2020-07-14', TRUE),
('EMP010', 'Emily Davis', 'Mechanic', 'Day', '2022-01-25', TRUE);

-- Populate Failure Codes
INSERT INTO DIM_FAILURE_CODE (FAILURE_HIERARCHY_1, FAILURE_HIERARCHY_2, FAILURE_HIERARCHY_3, FAILURE_DESCRIPTION) VALUES
('Mechanical', 'Bearing', 'Misalignment', 'Bearing misalignment causing excessive vibration and wear'),
('Mechanical', 'Bearing', 'Lubrication', 'Inadequate or contaminated lubrication leading to bearing failure'),
('Mechanical', 'Seal', 'Wear', 'Seal deterioration causing fluid leakage'),
('Mechanical', 'Coupling', 'Failure', 'Coupling failure due to fatigue or misalignment'),
('Mechanical', 'Impeller', 'Erosion', 'Impeller damage due to cavitation or erosion'),
('Electrical', 'Motor', 'Winding', 'Motor winding failure due to overheating or insulation breakdown'),
('Electrical', 'Motor', 'Connection', 'Loose or corroded electrical connections'),
('Electrical', 'Sensor', 'Calibration', 'Sensor drift or calibration issues affecting readings'),
('Electrical', 'Power Supply', 'Voltage', 'Power supply voltage fluctuations or failures'),
('Operational', 'Overload', 'Capacity', 'Equipment operated beyond design capacity'),
('Operational', 'Temperature', 'Overheating', 'Equipment overheating due to operational conditions'),
('Operational', 'Contamination', 'Foreign Object', 'Foreign object contamination causing operational issues');

-- Populate Materials (Parts and components used in maintenance)
INSERT INTO DIM_MATERIAL (MATERIAL_ID, MATERIAL_NK, MATERIAL_DESC, SUPPLIER_NAME, UNIT_COST) VALUES
(1, 'BRG-001', 'Standard Ball Bearing 6202', 'SKF Industries', 25.50),
(2, 'BRG-002', 'Heavy Duty Roller Bearing', 'Timken Company', 85.00),
(3, 'SEAL-001', 'Oil Seal 35x52x7', 'Parker Hannifin', 12.75),
(4, 'SEAL-002', 'Mechanical Seal Assembly', 'John Crane', 145.00),
(5, 'BELT-001', 'V-Belt A47', 'Gates Corporation', 18.50),
(6, 'FILTER-001', 'Hydraulic Filter Element', 'Pall Corporation', 42.00),
(7, 'FILTER-002', 'Air Filter Cartridge', 'Donaldson Company', 38.50),
(8, 'OIL-001', 'Synthetic Gear Oil 5L', 'Mobil', 55.00),
(9, 'OIL-002', 'Hydraulic Oil ISO 46 20L', 'Shell', 95.00),
(10, 'MOTOR-001', 'Servo Motor 2kW', 'Siemens', 850.00),
(11, 'SENSOR-001', 'Temperature Sensor PT100', 'Omega Engineering', 75.00),
(12, 'SENSOR-002', 'Vibration Sensor Accelerometer', 'PCB Piezotronics', 425.00),
(13, 'VALVE-001', 'Solenoid Valve 24V', 'Emerson', 165.00),
(14, 'COUPLING-001', 'Flexible Coupling', 'Lovejoy', 95.00),
(15, 'GASKET-001', 'Flange Gasket Set', 'Garlock', 22.00),
(16, 'IMPELLER-001', 'Pump Impeller Bronze', 'Goulds Pumps', 320.00),
(17, 'WIRE-001', 'Electrical Wire 10AWG 100ft', '3M', 85.00),
(18, 'RELAY-001', 'Control Relay 24VDC', 'Allen-Bradley', 45.00),
(19, 'FUSE-001', 'Fast-Acting Fuse 30A', 'Bussmann', 8.50),
(20, 'GREASE-001', 'High-Temp Bearing Grease 1lb', 'Mobil', 15.75);

-- Populate Budget Data
INSERT INTO FCT_BUDGET (BUDGET_ID, PLANT_ID, YEAR, QUARTER, BUDGET_TYPE, BUDGET_AMOUNT) VALUES
-- Davidson Manufacturing (Plant 1) - 2025 Budget
(1, 1, 2025, 1, 'OpEx Maintenance', 450000.00),
(2, 1, 2025, 2, 'OpEx Maintenance', 475000.00),
(3, 1, 2025, 3, 'OpEx Maintenance', 500000.00),
(4, 1, 2025, 4, 'OpEx Maintenance', 525000.00),
(5, 1, 2025, 1, 'CapEx Project', 125000.00),
(6, 1, 2025, 2, 'CapEx Project', 150000.00),
(7, 1, 2025, 3, 'CapEx Project', 200000.00),
(8, 1, 2025, 4, 'CapEx Project', 175000.00),

-- Charlotte Assembly (Plant 2) - 2025 Budget
(9, 2, 2025, 1, 'OpEx Maintenance', 550000.00),
(10, 2, 2025, 2, 'OpEx Maintenance', 580000.00),
(11, 2, 2025, 3, 'OpEx Maintenance', 600000.00),
(12, 2, 2025, 4, 'OpEx Maintenance', 625000.00),
(13, 2, 2025, 1, 'CapEx Project', 175000.00),
(14, 2, 2025, 2, 'CapEx Project', 200000.00),
(15, 2, 2025, 3, 'CapEx Project', 250000.00),
(16, 2, 2025, 4, 'CapEx Project', 225000.00),

-- Davidson Manufacturing (Plant 1) - 2024 Actuals for comparison
(17, 1, 2024, 1, 'OpEx Maintenance', 425000.00),
(18, 1, 2024, 2, 'OpEx Maintenance', 445000.00),
(19, 1, 2024, 3, 'OpEx Maintenance', 485000.00),
(20, 1, 2024, 4, 'OpEx Maintenance', 510000.00),
(21, 1, 2024, 1, 'CapEx Project', 100000.00),
(22, 1, 2024, 2, 'CapEx Project', 120000.00),
(23, 1, 2024, 3, 'CapEx Project', 180000.00),
(24, 1, 2024, 4, 'CapEx Project', 160000.00),

-- Charlotte Assembly (Plant 2) - 2024 Actuals for comparison
(25, 2, 2024, 1, 'OpEx Maintenance', 520000.00),
(26, 2, 2024, 2, 'OpEx Maintenance', 555000.00),
(27, 2, 2024, 3, 'OpEx Maintenance', 575000.00),
(28, 2, 2024, 4, 'OpEx Maintenance', 595000.00),
(29, 2, 2024, 1, 'CapEx Project', 150000.00),
(30, 2, 2024, 2, 'CapEx Project', 175000.00),
(31, 2, 2024, 3, 'CapEx Project', 220000.00),
(32, 2, 2024, 4, 'CapEx Project', 200000.00);

-- Sensors (3 per asset = 54 total sensors)
INSERT INTO DIM_SENSOR (SENSOR_NK, ASSET_ID, SENSOR_TYPE, UNITS_OF_MEASURE, SENSOR_UNS_NK) VALUES
-- Asset 1 (Primary Coolant Pump) Sensors
('eq_pump_001_vib', 1, 'Vibration', 'mm/s', 'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_pump_001/vibration'),
('eq_pump_001_tmp',
1,
'Temperature',
'Celsius',
'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_pump_001/temperature'),
('eq_pump_001_psi', 1, 'Pressure', 'PSI', 'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_pump_001/pressure'),

-- Asset 2 (Conveyor Drive Motor) Sensors
('eq_motor_007_vib', 2, 'Vibration', 'mm/s', 'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_motor_007/vibration'),
('eq_motor_007_tmp',
2,
'Temperature',
'Celsius',
'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_motor_007/temperature'),
('eq_motor_007_rpm',
2,
'Rotational Speed',
'RPM',
'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_motor_007/rotational_speed'),

-- Asset 3 (Air Compressor Unit) Sensors
('eq_comp_101_vib', 3, 'Vibration', 'mm/s', 'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_comp_101/vibration'),
('eq_comp_101_tmp',
3,
'Temperature',
'Celsius',
'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_comp_101/temperature'),
('eq_comp_101_psi', 3, 'Pressure', 'PSI', 'snowcore_industries/davidson_nc/production_line_a/machining_process/eq_comp_101/pressure'),

-- Asset 4 (Hydraulic Pump System) Sensors
('eq_pump_102_vib', 4, 'Vibration', 'mm/s', 'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_pump_102/vibration'),
('eq_pump_102_tmp',
4,
'Temperature',
'Celsius',
'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_pump_102/temperature'),
('eq_pump_102_psi', 4, 'Pressure', 'PSI', 'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_pump_102/pressure'),

-- Asset 5 (Main Drive Motor) Sensors
('eq_motor_102_vib', 5, 'Vibration', 'mm/s', 'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_motor_102/vibration'),
('eq_motor_102_tmp',
5,
'Temperature',
'Celsius',
'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_motor_102/temperature'),
('eq_motor_102_cur', 5, 'Current', 'Amps', 'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_motor_102/current'),

-- Asset 6 (Cooling Fan Assembly) Sensors
('eq_fan_102_vib', 6, 'Vibration', 'mm/s', 'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_fan_102/vibration'),
('eq_fan_102_tmp', 6, 'Temperature', 'Celsius', 'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_fan_102/temperature'),
('eq_fan_102_rpm',
6,
'Rotational Speed',
'RPM',
'snowcore_industries/davidson_nc/production_line_b/forming_process/eq_fan_102/rotational_speed'),

-- Asset 7 (Process Circulation Pump) Sensors
('eq_pump_103_vib', 7, 'Vibration', 'mm/s', 'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_pump_103/vibration'),
('eq_pump_103_tmp',
7,
'Temperature',
'Celsius',
'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_pump_103/temperature'),
('eq_pump_103_flw', 7, 'Flow Rate', 'GPM', 'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_pump_103/flow_rate'),

-- Asset 8 (Conveyor Motor Assembly) Sensors
('eq_motor_103_vib', 8, 'Vibration', 'mm/s', 'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_motor_103/vibration'),
('eq_motor_103_tmp',
8,
'Temperature',
'Celsius',
'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_motor_103/temperature'),
('eq_motor_103_trq', 8, 'Torque', 'Nm', 'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_motor_103/torque'),

-- Asset 9 (Control Valve System) Sensors
('eq_valve_103_psi', 9, 'Pressure', 'PSI', 'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_valve_103/pressure'),
('eq_valve_103_tmp',
9,
'Temperature',
'Celsius',
'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_valve_103/temperature'),
('eq_valve_103_pos', 9, 'Position', 'Percent', 'snowcore_industries/davidson_nc/production_line_c/molding_process/eq_valve_103/position'),

-- Asset 10 (Assembly Robot Arm) Sensors
('eq_robot_201_tmp',
10,
'Temperature',
'Celsius',
'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_robot_201/temperature'),
('eq_robot_201_cur', 10, 'Current', 'Amps', 'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_robot_201/current'),
('eq_robot_201_pos', 10, 'Position', 'Degrees', 'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_robot_201/position'),

-- Asset 11 (Conveyor Drive System) Sensors
('eq_motor_201_vib', 11, 'Vibration', 'mm/s', 'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_motor_201/vibration'),
('eq_motor_201_tmp',
11,
'Temperature',
'Celsius',
'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_motor_201/temperature'),
('eq_motor_201_cur', 11, 'Current', 'Amps', 'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_motor_201/current'),

-- Asset 12 (Pneumatic Press Unit) Sensors
('eq_press_201_psi', 12, 'Pressure', 'PSI', 'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_press_201/pressure'),
('eq_press_201_tmp',
12,
'Temperature',
'Celsius',
'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_press_201/temperature'),
('eq_press_201_for', 12, 'Force', 'kN', 'snowcore_industries/charlotte_nc/assembly_line_1/robot_assembly/eq_press_201/force'),

-- Asset 13 (Welding Robot System) Sensors
('eq_robot_202_tmp',
13,
'Temperature',
'Celsius',
'snowcore_industries/charlotte_nc/assembly_line_2/welding_station/eq_robot_202/temperature'),
('eq_robot_202_cur', 13, 'Current', 'Amps', 'snowcore_industries/charlotte_nc/assembly_line_2/welding_station/eq_robot_202/current'),
('eq_robot_202_vol', 13, 'Voltage', 'Volts', 'snowcore_industries/charlotte_nc/assembly_line_2/welding_station/eq_robot_202/voltage'),

-- Asset 14 (Material Handling Motor) Sensors
('eq_motor_202_vib', 14, 'Vibration', 'mm/s', 'snowcore_industries/charlotte_nc/assembly_line_2/welding_station/eq_motor_202/vibration'),
('eq_motor_202_tmp',
14,
'Temperature',
'Celsius',
'snowcore_industries/charlotte_nc/assembly_line_2/welding_station/eq_motor_202/temperature'),
('eq_motor_202_spd', 14, 'Speed', 'RPM', 'snowcore_industries/charlotte_nc/assembly_line_2/welding_station/eq_motor_202/speed'),

-- Asset 15 (Heat Treatment Furnace) Sensors
('eq_heat_202_tmp',
15,
'Temperature',
'Celsius',
'snowcore_industries/charlotte_nc/assembly_line_2/heat_treatment/eq_heat_202/temperature'),
('eq_heat_202_gas', 15, 'Gas Flow', 'SCFM', 'snowcore_industries/charlotte_nc/assembly_line_2/heat_treatment/eq_heat_202/gas_flow'),
('eq_heat_202_oxy',
15,
'Oxygen Level',
'Percent',
'snowcore_industries/charlotte_nc/assembly_line_2/heat_treatment/eq_heat_202/oxygen_level'),

-- Asset 16 (Packaging Robot) Sensors
('eq_robot_203_tmp',
16,
'Temperature',
'Celsius',
'snowcore_industries/charlotte_nc/assembly_line_3/packaging_robot/eq_robot_203/temperature'),
('eq_robot_203_spd', 16, 'Speed', 'Units/Min', 'snowcore_industries/charlotte_nc/assembly_line_3/packaging_robot/eq_robot_203/speed'),
('eq_robot_203_pos', 16, 'Position', 'mm', 'snowcore_industries/charlotte_nc/assembly_line_3/packaging_robot/eq_robot_203/position'),

-- Asset 17 (Sorting System Motor) Sensors
('eq_motor_203_vib', 17, 'Vibration', 'mm/s', 'snowcore_industries/charlotte_nc/assembly_line_3/sorting_process/eq_motor_203/vibration'),
('eq_motor_203_tmp',
17,
'Temperature',
'Celsius',
'snowcore_industries/charlotte_nc/assembly_line_3/sorting_process/eq_motor_203/temperature'),
('eq_motor_203_cur', 17, 'Current', 'Amps', 'snowcore_industries/charlotte_nc/assembly_line_3/sorting_process/eq_motor_203/current'),

-- Asset 18 (Quality Control Scanner) Sensors
('eq_scan_203_tmp', 18, 'Temperature', 'Celsius', 'snowcore_industries/charlotte_nc/assembly_line_3/quality_scan/eq_scan_203/temperature'),
('eq_scan_203_lux',
18,
'Light Intensity',
'Lux',
'snowcore_industries/charlotte_nc/assembly_line_3/quality_scan/eq_scan_203/light_intensity'),
('eq_scan_203_fps', 18, 'Scan Rate', 'FPS', 'snowcore_industries/charlotte_nc/assembly_line_3/quality_scan/eq_scan_203/scan_rate');

-- Populate Facts using IDs from Dimensions
-- Asset Telemetry (Hourly readings for all 18 assets from Nov 1, 2024 to current date)
-- Using a CTE to generate hourly data dynamically
INSERT INTO FCT_ASSET_TELEMETRY (ASSET_ID,
PROCESS_ID,
DATE_SK,
RECORDED_AT,
TEMPERATURE_C,
VIBRATION_MM_S,
PRESSURE_PSI,
HEALTH_SCORE,
FAILURE_PROBABILITY,
RUL_DAYS,
IS_ANOMALOUS)
WITH date_params AS (
    SELECT 
        '2024-11-01 00:00:00'::TIMESTAMP_NTZ AS start_timestamp,
        DATE_TRUNC('HOUR', CURRENT_TIMESTAMP())::TIMESTAMP_NTZ AS end_timestamp,
        -- Decay start date: 90 days ago from current time (assets are healthy before this)
        DATE_TRUNC('HOUR', DATEADD(DAY, -90, CURRENT_TIMESTAMP()))::TIMESTAMP_NTZ AS decay_start_timestamp
),
hourly_base AS (
    SELECT 
        a.asset_id,
        a.process_id,
        DATEADD(HOUR, h.hour_seq, dp.start_timestamp) AS recorded_at,
        TO_NUMBER(TO_CHAR(DATEADD(HOUR, h.hour_seq, dp.start_timestamp), 'YYYYMMDD')) AS date_sk,
        h.hour_seq,
        HOUR(DATEADD(HOUR, h.hour_seq, dp.start_timestamp)) AS hour_of_day,
        DATEDIFF(DAY, dp.start_timestamp, DATEADD(HOUR, h.hour_seq, dp.start_timestamp)) AS days_elapsed,
        -- Calculate days since decay started (0 or negative if before decay start)
        GREATEST(0, DATEDIFF(DAY, dp.decay_start_timestamp, DATEADD(HOUR, h.hour_seq, dp.start_timestamp))) AS days_since_decay_start
    FROM date_params dp
    CROSS JOIN (
        SELECT 
            da.ASSET_ID,
            da.PROCESS_ID
        FROM SF_SOLUTIONS.MPM_SILVER.DIM_ASSET da
        WHERE da.IS_CURRENT = TRUE
    ) a
    CROSS JOIN (
        SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS hour_seq
        FROM TABLE(GENERATOR(ROWCOUNT => 10000))  -- Enough for ~13 months
    ) h
    WHERE DATEADD(HOUR, h.hour_seq, dp.start_timestamp) <= dp.end_timestamp
),
sensor_data AS (
    SELECT 
        asset_id,
        process_id,
        date_sk,
        recorded_at,
        hour_of_day,
        days_elapsed,
        days_since_decay_start,
        -- Generate realistic sensor data based on asset type and time (controlled ranges)
        -- Temperature increases only after decay start date
        CASE 
            -- Pumps run warmer, gradual degradation
            WHEN asset_id IN (1,4,7) THEN ROUND(60 + (hour_of_day * 0.5) + (days_since_decay_start * 0.1) + UNIFORM(-3, 7, RANDOM()), 2)
            -- Motors
            WHEN asset_id IN (2,
            5,
            8,
            11,
            14,
            17) THEN ROUND(55 + (hour_of_day * 0.3) + (days_since_decay_start * 0.08) + UNIFORM(-2,
            6,
            RANDOM()),
            2)
            -- Robots
            WHEN asset_id IN (10,13,16) THEN ROUND(50 + (hour_of_day * 0.2) + (days_since_decay_start * 0.05) + UNIFORM(-2, 4, RANDOM()), 2)
            -- Furnace much hotter
            WHEN asset_id = 15 THEN ROUND(200 + (hour_of_day * 2) + (days_since_decay_start * 0.5) + UNIFORM(-10, 10, RANDOM()), 2)
            ELSE ROUND(45 + (hour_of_day * 0.4) + (days_since_decay_start * 0.06) + UNIFORM(-2, 3, RANDOM()), 2)  -- Other equipment
        END AS temperature_c,
        
        -- Vibration data (rotating equipment has higher vibration) - controlled precision with degradation
        -- Vibration increases only after decay start date
        CASE 
            -- Rotating equipment
            WHEN asset_id IN (1,2,4,5,7,8,11,14,17) THEN ROUND(0.3 + (days_since_decay_start * 0.002) + UNIFORM(0, 0.4, RANDOM()), 2)
            -- Robots (less vibration)
            WHEN asset_id IN (10,13,16) THEN ROUND(0.1 + (days_since_decay_start * 0.001) + UNIFORM(0, 0.2, RANDOM()), 2)
            ELSE ROUND(0.05 + UNIFORM(0, 0.1, RANDOM()), 2)  -- Static equipment
        END AS vibration_mm_s,
        
        -- Pressure data (only for pumps, compressors, and pneumatic systems) - controlled range
        CASE 
            WHEN asset_id IN (1,3,4,7,9,12) THEN ROUND(140 + UNIFORM(-5, 15, RANDOM()), 2)  -- Equipment with pressure sensors
            ELSE NULL
        END AS pressure_psi,
        
        -- Health score (degrades over time with realistic variation) - range 10-100 for interesting insights
        -- Base health degrades with time ONLY after decay_start_date (90 days ago)
        -- Before decay start: assets are healthy (95-100)
        -- After decay start: gradual degradation over 90 days
        -- Decay rate: 0.3 per day over 90 days = ~27 points base decay + wide asset-specific variation
        -- This creates interesting ranges: critical (<50), warning (50-70), good (70-85), excellent (85+)
        ROUND(GREATEST(10, LEAST(100, 
            100 - (days_since_decay_start * 0.3) - (hour_of_day * 0.06) - 
            CASE 
                -- Critical pumps (heavily degraded)
                WHEN asset_id IN (1,7) THEN UNIFORM(25, 45, RANDOM())  -- Pumps worst condition (CRITICAL: 28-48 range)
                -- Warning pump (moderate issues)
                WHEN asset_id = 4 THEN UNIFORM(15, 30, RANDOM())  -- Pump with some issues (WARNING: 43-58 range)
                -- Critical/Warning motors (mixed conditions)
                WHEN asset_id IN (2,8,14) THEN UNIFORM(18, 38, RANDOM())  -- Motors with issues (WARNING-CRITICAL: 35-55 range)
                -- Good motors (well maintained)
                WHEN asset_id IN (5,11,17) THEN UNIFORM(0, 15, RANDOM())  -- Motors in good shape (GOOD: 58-73 range)
                -- Excellent robots (newest/best maintained)
                WHEN asset_id IN (10,16) THEN UNIFORM(-5, 5, RANDOM())  -- Robots excellent (EXCELLENT: 68-78 range)
                -- Good robot (reliable)
                WHEN asset_id = 13 THEN UNIFORM(0, 10, RANDOM())  -- Robot good condition (GOOD: 63-73 range)
                -- Critical/Warning other equipment
                WHEN asset_id IN (3,6,9,12,18) THEN UNIFORM(20, 40, RANDOM())  -- Conveyors/scanners mixed (WARNING-CRITICAL: 33-53 range)
                -- Good other equipment
                ELSE UNIFORM(5, 20, RANDOM())  -- Other equipment decent (GOOD: 53-68 range)
            END
        )), 2) AS health_score
    FROM hourly_base
)
SELECT 
    asset_id,
    process_id,
    date_sk,
    recorded_at,
    temperature_c,
    vibration_mm_s,
    pressure_psi,
    health_score,
    
    -- Failure probability (inversely correlated with health score) - range 0.01 to 0.95
    -- Formula: low health (10) = high failure prob (0.95), high health (100) = low failure prob (0.01)
    -- Linear relationship: failure_prob = 0.01 + (100 - health_score) / 90 * 0.94
    -- This ensures health=10 gives 0.95 and health=100 gives 0.01
    ROUND(LEAST(0.95, GREATEST(0.01, 0.01 + (100 - health_score) / 90.0 * 0.94)), 2) AS failure_probability,
    
    -- Remaining useful life (correlated with health score) - range 10 to 500 days
    -- Lower health = lower RUL, higher health = higher RUL
    -- Formula ensures RUL scales with health: health=10 gives ~55 days, health=100 gives ~500 days
    -- RUL decreases based on days since decay started
    GREATEST(10, ROUND((health_score / 100.0 * 500) - (days_since_decay_start * 0.5) - UNIFORM(0, 20, RANDOM()), 0))::INTEGER AS rul_days,
    
    -- Mark as anomalous based on realistic thresholds
    CASE 
        WHEN health_score < 50 THEN TRUE  -- Health below 50 is concerning (failure prob > 0.48)
        WHEN asset_id IN (1,2,4,5,7,8,11,14,17) AND vibration_mm_s > 1.5 THEN TRUE  -- High vibration
        WHEN asset_id IN (1,4,7) AND temperature_c > 85 THEN TRUE  -- Overheating pumps
        ELSE FALSE
    END AS is_anomalous
FROM sensor_data;

-- Maintenance Log (Dynamic generation from Nov 1, 2024 to current date)
-- Each asset gets maintenance events based on realistic frequencies:
-- - Preventive Maintenance (PM): Every 30 days
-- - Inspections: Every 15 days
-- - Predictive Maintenance: Every 20 days
-- - Emergency repairs: Randomly, 5% chance
INSERT INTO FCT_MAINTENANCE_LOG (ASSET_ID,
PROCESS_ID,
WO_TYPE_ID,
ACTION_DATE_SK,
COMPLETED_DATE,
DOWNTIME_HOURS,
PARTS_COST,
LABOR_COST,
FAILURE_FLAG,
TECHNICIAN_ID,
FAILURE_CODE_ID,
TECHNICIAN_NOTES)
WITH date_params AS (
    SELECT 
        '2024-11-01'::DATE AS start_date,
        CURRENT_DATE() AS end_date
),
daily_asset_base AS (
    SELECT 
        a.asset_id,
        a.process_id,
        DATEADD(DAY, d.day_seq, dp.start_date) AS maint_date,
        d.day_seq,
        TO_NUMBER(TO_CHAR(DATEADD(DAY, d.day_seq, dp.start_date), 'YYYYMMDD')) AS date_sk
    FROM date_params dp
    CROSS JOIN (
        SELECT 
            da.ASSET_ID,
            da.PROCESS_ID
        FROM SF_SOLUTIONS.MPM_SILVER.DIM_ASSET da
        WHERE da.IS_CURRENT = TRUE
    ) a
    CROSS JOIN (
        SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS day_seq
        FROM TABLE(GENERATOR(ROWCOUNT => 500))
    ) d
    WHERE DATEADD(DAY, d.day_seq, dp.start_date) <= dp.end_date
),
maintenance_events AS (
    SELECT 
        asset_id,
        process_id,
        maint_date,
        date_sk,
        day_seq,
        -- Determine work order type based on patterns
        CASE 
            WHEN MOD(day_seq, 30) = MOD(asset_id, 30) THEN 3  -- Preventive Maintenance every 30 days
            WHEN MOD(day_seq, 15) = MOD(asset_id, 15) THEN 4  -- Inspection every 15 days
            WHEN MOD(day_seq, 20) = MOD((asset_id * 2), 20) THEN 2  -- Predictive Maintenance every 20 days
            WHEN UNIFORM(0, 100, RANDOM()) < 2 THEN 1  -- 2% chance of emergency repair
            ELSE NULL
        END AS wo_type_id,
        -- Assign technician (rotate through available technicians)
        MOD((asset_id + day_seq), 10) + 1 AS technician_id
    FROM daily_asset_base
),
maint_with_details AS (
    SELECT 
        me.*,
        -- Downtime hours based on work order type
        CASE 
            WHEN wo_type_id = 1 THEN ROUND(4 + UNIFORM(0, 4, RANDOM()), 1)  -- Emergency: 4-8 hours
            WHEN wo_type_id = 2 THEN ROUND(1 + UNIFORM(0, 2, RANDOM()), 1)  -- Predictive: 1-3 hours
            WHEN wo_type_id = 3 THEN ROUND(2 + UNIFORM(0, 3, RANDOM()), 1)  -- Preventive: 2-5 hours
            WHEN wo_type_id = 4 THEN ROUND(0.5 + UNIFORM(0, 1, RANDOM()), 1)  -- Inspection: 0.5-1.5 hours
            ELSE 0
        END AS downtime_hours,
        -- Parts cost
        CASE 
            WHEN wo_type_id = 1 THEN ROUND(300 + UNIFORM(0, 500, RANDOM()), 2)  -- Emergency: $300-800
            WHEN wo_type_id = 2 THEN ROUND(50 + UNIFORM(0, 150, RANDOM()), 2)   -- Predictive: $50-200
            WHEN wo_type_id = 3 THEN ROUND(100 + UNIFORM(0, 200, RANDOM()), 2)  -- Preventive: $100-300
            WHEN wo_type_id = 4 THEN ROUND(0 + UNIFORM(0, 50, RANDOM()), 2)     -- Inspection: $0-50
            ELSE 0
        END AS parts_cost,
        -- Labor cost (based on downtime * hourly rate $150-200/hr)
        CASE 
            WHEN wo_type_id = 1 THEN ROUND((4 + UNIFORM(0, 4, RANDOM())) * 180, 2)
            WHEN wo_type_id = 2 THEN ROUND((1 + UNIFORM(0, 2, RANDOM())) * 160, 2)
            WHEN wo_type_id = 3 THEN ROUND((2 + UNIFORM(0, 3, RANDOM())) * 150, 2)
            WHEN wo_type_id = 4 THEN ROUND((0.5 + UNIFORM(0, 1, RANDOM())) * 140, 2)
            ELSE 0
        END AS labor_cost,
        -- Failure flag and failure code (only for emergency repairs)
        CASE WHEN wo_type_id = 1 THEN TRUE ELSE FALSE END AS failure_flag,
        CASE 
            WHEN wo_type_id = 1 THEN MOD((asset_id + day_seq), 12) + 1  -- Rotate through 12 failure codes
            ELSE NULL 
        END AS failure_code_id,
        -- Notes based on work order type and asset
        CASE 
            WHEN wo_type_id = 1 THEN 'Emergency repair - ' || 
                CASE MOD(asset_id, 6)
                    WHEN 0 THEN 'bearing failure requiring immediate replacement'
                    WHEN 1 THEN 'unexpected shutdown due to overheating'
                    WHEN 2 THEN 'seal failure causing fluid leak'
                    WHEN 3 THEN 'electrical fault requiring repair'
                    WHEN 4 THEN 'mechanical failure requiring parts replacement'
                    ELSE 'critical component failure addressed'
                END
            WHEN wo_type_id = 2 THEN 'Predictive maintenance - ' || 
                CASE MOD(asset_id, 4)
                    WHEN 0 THEN 'proactive component replacement based on sensor data'
                    WHEN 1 THEN 'condition-based maintenance preventing failure'
                    WHEN 2 THEN 'vibration analysis indicated need for adjustment'
                    ELSE 'temperature trends suggested preventive action'
                END
            WHEN wo_type_id = 3 THEN 'Preventive maintenance - ' || 
                CASE MOD(asset_id, 4)
                    WHEN 0 THEN 'scheduled lubrication and inspection completed'
                    WHEN 1 THEN 'routine service and parts replacement per schedule'
                    WHEN 2 THEN 'planned maintenance activities completed'
                    ELSE 'standard PM tasks performed successfully'
                END
            WHEN wo_type_id = 4 THEN 'Routine inspection - ' || 
                CASE MOD(asset_id, 3)
                    WHEN 0 THEN 'visual inspection and sensor verification'
                    WHEN 1 THEN 'performance monitoring and calibration check'
                    ELSE 'standard inspection completed, no issues found'
                END
            ELSE 'Maintenance activity completed'
        END AS technician_notes
    FROM maintenance_events me
    WHERE wo_type_id IS NOT NULL
)
SELECT 
    asset_id,
    process_id,
    wo_type_id,
    date_sk,
    maint_date AS completed_date,
    downtime_hours,
    parts_cost,
    labor_cost,
    failure_flag,
    technician_id,
    failure_code_id,
    technician_notes
FROM maint_with_details;

-- Production Log (Daily production data for all assets from Nov 1, 2024 to current date)
-- Generates daily production metrics with realistic variations and maintenance impacts
INSERT INTO FCT_PRODUCTION_LOG (ASSET_ID,
PROCESS_ID,
DATE_SK,
PRODUCTION_DATE,
PLANNED_RUNTIME_HOURS,
ACTUAL_RUNTIME_HOURS,
UNITS_PRODUCED,
UNITS_SCRAPPED)
WITH date_params AS (
    SELECT 
        '2024-11-01'::DATE AS start_date,
        CURRENT_DATE() AS end_date
),
daily_production_base AS (
    SELECT 
        a.asset_id,
        a.process_id,
        DATEADD(DAY, d.day_seq, dp.start_date) AS production_date,
        TO_NUMBER(TO_CHAR(DATEADD(DAY, d.day_seq, dp.start_date), 'YYYYMMDD')) AS date_sk,
        d.day_seq,
        DAYOFWEEK(DATEADD(DAY, d.day_seq, dp.start_date)) AS day_of_week
    FROM date_params dp
    CROSS JOIN (
        SELECT 
            da.ASSET_ID,
            da.PROCESS_ID
        FROM SF_SOLUTIONS.MPM_SILVER.DIM_ASSET da
        WHERE da.IS_CURRENT = TRUE
    ) a
    CROSS JOIN (
        SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS day_seq
        FROM TABLE(GENERATOR(ROWCOUNT => 500))
    ) d
    WHERE DATEADD(DAY, d.day_seq, dp.start_date) <= dp.end_date
),
production_with_maint AS (
    SELECT 
        pb.asset_id,
        pb.process_id,
        pb.production_date,
        pb.date_sk,
        pb.day_seq,
        pb.day_of_week,
        -- Check if there was maintenance on this day
        COALESCE(ml.downtime_hours, 0) AS maint_downtime,
        COALESCE(ml.failure_flag, FALSE) AS had_failure
    FROM daily_production_base pb
    LEFT JOIN SF_SOLUTIONS.MPM_SILVER.FCT_MAINTENANCE_LOG ml 
        ON pb.asset_id = ml.asset_id 
        AND pb.date_sk = ml.action_date_sk
)
SELECT 
    asset_id,
    process_id,
    date_sk,
    production_date,
    -- Planned runtime varies by asset class
    CASE 
        WHEN asset_id IN (1,2,3,4,5,6,7,8,9) THEN 24.0  -- Davidson plant runs 24/7
        WHEN asset_id IN (10,11,12,13,14,15) THEN 20.0  -- Charlotte Assembly line 1&2
        ELSE 18.0  -- Charlotte Assembly line 3
    END AS planned_runtime_hours,
    -- Actual runtime (reduced by maintenance and random variations)
    CASE 
        WHEN asset_id IN (1,2,3,4,5,6,7,8,9) THEN 
            GREATEST(0, ROUND(24.0 - maint_downtime - UNIFORM(0, 1.5, RANDOM()), 1))
        WHEN asset_id IN (10,11,12,13,14,15) THEN 
            GREATEST(0, ROUND(20.0 - maint_downtime - UNIFORM(0, 1.2, RANDOM()), 1))
        ELSE 
            GREATEST(0, ROUND(18.0 - maint_downtime - UNIFORM(0, 1.0, RANDOM()), 1))
    END AS actual_runtime_hours,
    -- Units produced (based on asset capacity and actual runtime)
    CASE 
        WHEN asset_id IN (1,2,3,4,5,6,7,8,9) THEN 
            ROUND((24.0 - maint_downtime - UNIFORM(0, 1.5, RANDOM())) * 
                CASE asset_id
                    WHEN 1 THEN 50  -- Primary Coolant Pump: 50 units/hr
                    WHEN 2 THEN 100  -- Conveyor Drive Motor: 100 units/hr
                    WHEN 3 THEN 48  -- Air Compressor: 48 units/hr
                    WHEN 4 THEN 49  -- Hydraulic Pump: 49 units/hr
                    WHEN 5 THEN 50  -- Main Drive Motor: 50 units/hr
                    WHEN 6 THEN 50  -- Cooling Fan: 50 units/hr
                    WHEN 7 THEN 48  -- Process Circulation Pump: 48 units/hr
                    WHEN 8 THEN 49  -- Conveyor Motor Assembly: 49 units/hr
                    ELSE 49  -- Control Valve System: 49 units/hr
                END, 0)::INTEGER
        WHEN asset_id IN (10,11,12,13,14,15) THEN 
            ROUND((20.0 - maint_downtime - UNIFORM(0, 1.2, RANDOM())) * 
                CASE asset_id
                    WHEN 10 THEN 50  -- Assembly Robot: 50 units/hr
                    WHEN 11 THEN 49  -- Conveyor Drive System: 49 units/hr
                    WHEN 12 THEN 48  -- Pneumatic Press: 48 units/hr
                    WHEN 13 THEN 50  -- Welding Robot: 50 units/hr
                    WHEN 14 THEN 49  -- Material Handling Motor: 49 units/hr
                    ELSE 46  -- Heat Treatment Furnace: 46 units/hr (slower process)
                END, 0)::INTEGER
        ELSE 
            ROUND((18.0 - maint_downtime - UNIFORM(0, 1.0, RANDOM())) * 
                CASE asset_id
                    WHEN 16 THEN 50  -- Packaging Robot: 50 units/hr
                    WHEN 17 THEN 49  -- Sorting System Motor: 49 units/hr
                    ELSE 50  -- Quality Control Scanner: 50 units/hr
                END, 0)::INTEGER
    END AS units_produced,
    -- Units scrapped (higher if there was a failure, normal quality issues otherwise)
    CASE 
        WHEN had_failure THEN ROUND(UNIFORM(20, 50, RANDOM()), 0)::INTEGER
        ELSE ROUND(UNIFORM(3, 15, RANDOM()), 0)::INTEGER
    END AS units_scrapped
FROM production_with_maint;

-- Maintenance Parts Used (Links maintenance events to materials consumed)
-- Generates realistic parts usage for each maintenance event based on work order type
INSERT INTO FCT_MAINTENANCE_PARTS_USED (LOG_ID, MATERIAL_ID, QUANTITY_USED, TOTAL_COST)
WITH maintenance_logs_with_seq AS (
    SELECT 
        ml.LOG_ID,
        ml.WO_TYPE_ID,
        ml.ASSET_ID,
        ml.PARTS_COST,
        ROW_NUMBER() OVER (ORDER BY ml.LOG_ID) AS log_seq
    FROM SF_SOLUTIONS.MPM_SILVER.FCT_MAINTENANCE_LOG ml
),
parts_per_maint AS (
    SELECT 
        ml.LOG_ID,
        ml.WO_TYPE_ID,
        ml.ASSET_ID,
        ml.PARTS_COST,
        -- Determine number of parts used based on work order type
        CASE 
            WHEN ml.WO_TYPE_ID = 1 THEN UNIFORM(2, 5, RANDOM())  -- Emergency: 2-5 parts
            WHEN ml.WO_TYPE_ID = 2 THEN UNIFORM(1, 3, RANDOM())  -- Predictive: 1-3 parts
            WHEN ml.WO_TYPE_ID = 3 THEN UNIFORM(2, 4, RANDOM())  -- Preventive: 2-4 parts
            WHEN ml.WO_TYPE_ID = 4 THEN UNIFORM(0, 2, RANDOM())  -- Inspection: 0-2 parts
            ELSE 1
        END AS num_parts
    FROM maintenance_logs_with_seq ml
),
parts_expanded AS (
    SELECT 
        pm.LOG_ID,
        pm.WO_TYPE_ID,
        pm.ASSET_ID,
        pm.PARTS_COST,
        p.part_seq
    FROM parts_per_maint pm
    CROSS JOIN (
        SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS part_seq
        FROM TABLE(GENERATOR(ROWCOUNT => 10))
    ) p
    WHERE p.part_seq <= pm.num_parts
)
SELECT 
    pe.LOG_ID,
    -- Select material based on work order type and asset
    CASE 
        WHEN pe.WO_TYPE_ID = 1 THEN  -- Emergency repairs use critical parts
            CASE MOD((pe.ASSET_ID + pe.part_seq), 8)
                WHEN 0 THEN 2   -- Heavy duty bearing
                WHEN 1 THEN 4   -- Mechanical seal
                WHEN 2 THEN 10  -- Servo motor
                WHEN 3 THEN 16  -- Pump impeller
                WHEN 4 THEN 14  -- Coupling
                WHEN 5 THEN 13  -- Solenoid valve
                WHEN 6 THEN 12  -- Vibration sensor
                ELSE 11         -- Temperature sensor
            END
        WHEN pe.WO_TYPE_ID = 2 THEN  -- Predictive maintenance
            CASE MOD((pe.ASSET_ID + pe.part_seq), 6)
                WHEN 0 THEN 1   -- Standard bearing
                WHEN 1 THEN 3   -- Oil seal
                WHEN 2 THEN 5   -- Belt
                WHEN 3 THEN 14  -- Coupling
                WHEN 4 THEN 11  -- Temperature sensor
                ELSE 8          -- Synthetic oil
            END
        WHEN pe.WO_TYPE_ID = 3 THEN  -- Preventive maintenance
            CASE MOD((pe.ASSET_ID + pe.part_seq), 7)
                WHEN 0 THEN 6   -- Hydraulic filter
                WHEN 1 THEN 7   -- Air filter
                WHEN 2 THEN 8   -- Gear oil
                WHEN 3 THEN 9   -- Hydraulic oil
                WHEN 4 THEN 20  -- Grease
                WHEN 5 THEN 15  -- Gasket
                ELSE 3          -- Oil seal
            END
        ELSE  -- Inspections use minimal parts
            CASE MOD((pe.ASSET_ID + pe.part_seq), 4)
                WHEN 0 THEN 19  -- Fuse
                WHEN 1 THEN 20  -- Grease
                WHEN 2 THEN 15  -- Gasket
                ELSE 8          -- Oil
            END
    END AS material_id,
    -- Quantity varies by part type
    CASE 
        WHEN pe.WO_TYPE_ID = 1 THEN ROUND(UNIFORM(1, 3, RANDOM()), 1)  -- Emergency: 1-3 units
        WHEN pe.WO_TYPE_ID = 2 THEN ROUND(UNIFORM(1, 2, RANDOM()), 1)  -- Predictive: 1-2 units
        WHEN pe.WO_TYPE_ID = 3 THEN ROUND(UNIFORM(1, 2, RANDOM()), 1)  -- Preventive: 1-2 units
        ELSE 1  -- Inspection: 1 unit
    END AS quantity_used,
    -- Calculate cost based on material and quantity
    ROUND(
        CASE 
            WHEN pe.WO_TYPE_ID = 1 THEN UNIFORM(1, 3, RANDOM())
            WHEN pe.WO_TYPE_ID = 2 THEN UNIFORM(1, 2, RANDOM())
            WHEN pe.WO_TYPE_ID = 3 THEN UNIFORM(1, 2, RANDOM())
            ELSE 1
        END * 
        -- Approximate cost per material (simplified for dynamic generation)
        CASE MOD((pe.ASSET_ID + pe.part_seq), 20) + 1
            WHEN 1 THEN 25.50
            WHEN 2 THEN 85.00
            WHEN 3 THEN 12.75
            WHEN 4 THEN 145.00
            WHEN 5 THEN 18.50
            WHEN 6 THEN 42.00
            WHEN 7 THEN 38.50
            WHEN 8 THEN 55.00
            WHEN 9 THEN 95.00
            WHEN 10 THEN 850.00
            WHEN 11 THEN 75.00
            WHEN 12 THEN 425.00
            WHEN 13 THEN 165.00
            WHEN 14 THEN 95.00
            WHEN 15 THEN 22.00
            WHEN 16 THEN 320.00
            WHEN 17 THEN 85.00
            WHEN 18 THEN 45.00
            WHEN 19 THEN 8.50
            ELSE 15.75
        END
    , 2) AS total_cost
FROM parts_expanded pe;

-- Insert into GOLD Layer
USE SCHEMA SF_SOLUTIONS.MPM_GOLD;

-- AGG_ASSET_HOURLY_HEALTH: Aggregated hourly health metrics from telemetry data
INSERT INTO AGG_ASSET_HOURLY_HEALTH (HOUR_TIMESTAMP,
ASSET_ID,
AVG_TEMPERATURE_C,
MAX_VIBRATION_MM_S,
STDDEV_PRESSURE_PSI,
LATEST_HEALTH_SCORE,
AVG_FAILURE_PROBABILITY,
MIN_RUL_DAYS)
SELECT 
    DATE_TRUNC('HOUR', t.RECORDED_AT) AS hour_timestamp,
    t.ASSET_ID,
    ROUND(AVG(t.TEMPERATURE_C), 2) AS avg_temperature_c,
    ROUND(MAX(t.VIBRATION_MM_S), 2) AS max_vibration_mm_s,
    ROUND(STDDEV(t.PRESSURE_PSI), 2) AS stddev_pressure_psi,
    -- Get the latest health score within the hour
    MAX(t.HEALTH_SCORE) AS latest_health_score,
    ROUND(AVG(t.FAILURE_PROBABILITY), 2) AS avg_failure_probability,
    MIN(t.RUL_DAYS) AS min_rul_days
FROM SF_SOLUTIONS.MPM_SILVER.FCT_ASSET_TELEMETRY t
WHERE t.RECORDED_AT >= '2024-11-01 00:00:00'::TIMESTAMP_NTZ
GROUP BY 
    DATE_TRUNC('HOUR', t.RECORDED_AT),
    t.ASSET_ID
ORDER BY hour_timestamp, asset_id;

-- ML_FEATURE_STORE: Daily feature store for machine learning models
INSERT INTO ML_FEATURE_STORE (OBSERVATION_DATE_SK,
ASSET_ID,
AVG_TEMP_LAST_24H,
VIBRATION_STDDEV_7D,
PRESSURE_TREND_7D,
CYCLES_SINCE_LAST_PM,
DAYS_SINCE_LAST_FAILURE,
OEM_FAILURE_RATE_EST,
DOWNTIME_IMPACT_RISK,
FAILED_IN_NEXT_7_DAYS)
WITH daily_observations AS (
    SELECT DISTINCT
        t.DATE_SK AS observation_date_sk,
        t.ASSET_ID,
        t.RECORDED_AT::DATE AS observation_date
    FROM SF_SOLUTIONS.MPM_SILVER.FCT_ASSET_TELEMETRY t
    WHERE t.RECORDED_AT >= '2024-11-01'::DATE
),
temp_features AS ( -- noqa: ST03
    SELECT 
        do.observation_date_sk,
        do.ASSET_ID,
        ROUND(AVG(t.TEMPERATURE_C), 2) as avg_temp_last_24h
    FROM daily_observations do
    JOIN SF_SOLUTIONS.MPM_SILVER.FCT_ASSET_TELEMETRY t 
        ON do.ASSET_ID = t.ASSET_ID
        AND t.RECORDED_AT >= DATEADD(HOUR, -24, do.observation_date::TIMESTAMP_NTZ)
        AND t.RECORDED_AT < DATEADD(DAY, 1, do.observation_date::TIMESTAMP_NTZ)
    GROUP BY do.observation_date_sk, do.ASSET_ID
),
vibration_features AS ( -- noqa: ST03
    SELECT 
        do.observation_date_sk,
        do.ASSET_ID,
        ROUND(STDDEV(t.VIBRATION_MM_S), 2) as vibration_stddev_7d
    FROM daily_observations do
    JOIN SF_SOLUTIONS.MPM_SILVER.FCT_ASSET_TELEMETRY t 
        ON do.ASSET_ID = t.ASSET_ID
        AND t.RECORDED_AT >= DATEADD(DAY, -7, do.observation_date::TIMESTAMP_NTZ)
        AND t.RECORDED_AT < DATEADD(DAY, 1, do.observation_date::TIMESTAMP_NTZ)
    GROUP BY do.observation_date_sk, do.ASSET_ID
),
pressure_features AS ( -- noqa: ST03
    SELECT 
        do.observation_date_sk,
        do.ASSET_ID,
        ROUND(
            (MAX(t.PRESSURE_PSI) - MIN(t.PRESSURE_PSI)) / NULLIF(COUNT(*), 0), 
        2) as pressure_trend_7d
    FROM daily_observations do
    JOIN SF_SOLUTIONS.MPM_SILVER.FCT_ASSET_TELEMETRY t 
        ON do.ASSET_ID = t.ASSET_ID
        AND t.RECORDED_AT >= DATEADD(DAY, -7, do.observation_date::TIMESTAMP_NTZ)
        AND t.RECORDED_AT < DATEADD(DAY, 1, do.observation_date::TIMESTAMP_NTZ)
        AND t.PRESSURE_PSI IS NOT NULL
    GROUP BY do.observation_date_sk, do.ASSET_ID
),
maintenance_features AS ( -- noqa: ST03
    SELECT 
        do.observation_date_sk,
        do.ASSET_ID,
        do.observation_date,
        -- Days since last preventive maintenance
        COALESCE(DATEDIFF(DAY, 
            MAX(CASE WHEN ml.WO_TYPE_ID = 3 THEN ml.COMPLETED_DATE END), 
            do.observation_date), 
        999) as days_since_last_pm,
        -- Days since last failure
        COALESCE(DATEDIFF(DAY, 
            MAX(CASE WHEN ml.FAILURE_FLAG = TRUE THEN ml.COMPLETED_DATE END), 
            do.observation_date), 
        999) as days_since_last_failure
    FROM daily_observations do
    LEFT JOIN SF_SOLUTIONS.MPM_SILVER.FCT_MAINTENANCE_LOG ml 
        ON do.ASSET_ID = ml.ASSET_ID
        AND ml.COMPLETED_DATE < do.observation_date
    GROUP BY do.observation_date_sk, do.ASSET_ID, do.observation_date
),
future_failures AS ( -- noqa: ST03
    SELECT 
        do.observation_date_sk,
        do.ASSET_ID,
        -- Check if there was a failure in the next 7 days
        MAX(CASE 
            WHEN ml.FAILURE_FLAG = TRUE 
                AND ml.COMPLETED_DATE > do.observation_date 
                AND ml.COMPLETED_DATE <= DATEADD(DAY, 7, do.observation_date)
            THEN TRUE 
            ELSE FALSE 
        END) as failed_in_next_7_days
    FROM daily_observations do
    LEFT JOIN SF_SOLUTIONS.MPM_SILVER.FCT_MAINTENANCE_LOG ml 
        ON do.ASSET_ID = ml.ASSET_ID
    GROUP BY do.observation_date_sk, do.ASSET_ID
)
SELECT 
    do.observation_date_sk,
    do.ASSET_ID,
    tf.avg_temp_last_24h,
    vf.vibration_stddev_7d,
    pf.pressure_trend_7d,
    -- Cycles approximation (hours * 60 for cycles per hour estimate)
    GREATEST(0, mf.days_since_last_pm * 24 * 50) as cycles_since_last_pm,
    mf.days_since_last_failure,
    -- OEM failure rate estimate (based on asset age and type)
    ROUND(0.08 + UNIFORM(0, 0.12, RANDOM()), 2) as oem_failure_rate_est,
    -- Downtime impact risk (health score * downtime impact per hour)
    ROUND(
        (100 - COALESCE(h.latest_health_score, 95)) * a.DOWNTIME_IMPACT_PER_HOUR,
    2) as downtime_impact_risk,
    ff.failed_in_next_7_days
FROM daily_observations do
LEFT JOIN temp_features tf ON do.observation_date_sk = tf.observation_date_sk AND do.ASSET_ID = tf.ASSET_ID
LEFT JOIN vibration_features vf ON do.observation_date_sk = vf.observation_date_sk AND do.ASSET_ID = vf.ASSET_ID
LEFT JOIN pressure_features pf ON do.observation_date_sk = pf.observation_date_sk AND do.ASSET_ID = pf.ASSET_ID
LEFT JOIN maintenance_features mf ON do.observation_date_sk = mf.observation_date_sk AND do.ASSET_ID = mf.ASSET_ID
LEFT JOIN future_failures ff ON do.observation_date_sk = ff.observation_date_sk AND do.ASSET_ID = ff.ASSET_ID
LEFT JOIN SF_SOLUTIONS.MPM_SILVER.DIM_ASSET a ON do.ASSET_ID = a.ASSET_ID
LEFT JOIN (
    SELECT 
        ASSET_ID,
        DATE_SK,
        MAX(HEALTH_SCORE) as latest_health_score
    FROM SF_SOLUTIONS.MPM_SILVER.FCT_ASSET_TELEMETRY
    GROUP BY ASSET_ID, DATE_SK
) h ON do.ASSET_ID = h.ASSET_ID AND do.observation_date_sk = h.DATE_SK
WHERE do.observation_date >= '2024-11-01'::DATE
ORDER BY do.observation_date_sk, do.ASSET_ID;

-- AGG_DAILY_OEE: Daily OEE calculations for each asset
INSERT INTO AGG_DAILY_OEE (
    PRODUCTION_DATE, DATE_SK, ASSET_ID, PROCESS_ID,
    AVAILABILITY_PERCENT, PERFORMANCE_PERCENT, QUALITY_PERCENT, OEE_PERCENT,
    PLANNED_RUNTIME_HOURS, ACTUAL_RUNTIME_HOURS, UNITS_PRODUCED, UNITS_SCRAPPED, GOOD_UNITS
)
SELECT 
    pl.PRODUCTION_DATE,
    pl.DATE_SK,
    pl.ASSET_ID,
    pl.PROCESS_ID,
    -- Availability: (Actual Runtime / Planned Runtime) × 100
    ROUND(CASE 
        WHEN pl.PLANNED_RUNTIME_HOURS > 0 
        THEN (pl.ACTUAL_RUNTIME_HOURS / pl.PLANNED_RUNTIME_HOURS) * 100 
        ELSE 0 
    END, 2) AS availability_percent,
    -- Performance: Assume 80-98% of theoretical max (adding realistic variation)
    ROUND(UNIFORM(80, 98, RANDOM()), 2) AS performance_percent,
    -- Quality: (Good Units / Total Units) × 100
    ROUND(CASE 
        WHEN pl.UNITS_PRODUCED > 0 
        THEN ((pl.UNITS_PRODUCED - pl.UNITS_SCRAPPED) / pl.UNITS_PRODUCED) * 100 
        ELSE 0 
    END, 2) AS quality_percent,
    -- OEE: Availability × Performance × Quality (as decimal multiplication, then × 100)
    ROUND(
        CASE 
            WHEN pl.PLANNED_RUNTIME_HOURS > 0 AND pl.UNITS_PRODUCED > 0
            THEN (pl.ACTUAL_RUNTIME_HOURS / pl.PLANNED_RUNTIME_HOURS) * 
                 (UNIFORM(80, 98, RANDOM()) / 100) * 
                 ((pl.UNITS_PRODUCED - pl.UNITS_SCRAPPED) / pl.UNITS_PRODUCED) * 100
            ELSE 0 
        END, 2
    ) AS oee_percent,
    pl.PLANNED_RUNTIME_HOURS,
    pl.ACTUAL_RUNTIME_HOURS,
    pl.UNITS_PRODUCED,
    pl.UNITS_SCRAPPED,
    pl.UNITS_PRODUCED - pl.UNITS_SCRAPPED AS good_units
FROM SF_SOLUTIONS.MPM_SILVER.FCT_PRODUCTION_LOG pl
WHERE pl.PRODUCTION_DATE >= '2024-11-01'::DATE
ORDER BY pl.PRODUCTION_DATE, pl.ASSET_ID;

-- AGG_MONTHLY_TRENDS: Monthly aggregations for OEE vs Maintenance Cost trending
INSERT INTO AGG_MONTHLY_TRENDS (
    YEAR_MONTH, YEAR, MONTH, PLANT_ID, LINE_ID, PROCESS_ID,
    AVG_OEE_PERCENT, MIN_OEE_PERCENT, MAX_OEE_PERCENT,
    AVG_AVAILABILITY_PERCENT, AVG_PERFORMANCE_PERCENT, AVG_QUALITY_PERCENT,
    TOTAL_MAINTENANCE_COST, TOTAL_PARTS_COST, TOTAL_LABOR_COST,
    TOTAL_DOWNTIME_HOURS, PREVENTIVE_WO_COUNT, PREDICTIVE_WO_COUNT, EMERGENCY_WO_COUNT, FAILURE_COUNT,
    TOTAL_UNITS_PRODUCED, TOTAL_UNITS_SCRAPPED, ASSET_COUNT
)
WITH monthly_oee AS (
    SELECT 
        TO_CHAR(oee.PRODUCTION_DATE, 'YYYY-MM') AS year_month,
        YEAR(oee.PRODUCTION_DATE) AS year,
        MONTH(oee.PRODUCTION_DATE) AS month,
        l.PLANT_ID,
        p.LINE_ID,
        oee.PROCESS_ID,
        AVG(oee.OEE_PERCENT) AS avg_oee_percent,
        MIN(oee.OEE_PERCENT) AS min_oee_percent,
        MAX(oee.OEE_PERCENT) AS max_oee_percent,
        AVG(oee.AVAILABILITY_PERCENT) AS avg_availability_percent,
        AVG(oee.PERFORMANCE_PERCENT) AS avg_performance_percent,
        AVG(oee.QUALITY_PERCENT) AS avg_quality_percent,
        SUM(oee.UNITS_PRODUCED) AS total_units_produced,
        SUM(oee.UNITS_SCRAPPED) AS total_units_scrapped,
        COUNT(DISTINCT oee.ASSET_ID) AS asset_count
    FROM SF_SOLUTIONS.MPM_GOLD.AGG_DAILY_OEE oee
    JOIN SF_SOLUTIONS.MPM_SILVER.DIM_ASSET a ON oee.ASSET_ID = a.ASSET_ID AND a.IS_CURRENT = TRUE
    JOIN SF_SOLUTIONS.MPM_SILVER.DIM_PROCESS p ON oee.PROCESS_ID = p.PROCESS_ID
    JOIN SF_SOLUTIONS.MPM_SILVER.DIM_LINE l ON p.LINE_ID = l.LINE_ID
    WHERE oee.PRODUCTION_DATE >= '2024-11-01'::DATE
    GROUP BY 
        TO_CHAR(oee.PRODUCTION_DATE, 'YYYY-MM'),
        YEAR(oee.PRODUCTION_DATE),
        MONTH(oee.PRODUCTION_DATE),
        l.PLANT_ID,
        p.LINE_ID,
        oee.PROCESS_ID
),
monthly_maintenance AS (
    SELECT 
        TO_CHAR(ml.COMPLETED_DATE, 'YYYY-MM') AS year_month,
        l.PLANT_ID,
        p.LINE_ID,
        ml.PROCESS_ID,
        SUM(ml.PARTS_COST + ml.LABOR_COST) AS total_maintenance_cost,
        SUM(ml.PARTS_COST) AS total_parts_cost,
        SUM(ml.LABOR_COST) AS total_labor_cost,
        SUM(ml.DOWNTIME_HOURS) AS total_downtime_hours,
        SUM(CASE WHEN ml.WO_TYPE_ID = 3 THEN 1 ELSE 0 END) AS preventive_wo_count,
        SUM(CASE WHEN ml.WO_TYPE_ID = 2 THEN 1 ELSE 0 END) AS predictive_wo_count,
        SUM(CASE WHEN ml.WO_TYPE_ID = 1 THEN 1 ELSE 0 END) AS emergency_wo_count,
        SUM(CASE WHEN ml.FAILURE_FLAG = TRUE THEN 1 ELSE 0 END) AS failure_count
    FROM SF_SOLUTIONS.MPM_SILVER.FCT_MAINTENANCE_LOG ml
    JOIN SF_SOLUTIONS.MPM_SILVER.DIM_ASSET a ON ml.ASSET_ID = a.ASSET_ID AND a.IS_CURRENT = TRUE
    JOIN SF_SOLUTIONS.MPM_SILVER.DIM_PROCESS p ON ml.PROCESS_ID = p.PROCESS_ID
    JOIN SF_SOLUTIONS.MPM_SILVER.DIM_LINE l ON p.LINE_ID = l.LINE_ID
    WHERE ml.COMPLETED_DATE >= '2024-11-01'::DATE
    GROUP BY 
        TO_CHAR(ml.COMPLETED_DATE, 'YYYY-MM'),
        l.PLANT_ID,
        p.LINE_ID,
        ml.PROCESS_ID
)
SELECT 
    oee.year_month,
    oee.year,
    oee.month,
    oee.plant_id,
    oee.line_id,
    oee.process_id,
    ROUND(oee.avg_oee_percent, 2) AS avg_oee_percent,
    ROUND(oee.min_oee_percent, 2) AS min_oee_percent,
    ROUND(oee.max_oee_percent, 2) AS max_oee_percent,
    ROUND(oee.avg_availability_percent, 2) AS avg_availability_percent,
    ROUND(oee.avg_performance_percent, 2) AS avg_performance_percent,
    ROUND(oee.avg_quality_percent, 2) AS avg_quality_percent,
    COALESCE(maint.total_maintenance_cost, 0) AS total_maintenance_cost,
    COALESCE(maint.total_parts_cost, 0) AS total_parts_cost,
    COALESCE(maint.total_labor_cost, 0) AS total_labor_cost,
    COALESCE(maint.total_downtime_hours, 0) AS total_downtime_hours,
    COALESCE(maint.preventive_wo_count, 0) AS preventive_wo_count,
    COALESCE(maint.predictive_wo_count, 0) AS predictive_wo_count,
    COALESCE(maint.emergency_wo_count, 0) AS emergency_wo_count,
    COALESCE(maint.failure_count, 0) AS failure_count,
    oee.total_units_produced,
    oee.total_units_scrapped,
    oee.asset_count
FROM monthly_oee oee
LEFT JOIN monthly_maintenance maint 
    ON oee.year_month = maint.year_month 
    AND oee.plant_id = maint.plant_id 
    AND oee.line_id = maint.line_id 
    AND oee.process_id = maint.process_id
ORDER BY oee.year_month, oee.plant_id, oee.line_id;
