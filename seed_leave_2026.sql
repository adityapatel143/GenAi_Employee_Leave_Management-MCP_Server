-- ============================================================
-- Seed Leave Balances for Year 2026
-- Run this after the main schema is set up
-- ============================================================

-- Seed leave balances for all employees for the year 2026
DO $$
DECLARE
    annual_id  INT;
    sick_id    INT;
    casual_id  INT;
    maternity_id INT;
    paternity_id INT;
    unpaid_id INT;
BEGIN
    -- Get leave type IDs
    SELECT id INTO annual_id FROM leave_types WHERE name = 'Annual';
    SELECT id INTO sick_id   FROM leave_types WHERE name = 'Sick';
    SELECT id INTO casual_id FROM leave_types WHERE name = 'Casual';
    SELECT id INTO maternity_id FROM leave_types WHERE name = 'Maternity';
    SELECT id INTO paternity_id FROM leave_types WHERE name = 'Paternity';
    SELECT id INTO unpaid_id FROM leave_types WHERE name = 'Unpaid';
    
    -- ============================================================
    -- Insert base leave balances for ALL active employees for 2026
    -- ============================================================
    
    -- Annual Leave (18 days for everyone)
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT e.id, annual_id, 2026, 18, 0
    FROM employees e
    WHERE e.is_active = TRUE
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;
    
    -- Sick Leave (10 days for everyone)
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT e.id, sick_id, 2026, 10, 0
    FROM employees e
    WHERE e.is_active = TRUE
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;
    
    -- Casual Leave (6 days for everyone)
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT e.id, casual_id, 2026, 6, 0
    FROM employees e
    WHERE e.is_active = TRUE
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;
    
    -- Maternity Leave (90 days - only eligible female employees, typically those who might need it)
    -- For demo purposes, adding to female employees who joined before 2025
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT e.id, maternity_id, 2026, 90, 0
    FROM employees e
    WHERE e.is_active = TRUE 
    AND e.full_name IN ('Priya Nair', 'Sneha Kulkarni', 'Divya Reddy', 'Meera Pillai')
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;
    
    -- Paternity Leave (15 days - eligible for male employees)
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT e.id, paternity_id, 2026, 15, 0
    FROM employees e
    WHERE e.is_active = TRUE 
    AND e.full_name IN ('Aditya Sharma', 'Rahul Verma', 'Arjun Mehta', 'Karan Joshi')
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;
    
    -- Unpaid Leave (30 days for everyone as buffer)
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT e.id, unpaid_id, 2026, 30, 0
    FROM employees e
    WHERE e.is_active = TRUE
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;
    
    -- ============================================================
    -- Add some used leaves for 2026 (based on early 2026 requests)
    -- ============================================================
    
    -- EMP001: Aditya Sharma - Used 2 annual days in Jan 2026
    UPDATE leave_balances 
    SET used_days = 2
    FROM employees e
    WHERE e.employee_code = 'EMP001'
    AND leave_balances.employee_id = e.id
    AND leave_balances.leave_type_id = annual_id
    AND leave_balances.year = 2026;
    
    -- EMP002: Priya Nair - Used 1 sick day in Jan 2026
    UPDATE leave_balances 
    SET used_days = 1
    FROM employees e
    WHERE e.employee_code = 'EMP002'
    AND leave_balances.employee_id = e.id
    AND leave_balances.leave_type_id = sick_id
    AND leave_balances.year = 2026;
    
    -- EMP003: Rahul Verma - Used 3 annual days in Feb 2026
    UPDATE leave_balances 
    SET used_days = 3
    FROM employees e
    WHERE e.employee_code = 'EMP003'
    AND leave_balances.employee_id = e.id
    AND leave_balances.leave_type_id = annual_id
    AND leave_balances.year = 2026;
    
    -- EMP005: Arjun Mehta - Used 1 casual day in Jan 2026
    UPDATE leave_balances 
    SET used_days = 1
    FROM employees e
    WHERE e.employee_code = 'EMP005'
    AND leave_balances.employee_id = e.id
    AND leave_balances.leave_type_id = casual_id
    AND leave_balances.year = 2026;
    
END $$;

-- ============================================================
-- Sample Leave Requests for 2026
-- ============================================================

