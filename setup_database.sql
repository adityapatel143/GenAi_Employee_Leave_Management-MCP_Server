-- ============================================================
-- Employee Leave Management — Supabase Schema + Seed Data
-- Run this in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================


-- ── 1. EMPLOYEES ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS employees (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_code TEXT NOT NULL UNIQUE,   -- e.g. "EMP001"
    full_name     TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE,
    department    TEXT NOT NULL,
    position      TEXT NOT NULL,
    joining_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ── 2. LEAVE TYPES ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS leave_types (
    id            SERIAL PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,   -- "Annual", "Sick", "Casual", …
    description   TEXT,
    default_days  INT  NOT NULL           -- days granted per year
);


-- ── 3. LEAVE BALANCES (per employee, per type, per year) ─────
CREATE TABLE IF NOT EXISTS leave_balances (
    id             SERIAL PRIMARY KEY,
    employee_id    UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    leave_type_id  INT  NOT NULL REFERENCES leave_types(id) ON DELETE CASCADE,
    year           INT  NOT NULL,
    total_days     INT  NOT NULL,
    used_days      INT  NOT NULL DEFAULT 0,
    UNIQUE (employee_id, leave_type_id, year)
);

-- Computed column helper view
CREATE OR REPLACE VIEW leave_balances_view AS
SELECT
    lb.id,
    lb.employee_id,
    e.employee_code,
    e.full_name,
    lt.name   AS leave_type,
    lb.year,
    lb.total_days,
    lb.used_days,
    (lb.total_days - lb.used_days) AS remaining_days
FROM leave_balances lb
JOIN employees   e  ON e.id  = lb.employee_id
JOIN leave_types lt ON lt.id = lb.leave_type_id;


-- ── 4. LEAVE REQUESTS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS leave_requests (
    id             SERIAL PRIMARY KEY,
    employee_id    UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    leave_type_id  INT  NOT NULL REFERENCES leave_types(id),
    start_date     DATE NOT NULL,
    end_date       DATE NOT NULL,
    days_count     INT  NOT NULL,          -- business days requested
    reason         TEXT,
    status         TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','approved','rejected','cancelled')),
    manager_note   TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_leave_requests_updated_at ON leave_requests;
CREATE TRIGGER trg_leave_requests_updated_at
BEFORE UPDATE ON leave_requests
FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- ════════════════════════════════════════════════════════════
-- SEED DATA
-- ════════════════════════════════════════════════════════════

-- Leave Types
INSERT INTO leave_types (name, description, default_days) VALUES
    ('Annual',     'Paid annual vacation leave',                    18),
    ('Sick',       'Medical / health-related leave',                10),
    ('Casual',     'Short personal errands (max 3 consecutive)',     6),
    ('Maternity',  'Maternity leave for eligible employees',        90),
    ('Paternity',  'Paternity leave for eligible employees',        15),
    ('Unpaid',     'Leave without pay when all paid leaves exhausted', 30)
ON CONFLICT (name) DO NOTHING;


-- Employees
INSERT INTO employees (employee_code, full_name, email, department, position, joining_date) VALUES
    ('EMP001', 'Aditya Sharma',    'aditya.sharma@company.com',    'Engineering',   'Senior Developer',    '2022-03-15'),
    ('EMP002', 'Priya Nair',       'priya.nair@company.com',       'Engineering',   'Backend Developer',   '2023-01-10'),
    ('EMP003', 'Rahul Verma',      'rahul.verma@company.com',      'HR',            'HR Manager',          '2021-06-01'),
    ('EMP004', 'Sneha Kulkarni',   'sneha.kulkarni@company.com',   'Design',        'UI/UX Designer',      '2023-07-20'),
    ('EMP005', 'Arjun Mehta',      'arjun.mehta@company.com',      'Engineering',   'DevOps Engineer',     '2022-11-05'),
    ('EMP006', 'Divya Reddy',      'divya.reddy@company.com',      'Marketing',     'Marketing Lead',      '2021-09-14'),
    ('EMP007', 'Karan Joshi',      'karan.joshi@company.com',      'Sales',         'Sales Executive',     '2024-02-01'),
    ('EMP008', 'Meera Pillai',     'meera.pillai@company.com',     'Engineering',   'QA Engineer',         '2022-05-30')
ON CONFLICT (employee_code) DO NOTHING;


-- Leave Balances for 2025 — run after employees and leave_types are inserted
DO $$
DECLARE
    annual_id  INT;
    sick_id    INT;
    casual_id  INT;
BEGIN
    SELECT id INTO annual_id FROM leave_types WHERE name = 'Annual';
    SELECT id INTO sick_id   FROM leave_types WHERE name = 'Sick';
    SELECT id INTO casual_id FROM leave_types WHERE name = 'Casual';

    -- EMP001 — already used 5 annual + 2 sick
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, annual_id, 2025, 18, 5 FROM employees WHERE employee_code = 'EMP001'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, sick_id,   2025, 10, 2 FROM employees WHERE employee_code = 'EMP001'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, casual_id, 2025,  6, 1 FROM employees WHERE employee_code = 'EMP001'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    -- EMP002
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, annual_id, 2025, 18, 3 FROM employees WHERE employee_code = 'EMP002'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, sick_id,   2025, 10, 0 FROM employees WHERE employee_code = 'EMP002'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, casual_id, 2025,  6, 0 FROM employees WHERE employee_code = 'EMP002'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    -- EMP003
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, annual_id, 2025, 18, 10 FROM employees WHERE employee_code = 'EMP003'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, sick_id,   2025, 10,  4 FROM employees WHERE employee_code = 'EMP003'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, casual_id, 2025,  6,  2 FROM employees WHERE employee_code = 'EMP003'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    -- EMP004
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, annual_id, 2025, 18, 0 FROM employees WHERE employee_code = 'EMP004'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, sick_id,   2025, 10, 1 FROM employees WHERE employee_code = 'EMP004'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, casual_id, 2025,  6, 3 FROM employees WHERE employee_code = 'EMP004'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    -- EMP005
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, annual_id, 2025, 18, 7 FROM employees WHERE employee_code = 'EMP005'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, sick_id,   2025, 10, 0 FROM employees WHERE employee_code = 'EMP005'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT id, casual_id, 2025,  6, 0 FROM employees WHERE employee_code = 'EMP005'
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

    -- EMP006, EMP007, EMP008 (fresh balances) - FIXED VERSION
    -- Using a single INSERT with CROSS JOIN (most efficient)
    INSERT INTO leave_balances (employee_id, leave_type_id, year, total_days, used_days)
    SELECT e.id, lt.id, 2025, lt.default_days, 0
    FROM employees e
    CROSS JOIN (
        SELECT id, default_days 
        FROM leave_types 
        WHERE name IN ('Annual', 'Sick', 'Casual')
    ) lt
    WHERE e.employee_code IN ('EMP006','EMP007','EMP008')
    ON CONFLICT (employee_id, leave_type_id, year) DO NOTHING;

END $$;


-- Sample approved leave requests for EMP001
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_count, reason, status)
SELECT
    e.id,
    lt.id,
    '2025-01-13',
    '2025-01-17',
    5,
    'Family vacation',
    'approved'
FROM employees e, leave_types lt
WHERE e.employee_code = 'EMP001' AND lt.name = 'Annual'
ON CONFLICT DO NOTHING;

INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_count, reason, status)
SELECT
    e.id,
    lt.id,
    '2025-02-10',
    '2025-02-11',
    2,
    'Fever and rest',
    'approved'
FROM employees e, leave_types lt
WHERE e.employee_code = 'EMP001' AND lt.name = 'Sick'
ON CONFLICT DO NOTHING;

-- Optional: Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee_id ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_leave_requests_dates ON leave_requests(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_leave_balances_employee_year ON leave_balances(employee_id, year);
CREATE INDEX IF NOT EXISTS idx_employees_employee_code ON employees(employee_code);