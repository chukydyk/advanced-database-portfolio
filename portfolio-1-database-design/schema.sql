-- =====================================================================
-- The Homes Hotel Chain: Portfolio 1 schema (PostgreSQL 15+)
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- needed for the double-booking constraint

-- ---------- Chain structure ----------
CREATE TABLE hotel (
    hotel_id      SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    city          VARCHAR(60)  NOT NULL,
    country       VARCHAR(60)  NOT NULL,
    address       VARCHAR(200) NOT NULL,
    phone         VARCHAR(30),
    email         VARCHAR(120) UNIQUE,
    star_rating   SMALLINT CHECK (star_rating BETWEEN 1 AND 5)
);

CREATE TABLE room_type (
    room_type_id  SERIAL PRIMARY KEY,
    type_name     VARCHAR(50) NOT NULL UNIQUE,      -- Single, Double, Suite...
    max_occupancy SMALLINT NOT NULL CHECK (max_occupancy > 0),
    description   TEXT
);

CREATE TABLE room (
    room_id       SERIAL PRIMARY KEY,
    hotel_id      INT NOT NULL REFERENCES hotel(hotel_id),
    room_type_id  INT NOT NULL REFERENCES room_type(room_type_id),
    room_number   VARCHAR(10) NOT NULL,
    floor         SMALLINT,
    status        VARCHAR(20) NOT NULL DEFAULT 'available'
                  CHECK (status IN ('available','occupied','cleaning','maintenance')),
    UNIQUE (hotel_id, room_number)
);