-- Annual leave request for EMP001 (Aditya) - Approved
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_count, reason, status, manager_note)
SELECT
    e.id,
    lt.id,
    '2026-01-15',
    '2026-01-16',
    2,
    'Short vacation',
    'approved',
    'Team lead approved'
FROM employees e, leave_types lt
WHERE e.employee_code = 'EMP001' AND lt.name = 'Annual'
ON CONFLICT (id) DO NOTHING;

-- Sick leave request for EMP002 (Priya) - Approved
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_count, reason, status, manager_note)
SELECT
    e.id,
    lt.id,
    '2026-01-20',
    '2026-01-20',
    1,
    'Doctor appointment',
    'approved',
    'Get well soon'
FROM employees e, leave_types lt
WHERE e.employee_code = 'EMP002' AND lt.name = 'Sick'
ON CONFLICT (id) DO NOTHING;

-- Annual leave request for EMP003 (Rahul) - Pending
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_count, reason, status)
SELECT
    e.id,
    lt.id,
    '2026-03-10',
    '2026-03-14',
    5,
    'Family wedding',
    'pending'
FROM employees e, leave_types lt
WHERE e.employee_code = 'EMP003' AND lt.name = 'Annual'
ON CONFLICT (id) DO NOTHING;

-- Casual leave request for EMP004 (Sneha) - Pending
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_count, reason, status)
SELECT
    e.id,
    lt.id,
    '2026-02-05',
    '2026-02-05',
    1,
    'Personal work',
    'pending'
FROM employees e, leave_types lt
WHERE e.employee_code = 'EMP004' AND lt.name = 'Casual'
ON CONFLICT (id) DO NOTHING;

-- Maternity leave request for EMP006 (Divya) - Approved
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_count, reason, status, manager_note)
SELECT
    e.id,
    lt.id,
    '2026-06-01',
    '2026-08-29',
    90,
    'Maternity leave',
    'approved',
    'Congratulations!'
FROM employees e, leave_types lt
WHERE e.employee_code = 'EMP006' AND lt.name = 'Maternity'
ON CONFLICT (id) DO NOTHING;

-- Annual leave request for EMP007 (Karan) - Rejected
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_count, reason, status, manager_note)
SELECT
    e.id,
    lt.id,
    '2026-02-20',
    '2026-02-27',
    8,
    'International trip',
    'rejected',
    'Request exceeds available balance (only 18 days total, requested 8 days but critical project period)'
FROM employees e, leave_types lt
WHERE e.employee_code = 'EMP007' AND lt.name = 'Annual'
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- View to check 2026 balances
-- ============================================================

-- Create a helpful view for 2026 balances
CREATE OR REPLACE VIEW leave_balances_2026 AS
SELECT 
    e.employee_code,
    e.full_name,
    e.department,
    lt.name AS leave_type,
    lb.total_days,
    lb.used_days,
    (lb.total_days - lb.used_days) AS remaining_days,
    ROUND((lb.used_days::DECIMAL / NULLIF(lb.total_days, 0)) * 100, 1) AS utilization_percentage
FROM leave_balances lb
JOIN employees e ON e.id = lb.employee_id
JOIN leave_types lt ON lt.id = lb.leave_type_id
WHERE lb.year = 2026
ORDER BY e.employee_code, lt.name;

-- ============================================================
-- Optional: Copy 2025 balances to 2026 (alternative approach)
-- ============================================================
-- Use this if you want to copy previous year's balances instead of starting fresh
/*
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN 
        SELECT employee_id, leave_type_id, total_days, 0 as used_days
        FROM leave_balances 
        WHERE year = 2025
        AND NOT EXISTS (
            SELECT 1 FROM leave_balances lb2 
            WHERE lb2.employee_id = leave_balances.employee_id 
            AND lb2.leave_type_id = leave_balances.leave_type_id 
            AND lb2.year = 2026
        )
    LOOP
        INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
        VALUES (rec.employee_id, rec.leave_type_id, 2026, rec.total_days, 0);
    END LOOP;
END $$;
*/

-- ============================================================
-- Display summary for 2026
-- ============================================================
SELECT 
    '2026 Leave Balances Summary' AS info,
    COUNT(DISTINCT employee_id) AS total_employees,
    COUNT(*) AS total_balance_records,
    SUM(used_days) AS total_used_days_across_all_types,
    SUM(total_days) AS total_allocated_days_across_all_types
FROM leave_balances 
WHERE year = 2026;