-- ============================================================
-- GYM ADMIN — FULL DATABASE SCHEMA
-- ============================================================

-- EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgvector"; -- for AI RAG chatbot

-- ============================================================
-- 1. ROLES & PERMISSIONS (RBAC)
-- ============================================================
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) UNIQUE NOT NULL, -- owner, manager, trainer, front-desk, accountant
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    module VARCHAR(100) NOT NULL,      -- members, payments, reports, etc.
    action VARCHAR(50) NOT NULL,       -- create, read, update, delete
    description TEXT,
    UNIQUE(module, action)
);

CREATE TABLE role_permissions (
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- ============================================================
-- 2. USERS
-- ============================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_id UUID REFERENCES roles(id),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    refresh_token TEXT,
    last_login TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. GYMS
-- ============================================================
CREATE TABLE gyms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID REFERENCES users(id),
    name VARCHAR(200) NOT NULL,
    logo_url TEXT,
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(100),
    country VARCHAR(100) DEFAULT 'India',
    pincode VARCHAR(10),
    phone VARCHAR(20),
    email VARCHAR(255),
    gstin VARCHAR(20),             -- GST number for invoicing
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. BRANCHES
-- ============================================================
CREATE TABLE branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gym_id UUID REFERENCES gyms(id) ON DELETE CASCADE,
    manager_id UUID REFERENCES users(id),
    name VARCHAR(200) NOT NULL,
    address TEXT,
    city VARCHAR(100),
    phone VARCHAR(20),
    email VARCHAR(255),
    opening_time TIME,
    closing_time TIME,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. SAAS BILLING (if selling to gym owners)
-- ============================================================
CREATE TABLE billing_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,        -- Basic, Pro, Enterprise
    price_monthly NUMERIC(10,2),
    price_yearly NUMERIC(10,2),
    max_branches INT,
    max_members INT,
    features JSONB,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gym_id UUID REFERENCES gyms(id) ON DELETE CASCADE,
    billing_plan_id UUID REFERENCES billing_plans(id),
    status VARCHAR(30) DEFAULT 'active', -- active, cancelled, expired, trial
    trial_ends_at TIMESTAMPTZ,
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 6. MEMBERSHIP PLANS (gym's own plans for members)
-- ============================================================
CREATE TABLE membership_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,        -- Monthly, Quarterly, Annual
    description TEXT,
    duration_days INT NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    max_freeze_days INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE coupons (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gym_id UUID REFERENCES gyms(id),
    code VARCHAR(50) UNIQUE NOT NULL,
    discount_type VARCHAR(20) NOT NULL,   -- percentage, fixed
    discount_value NUMERIC(10,2) NOT NULL,
    max_uses INT,
    used_count INT DEFAULT 0,
    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 7. MEMBERS
-- ============================================================
CREATE TABLE members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),          -- if they have portal access
    referred_by UUID REFERENCES members(id),    -- referral tracking
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20) NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(20),
    address TEXT,
    profile_photo_url TEXT,
    emergency_contact_name VARCHAR(150),
    emergency_contact_phone VARCHAR(20),
    health_notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE member_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id UUID REFERENCES members(id) ON DELETE CASCADE,
    doc_type VARCHAR(100) NOT NULL,    -- id_proof, medical_certificate, pt_consent
    file_url TEXT NOT NULL,
    uploaded_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 8. MEMBER MEMBERSHIPS
-- ============================================================
CREATE TABLE member_memberships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id UUID REFERENCES members(id) ON DELETE CASCADE,
    plan_id UUID REFERENCES membership_plans(id),
    coupon_id UUID REFERENCES coupons(id),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    freeze_start DATE,
    freeze_end DATE,
    status VARCHAR(30) DEFAULT 'active',  -- active, expired, frozen, cancelled
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 9. PAYMENTS & INVOICES
-- ============================================================
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id UUID REFERENCES members(id),
    membership_id UUID REFERENCES member_memberships(id),
    branch_id UUID REFERENCES branches(id),
    amount NUMERIC(10,2) NOT NULL,
    payment_mode VARCHAR(50),          -- cash, upi, card, netbanking
    payment_ref VARCHAR(255),          -- transaction ID
    payment_date TIMESTAMPTZ DEFAULT NOW(),
    status VARCHAR(30) DEFAULT 'completed', -- completed, pending, failed
    notes TEXT,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id UUID REFERENCES payments(id),
    member_id UUID REFERENCES members(id),
    invoice_number VARCHAR(100) UNIQUE NOT NULL,
    issued_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    subtotal NUMERIC(10,2),
    gst_rate NUMERIC(5,2) DEFAULT 18.00,
    gst_amount NUMERIC(10,2),
    total NUMERIC(10,2),
    status VARCHAR(30) DEFAULT 'paid', -- paid, unpaid, cancelled
    pdf_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE refunds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id UUID REFERENCES payments(id),
    member_id UUID REFERENCES members(id),
    amount NUMERIC(10,2) NOT NULL,
    reason TEXT,
    refund_mode VARCHAR(50),
    refund_ref VARCHAR(255),
    refunded_by UUID REFERENCES users(id),
    refunded_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE referrals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referrer_id UUID REFERENCES members(id),
    referred_id UUID REFERENCES members(id),
    reward_given BOOLEAN DEFAULT FALSE,
    reward_amount NUMERIC(10,2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 10. STAFF
-- ============================================================
CREATE TABLE staff (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    role_id UUID REFERENCES roles(id),
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20),
    designation VARCHAR(100),          -- trainer, receptionist, cleaner
    salary NUMERIC(10,2),
    joining_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 11. ATTENDANCE
-- ============================================================
CREATE TABLE attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES branches(id),
    member_id UUID REFERENCES members(id),
    check_in TIMESTAMPTZ NOT NULL,
    check_out TIMESTAMPTZ,
    check_in_method VARCHAR(30) DEFAULT 'manual', -- manual, card, face_recognition
    marked_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE staff_attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    staff_id UUID REFERENCES staff(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id),
    check_in TIMESTAMPTZ NOT NULL,
    check_out TIMESTAMPTZ,
    marked_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 12. EXPENSES
-- ============================================================
CREATE TABLE expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    category VARCHAR(100),             -- rent, utilities, salaries, maintenance
    amount NUMERIC(10,2) NOT NULL,
    description TEXT,
    expense_date DATE NOT NULL,
    receipt_url TEXT,
    added_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 13. EQUIPMENT & MAINTENANCE
-- ============================================================
CREATE TABLE equipment (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    category VARCHAR(100),             -- cardio, strength, free_weights
    brand VARCHAR(100),
    model_number VARCHAR(100),
    purchase_date DATE,
    purchase_price NUMERIC(10,2),
    warranty_until DATE,
    status VARCHAR(30) DEFAULT 'active', -- active, under_maintenance, retired
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE maintenance_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    equipment_id UUID REFERENCES equipment(id) ON DELETE CASCADE,
    maintenance_type VARCHAR(100),     -- routine, repair, inspection
    description TEXT,
    cost NUMERIC(10,2),
    serviced_by VARCHAR(150),
    service_date DATE NOT NULL,
    next_service_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 14. LEADS / CRM
-- ============================================================
CREATE TABLE leads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES branches(id),
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20),
    source VARCHAR(100),               -- walk-in, instagram, referral, google
    interest_in VARCHAR(150),          -- plan they enquired about
    status VARCHAR(50) DEFAULT 'new',  -- new, contacted, follow-up, converted, lost
    assigned_to UUID REFERENCES users(id),
    ai_score NUMERIC(5,2),             -- AI lead scoring (Phase 2)
    notes TEXT,
    follow_up_date DATE,
    converted_member_id UUID REFERENCES members(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE lead_interactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    lead_id UUID REFERENCES leads(id) ON DELETE CASCADE,
    interaction_type VARCHAR(50),      -- call, message, visit, email
    notes TEXT,
    done_by UUID REFERENCES users(id),
    interaction_date TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 15. TRAINER PORTAL — WORKOUT & DIET PLANS
-- ============================================================
CREATE TABLE workout_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id UUID REFERENCES members(id) ON DELETE CASCADE,
    trainer_id UUID REFERENCES staff(id),
    title VARCHAR(150),
    goal VARCHAR(100),                 -- weight_loss, muscle_gain, endurance
    plan_details JSONB,                -- flexible structure for exercises
    ai_generated BOOLEAN DEFAULT FALSE,
    valid_from DATE,
    valid_until DATE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE diet_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id UUID REFERENCES members(id) ON DELETE CASCADE,
    trainer_id UUID REFERENCES staff(id),
    title VARCHAR(150),
    goal VARCHAR(100),
    plan_details JSONB,
    ai_generated BOOLEAN DEFAULT FALSE,
    valid_from DATE,
    valid_until DATE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 16. NOTIFICATIONS
-- ============================================================
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gym_id UUID REFERENCES gyms(id),
    user_id UUID REFERENCES users(id),
    member_id UUID REFERENCES members(id),
    type VARCHAR(100) NOT NULL,        -- renewal_reminder, payment_due, birthday, etc.
    channel VARCHAR(30) NOT NULL,      -- email, sms, push
    title VARCHAR(255),
    body TEXT,
    status VARCHAR(30) DEFAULT 'pending', -- pending, sent, failed
    scheduled_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    ai_generated BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE push_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    member_id UUID REFERENCES members(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL,
    platform VARCHAR(20),              -- android, ios, web
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 17. REVIEWS & FEEDBACK
-- ============================================================
CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES branches(id),
    member_id UUID REFERENCES members(id),
    trainer_id UUID REFERENCES staff(id),
    rating INT CHECK (rating BETWEEN 1 AND 5),
    review_text TEXT,
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 18. AUDIT LOGS
-- ============================================================
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,      -- CREATE, UPDATE, DELETE
    table_name VARCHAR(100) NOT NULL,
    record_id UUID,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 19. AI LOGS (audit every AI-generated suggestion)
-- ============================================================
CREATE TABLE ai_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    feature VARCHAR(100) NOT NULL,     -- chatbot, churn_prediction, workout_gen, etc.
    input_data JSONB,
    output_data JSONB,
    model_used VARCHAR(100),
    tokens_used INT,
    latency_ms INT,
    triggered_by UUID REFERENCES users(id),
    member_id UUID REFERENCES members(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 20. SETTINGS
-- ============================================================
CREATE TABLE settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gym_id UUID REFERENCES gyms(id) ON DELETE CASCADE,
    key VARCHAR(150) NOT NULL,
    value TEXT,
    UNIQUE(gym_id, key),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES (performance)
-- ============================================================
CREATE INDEX idx_members_branch ON members(branch_id);
CREATE INDEX idx_attendance_member ON attendance(member_id);
CREATE INDEX idx_attendance_checkin ON attendance(check_in);
CREATE INDEX idx_payments_member ON payments(member_id);
CREATE INDEX idx_payments_date ON payments(payment_date);
CREATE INDEX idx_leads_branch ON leads(branch_id);
CREATE INDEX idx_leads_status ON leads(status);
CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_status ON notifications(status);
CREATE INDEX idx_audit_logs_table ON audit_logs(table_name, record_id);
CREATE INDEX idx_ai_logs_feature ON ai_logs(feature);
CREATE INDEX idx_member_memberships_member ON member_memberships(member_id);
CREATE INDEX idx_member_memberships_status ON member_memberships(status);



-- Add module_permissions to billing_plans (already in your schema, just extend it)
-- The `features` JSONB column stores the enabled module list, e.g.:
-- {"modules": ["dashboard","members","attendance","payments"]}

-- Suggested plan tiers:
INSERT INTO billing_plans (name, price_monthly, price_yearly, max_branches, max_members, features) VALUES
('Starter',   999,  9990,  1,   200, '{"modules":["dashboard","gym","branches","members","membership_plans","attendance","payments","settings"]}'),
('Growth',   2499, 24990,  3,  1000, '{"modules":["dashboard","gym","branches","members","membership_plans","staff","attendance","payments","expenses","reports","notifications","leads","settings"]}'),
('Pro',      4999, 49990, 10,  5000, '{"modules":["dashboard","gym","branches","members","membership_plans","staff","attendance","payments","expenses","reports","notifications","leads","billing","rbac","equipment","reviews","coupons","settings"]}'),
('Enterprise',9999,99990, -1,    -1, '{"modules":["dashboard","gym","branches","members","membership_plans","staff","attendance","payments","expenses","reports","notifications","leads","billing","rbac","equipment","reviews","coupons","ai_chatbot","ai_insights","ai_churn","ai_forecasting","ai_workout","trainer_portal","member_portal","settings"]}');

-- API endpoint pseudocode (Node/Express):
-- GET /api/gym/:id/sidebar-permissions
-- → JOIN gyms → subscriptions → billing_plans
-- → return billing_plans.features->>'modules' as array