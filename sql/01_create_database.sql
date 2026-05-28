-- ============================================================================
-- Banking Management System — Schema Definition
-- Project 09  |  DSEB 66B  |  Đỗ Minh Thành (11245932)
-- DBMS: MySQL 8.x  |  Engine: InnoDB  |  Charset: utf8mb4
-- ============================================================================

-- Drop and recreate database (CAUTION: destructive)
DROP DATABASE IF EXISTS banking_system;
CREATE DATABASE banking_system
    CHARACTER SET utf8mb4
    COLLATE     utf8mb4_unicode_ci;

USE banking_system;

-- Drop tables in reverse dependency order (idempotent)
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS loan_payments;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS cards;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS account_types;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS branches;

-- ----------------------------------------------------------------------------
-- 1. branches  —  bank branch locations
-- ----------------------------------------------------------------------------
CREATE TABLE branches (
    branch_id        INT          AUTO_INCREMENT PRIMARY KEY,
    branch_code      VARCHAR(10)  NOT NULL UNIQUE,
    branch_name      VARCHAR(100) NOT NULL,
    address          VARCHAR(255) NOT NULL,
    city             VARCHAR(50)  NOT NULL,
    phone            VARCHAR(20),
    open_date        DATE         NOT NULL,
    created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_branch_city (city)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 2. employees  —  bank staff with reporting hierarchy
-- ----------------------------------------------------------------------------
CREATE TABLE employees (
    employee_id      INT          AUTO_INCREMENT PRIMARY KEY,
    emp_code         VARCHAR(15)  NOT NULL UNIQUE,
    full_name        VARCHAR(100) NOT NULL,
    position         ENUM('Manager', 'Teller', 'Auditor', 'Admin') NOT NULL,
    branch_id        INT          NOT NULL,
    email            VARCHAR(100) UNIQUE,
    phone            VARCHAR(20),
    hire_date        DATE         NOT NULL,
    salary           DECIMAL(12,2) NOT NULL,
    manager_id       INT          NULL,
    status           ENUM('Active', 'Inactive') DEFAULT 'Active',
    created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_emp_branch  FOREIGN KEY (branch_id)  REFERENCES branches(branch_id),
    CONSTRAINT fk_emp_manager FOREIGN KEY (manager_id) REFERENCES employees(employee_id),
    CONSTRAINT chk_emp_salary CHECK (salary > 0),
    INDEX idx_emp_branch   (branch_id),
    INDEX idx_emp_position (position),
    INDEX idx_emp_status   (status)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 3. customers  —  bank customers (PII fields encrypted)
-- ----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id      INT          AUTO_INCREMENT PRIMARY KEY,
    cust_code        VARCHAR(15)  NOT NULL UNIQUE,
    full_name        VARCHAR(100) NOT NULL,
    gender           ENUM('Male', 'Female', 'Other'),
    date_of_birth    DATE         NOT NULL,
    national_id      VARBINARY(255),                       -- AES_ENCRYPT'd
    phone            VARCHAR(20),
    email            VARCHAR(100),
    address          VARCHAR(255),
    city             VARCHAR(50),
    register_date    DATE         NOT NULL,
    credit_score     INT,
    created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_cust_score CHECK (credit_score BETWEEN 300 AND 850),
    INDEX idx_cust_name (full_name),
    INDEX idx_cust_city (city),
    INDEX idx_cust_phone (phone)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 4. account_types  —  reference: Checking, Savings, ...
-- ----------------------------------------------------------------------------
CREATE TABLE account_types (
    type_id          INT          AUTO_INCREMENT PRIMARY KEY,
    type_name        VARCHAR(30)  NOT NULL UNIQUE,
    interest_rate    DECIMAL(5,4) NOT NULL,                -- e.g. 0.0350 = 3.50%
    min_balance      DECIMAL(12,2) NOT NULL,
    description      VARCHAR(255),
    CONSTRAINT chk_at_rate CHECK (interest_rate >= 0),
    CONSTRAINT chk_at_min  CHECK (min_balance  >= 0)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 5. accounts  —  customer bank accounts
-- ----------------------------------------------------------------------------
CREATE TABLE accounts (
    account_id       INT          AUTO_INCREMENT PRIMARY KEY,
    account_number   VARCHAR(20)  NOT NULL UNIQUE,
    customer_id      INT          NOT NULL,
    type_id          INT          NOT NULL,
    branch_id        INT          NOT NULL,
    balance          DECIMAL(15,2) NOT NULL DEFAULT 0,
    status           ENUM('Active', 'Frozen', 'Closed') DEFAULT 'Active',
    open_date        DATE         NOT NULL,
    close_date       DATE         NULL,
    created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_acc_cust   FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_acc_type   FOREIGN KEY (type_id)     REFERENCES account_types(type_id),
    CONSTRAINT fk_acc_branch FOREIGN KEY (branch_id)   REFERENCES branches(branch_id),
    CONSTRAINT chk_acc_bal   CHECK (balance >= 0),
    INDEX idx_acc_customer (customer_id),
    INDEX idx_acc_branch   (branch_id),
    INDEX idx_acc_status   (status),
    INDEX idx_acc_type     (type_id)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 6. transactions  —  every money movement
-- ----------------------------------------------------------------------------
CREATE TABLE transactions (
    transaction_id     BIGINT       AUTO_INCREMENT PRIMARY KEY,
    account_id         INT          NOT NULL,
    related_account_id INT          NULL,                   -- counterparty for transfers
    transaction_type   ENUM('Deposit','Withdrawal','Transfer_Out','Transfer_In','Interest','Fee') NOT NULL,
    amount             DECIMAL(15,2) NOT NULL,
    balance_after      DECIMAL(15,2) NOT NULL,
    transaction_date   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description        VARCHAR(255),
    employee_id        INT          NULL,
    status             ENUM('Completed','Pending','Reversed') DEFAULT 'Completed',
    CONSTRAINT fk_tx_acc     FOREIGN KEY (account_id)         REFERENCES accounts(account_id),
    CONSTRAINT fk_tx_related FOREIGN KEY (related_account_id) REFERENCES accounts(account_id),
    CONSTRAINT fk_tx_emp     FOREIGN KEY (employee_id)        REFERENCES employees(employee_id),
    CONSTRAINT chk_tx_amount CHECK (amount > 0),
    INDEX idx_tx_account (account_id),
    INDEX idx_tx_date    (transaction_date),
    INDEX idx_tx_type    (transaction_type),
    INDEX idx_tx_status  (status),
    INDEX idx_tx_acc_date (account_id, transaction_date)     -- composite for statement queries
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 7. loans
-- ----------------------------------------------------------------------------
CREATE TABLE loans (
    loan_id          INT          AUTO_INCREMENT PRIMARY KEY,
    loan_code        VARCHAR(15)  NOT NULL UNIQUE,
    customer_id      INT          NOT NULL,
    loan_amount      DECIMAL(15,2) NOT NULL,
    interest_rate    DECIMAL(5,4) NOT NULL,
    term_months      INT          NOT NULL,
    start_date       DATE         NOT NULL,
    end_date         DATE         NOT NULL,
    status           ENUM('Active','PaidOff','Defaulted','Cancelled') DEFAULT 'Active',
    branch_id        INT          NOT NULL,
    employee_id      INT          NOT NULL,
    created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_loan_cust   FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_loan_branch FOREIGN KEY (branch_id)   REFERENCES branches(branch_id),
    CONSTRAINT fk_loan_emp    FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
    CONSTRAINT chk_loan_amt   CHECK (loan_amount > 0),
    CONSTRAINT chk_loan_rate  CHECK (interest_rate > 0),
    CONSTRAINT chk_loan_term  CHECK (term_months > 0),
    CONSTRAINT chk_loan_dates CHECK (end_date > start_date),
    INDEX idx_loan_customer (customer_id),
    INDEX idx_loan_status   (status),
    INDEX idx_loan_branch   (branch_id)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 8. loan_payments  —  amortization schedule + actual payments
-- ----------------------------------------------------------------------------
CREATE TABLE loan_payments (
    payment_id       INT          AUTO_INCREMENT PRIMARY KEY,
    loan_id          INT          NOT NULL,
    scheduled_date   DATE         NOT NULL,
    actual_date      DATE         NULL,
    amount           DECIMAL(15,2) NOT NULL,
    principal        DECIMAL(15,2) NOT NULL,
    interest         DECIMAL(15,2) NOT NULL,
    status           ENUM('Scheduled','Paid','Late','Missed') DEFAULT 'Scheduled',
    CONSTRAINT fk_pay_loan FOREIGN KEY (loan_id) REFERENCES loans(loan_id) ON DELETE CASCADE,
    CONSTRAINT chk_pay_amt CHECK (amount > 0),
    INDEX idx_pay_loan   (loan_id),
    INDEX idx_pay_status (status),
    INDEX idx_pay_sched  (scheduled_date)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 9. cards  —  ATM / Debit / Credit cards
-- ----------------------------------------------------------------------------
CREATE TABLE cards (
    card_id          INT          AUTO_INCREMENT PRIMARY KEY,
    card_number      VARCHAR(20)  NOT NULL UNIQUE,
    account_id       INT          NOT NULL,
    card_type        ENUM('ATM','Debit','Credit') DEFAULT 'ATM',
    issue_date       DATE         NOT NULL,
    expiry_date      DATE         NOT NULL,
    status           ENUM('Active','Blocked','Expired') DEFAULT 'Active',
    pin_hash         VARCHAR(64)  NOT NULL,                 -- SHA-256
    CONSTRAINT fk_card_acc    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    CONSTRAINT chk_card_dates CHECK (expiry_date > issue_date),
    INDEX idx_card_account (account_id),
    INDEX idx_card_status  (status)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 10. users  —  application authentication
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id          INT          AUTO_INCREMENT PRIMARY KEY,
    username         VARCHAR(50)  NOT NULL UNIQUE,
    password_hash    VARCHAR(64)  NOT NULL,                 -- SHA-256
    employee_id      INT          NULL,
    role             ENUM('Admin','Manager','Teller','Auditor') NOT NULL,
    last_login       DATETIME     NULL,
    is_active        BOOLEAN      DEFAULT TRUE,
    created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_emp FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 11. audit_log  —  immutable trail of changes on critical tables
-- ----------------------------------------------------------------------------
CREATE TABLE audit_log (
    log_id           BIGINT       AUTO_INCREMENT PRIMARY KEY,
    table_name       VARCHAR(50)  NOT NULL,
    operation_type   ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    record_id        VARCHAR(50)  NOT NULL,
    old_values       JSON         NULL,
    new_values       JSON         NULL,
    changed_by       VARCHAR(50)  NULL,
    changed_at       DATETIME     DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_table (table_name),
    INDEX idx_audit_date  (changed_at),
    INDEX idx_audit_record (table_name, record_id)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- Reference data: account types
-- ----------------------------------------------------------------------------
INSERT INTO account_types (type_name, interest_rate, min_balance, description) VALUES
    ('Checking',         0.0010,   50000.00, 'Standard checking account, low interest, low minimum balance'),
    ('Savings',          0.0420,  500000.00, 'Standard savings account, monthly interest accrual'),
    ('Premium Savings',  0.0580, 5000000.00, 'High-balance savings with premium interest rate'),
    ('Student',          0.0250,       0.00, 'Fee-free account for verified students');

-- ============================================================================
-- End of schema
-- ============================================================================
USE banking_system;
SHOW TABLES;
SELECT * FROM account_types;