CREATE TABLE amenity (
    amenity_id    SERIAL PRIMARY KEY,
    amenity_name  VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE room_type_amenity (                    -- M:N resolution
    room_type_id  INT REFERENCES room_type(room_type_id),
    amenity_id    INT REFERENCES amenity(amenity_id),
    PRIMARY KEY (room_type_id, amenity_id)
);

-- ---------- Pricing ----------
CREATE TABLE rate (
    rate_id       SERIAL PRIMARY KEY,
    hotel_id      INT NOT NULL REFERENCES hotel(hotel_id),
    room_type_id  INT NOT NULL REFERENCES room_type(room_type_id),
    season_name   VARCHAR(40) NOT NULL,
    valid_from    DATE NOT NULL,
    valid_to      DATE NOT NULL,
    nightly_rate  NUMERIC(10,2) NOT NULL CHECK (nightly_rate > 0),
    CHECK (valid_to >= valid_from)
);

CREATE TABLE promotion (
    promo_id      SERIAL PRIMARY KEY,
    promo_code    VARCHAR(30) NOT NULL UNIQUE,
    discount_pct  NUMERIC(5,2) NOT NULL CHECK (discount_pct BETWEEN 0 AND 100),
    valid_from    DATE NOT NULL,
    valid_to      DATE NOT NULL,
    CHECK (valid_to >= valid_from)
);

-- ---------- Guests and loyalty ----------
CREATE TABLE guest (
    guest_id      SERIAL PRIMARY KEY,
    first_name    VARCHAR(60) NOT NULL,
    last_name     VARCHAR(60) NOT NULL,
    email         VARCHAR(120) NOT NULL UNIQUE,
    phone         VARCHAR(30),
    nationality   VARCHAR(60),
    id_type       VARCHAR(30),                      -- passport, national ID...
    id_doc_ref    VARCHAR(100),                     -- masked/reference only, never the raw document
    registered_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE loyalty_account (
    loyalty_id     SERIAL PRIMARY KEY,
    guest_id       INT NOT NULL UNIQUE REFERENCES guest(guest_id),   -- 1:1
    tier           VARCHAR(20) NOT NULL DEFAULT 'Standard'
                   CHECK (tier IN ('Standard','Silver','Gold','Platinum')),
    points_balance INT NOT NULL DEFAULT 0 CHECK (points_balance >= 0)
);

CREATE TABLE loyalty_transaction (
    loyalty_txn_id SERIAL PRIMARY KEY,
    loyalty_id     INT NOT NULL REFERENCES loyalty_account(loyalty_id),
    points_change  INT NOT NULL,
    reason         VARCHAR(100),
    created_at     TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------- Staff ----------
CREATE TABLE staff_role (
    role_id    SERIAL PRIMARY KEY,
    role_name  VARCHAR(50) NOT NULL UNIQUE          -- Receptionist, Housekeeper, Manager...
);

CREATE TABLE employee (
    employee_id SERIAL PRIMARY KEY,
    hotel_id    INT NOT NULL REFERENCES hotel(hotel_id),
    role_id     INT NOT NULL REFERENCES staff_role(role_id),
    first_name  VARCHAR(60) NOT NULL,
    last_name   VARCHAR(60) NOT NULL,
    email       VARCHAR(120) NOT NULL UNIQUE,
    hire_date   DATE NOT NULL
);

-- ---------- Bookings ----------
CREATE TABLE booking_source (
    source_id        SERIAL PRIMARY KEY,
    source_name      VARCHAR(50) NOT NULL UNIQUE,   -- Website, Mobile App, Walk-in, Agent...
    commission_rate  NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (commission_rate BETWEEN 0 AND 100)
);

CREATE TABLE booking (
    booking_id     SERIAL PRIMARY KEY,
    guest_id       INT NOT NULL REFERENCES guest(guest_id),
    hotel_id       INT NOT NULL REFERENCES hotel(hotel_id),
    source_id      INT NOT NULL REFERENCES booking_source(source_id),
    promo_id       INT REFERENCES promotion(promo_id),
    booked_at      TIMESTAMP NOT NULL DEFAULT now(),
    check_in_date  DATE NOT NULL,
    check_out_date DATE NOT NULL,
    num_guests     SMALLINT NOT NULL CHECK (num_guests > 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','confirmed','checked_in','completed','cancelled','no_show')),
    CHECK (check_out_date > check_in_date)
);

-- One booking can hold several rooms. stay_period is copied from the booking
-- on purpose (controlled denormalisation) so the database itself can reject
-- overlapping reservations of the same room.
CREATE TABLE booking_room (
    booking_room_id SERIAL PRIMARY KEY,
    booking_id      INT NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
    room_id         INT NOT NULL REFERENCES room(room_id),
    rate_applied    NUMERIC(10,2) NOT NULL CHECK (rate_applied > 0),
    stay_period     DATERANGE NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,   -- FALSE when cancelled
    UNIQUE (booking_id, room_id),
    EXCLUDE USING gist (room_id WITH =, stay_period WITH &&) WHERE (is_active)
);

-- Check-in / check-out record
CREATE TABLE stay_record (
    stay_id          SERIAL PRIMARY KEY,
    booking_room_id  INT NOT NULL UNIQUE REFERENCES booking_room(booking_room_id),
    checked_in_at    TIMESTAMP NOT NULL,
    checked_out_at   TIMESTAMP,
    checkin_by       INT NOT NULL REFERENCES employee(employee_id),
    checkout_by      INT REFERENCES employee(employee_id),
    CHECK (checked_out_at IS NULL OR checked_out_at > checked_in_at)
);

-- ---------- Services and billing ----------
CREATE TABLE service (
    service_id   SERIAL PRIMARY KEY,
    hotel_id     INT NOT NULL REFERENCES hotel(hotel_id),
    service_name VARCHAR(80) NOT NULL,              -- Restaurant, Spa, Laundry, Airport pickup
    unit_price   NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (hotel_id, service_name)
);

CREATE TABLE service_order (
    order_id          SERIAL PRIMARY KEY,
    booking_id        INT NOT NULL REFERENCES booking(booking_id),
    service_id        INT NOT NULL REFERENCES service(service_id),
    quantity          INT NOT NULL CHECK (quantity > 0),
    unit_price_charged NUMERIC(10,2) NOT NULL CHECK (unit_price_charged >= 0),  -- price snapshot
    ordered_at        TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE invoice (
    invoice_id   SERIAL PRIMARY KEY,
    booking_id   INT NOT NULL UNIQUE REFERENCES booking(booking_id),
    issued_at    TIMESTAMP NOT NULL DEFAULT now(),
    subtotal     NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    tax_amount   NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),   -- frozen snapshot at issue time
    status       VARCHAR(20) NOT NULL DEFAULT 'unpaid'
                 CHECK (status IN ('unpaid','partially_paid','paid','refunded'))
);

CREATE TABLE payment_method (
    method_id    SERIAL PRIMARY KEY,
    method_name  VARCHAR(40) NOT NULL UNIQUE        -- Card, Cash, Bank Transfer, Mobile Money
);

CREATE TABLE payment (
    payment_id    SERIAL PRIMARY KEY,
    invoice_id    INT NOT NULL REFERENCES invoice(invoice_id),
    method_id     INT NOT NULL REFERENCES payment_method(method_id),
    payment_type  VARCHAR(20) NOT NULL CHECK (payment_type IN ('deposit','full','partial','refund')),
    amount        NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    status        VARCHAR(20) NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','successful','failed')),
    gateway_token VARCHAR(100),                     -- tokenised reference, never a card number
    paid_at       TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------- Operations ----------
CREATE TABLE housekeeping_task (
    task_id       SERIAL PRIMARY KEY,
    room_id       INT NOT NULL REFERENCES room(room_id),
    assigned_to   INT REFERENCES employee(employee_id),
    task_type     VARCHAR(30) NOT NULL CHECK (task_type IN ('checkout_clean','daily_clean','deep_clean')),
    status        VARCHAR(20) NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','in_progress','done')),
    created_at    TIMESTAMP NOT NULL DEFAULT now(),
    completed_at  TIMESTAMP
);

CREATE TABLE maintenance_request (
    request_id    SERIAL PRIMARY KEY,
    room_id       INT NOT NULL REFERENCES room(room_id),
    reported_by   INT NOT NULL REFERENCES employee(employee_id),
    issue         TEXT NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved')),
    reported_at   TIMESTAMP NOT NULL DEFAULT now(),
    resolved_at   TIMESTAMP
);

CREATE TABLE audit_log (
    audit_id     BIGSERIAL PRIMARY KEY,
    table_name   VARCHAR(60) NOT NULL,
    record_id    INT NOT NULL,
    action       VARCHAR(10) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    changed_by   INT REFERENCES employee(employee_id),
    changed_at   TIMESTAMP NOT NULL DEFAULT now(),
    old_data     JSONB,
    new_data     JSONB
);

-- ---------- Baseline indexes on foreign keys / frequent filters ----------
CREATE INDEX idx_room_hotel        ON room(hotel_id);
CREATE INDEX idx_booking_guest     ON booking(guest_id);
CREATE INDEX idx_booking_hotel_dt  ON booking(hotel_id, check_in_date);
CREATE INDEX idx_payment_invoice   ON payment(invoice_id);
CREATE INDEX idx_service_order_bk  ON service_order(booking_id);
