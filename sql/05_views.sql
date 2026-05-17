-- ============================================================================
-- Banking Management System — Views
-- Read-only views that pre-compose common analytic queries. They simplify
-- application code, encapsulate aggregation logic in the database, and let
-- the Auditor role have read-only access without exposing underlying tables.
--   v_customer_summary       — 1 row per customer: balances, accounts, loans
--   v_branch_performance     — 1 row per branch: deposits, loans, headcount
--   v_daily_transaction_summary — daily aggregates by transaction type
--   v_loan_portfolio         — loan list with computed remaining balance
--   v_top_customers          — top 100 customers by total balance
--   v_overdue_loans          — overdue payments with days late
--   v_transaction_audit_trail — transactions joined with operator / customer
-- ============================================================================

USE banking_system;

DROP VIEW IF EXISTS v_customer_summary;
DROP VIEW IF EXISTS v_branch_performance;
DROP VIEW IF EXISTS v_daily_transaction_summary;
DROP VIEW IF EXISTS v_loan_portfolio;
DROP VIEW IF EXISTS v_top_customers;
DROP VIEW IF EXISTS v_overdue_loans;
DROP VIEW IF EXISTS v_transaction_audit_trail;

-- ----------------------------------------------------------------------------
-- 1. v_customer_summary
-- One row per customer with aggregated holdings information.
-- ----------------------------------------------------------------------------
CREATE VIEW v_customer_summary AS
SELECT
    c.customer_id,
    c.cust_code,
    c.full_name,
    c.gender,
    c.city,
    c.credit_score,
    c.register_date,
    COUNT(DISTINCT a.account_id)         AS active_accounts,
    COALESCE(SUM(a.balance), 0)          AS total_balance,
    COUNT(DISTINCT l.loan_id)            AS active_loans,
    COALESCE(SUM(l.loan_amount), 0)      AS total_loan_principal
FROM customers c
LEFT JOIN accounts a
       ON c.customer_id = a.customer_id
      AND a.status = 'Active'
LEFT JOIN loans l
       ON c.customer_id = l.customer_id
      AND l.status = 'Active'
GROUP BY c.customer_id, c.cust_code, c.full_name, c.gender,
         c.city, c.credit_score, c.register_date;

-- ----------------------------------------------------------------------------
-- 2. v_branch_performance
-- One row per branch summarizing operational scale and book value.
-- ----------------------------------------------------------------------------
CREATE VIEW v_branch_performance AS
SELECT
    b.branch_id,
    b.branch_code,
    b.branch_name,
    b.city,
    (SELECT COUNT(*) FROM employees e
       WHERE e.branch_id = b.branch_id AND e.status = 'Active')      AS employee_count,
    (SELECT COUNT(*) FROM accounts a
       WHERE a.branch_id = b.branch_id AND a.status = 'Active')      AS account_count,
    (SELECT COALESCE(SUM(balance),0) FROM accounts a
       WHERE a.branch_id = b.branch_id AND a.status = 'Active')      AS total_deposits,
    (SELECT COUNT(*) FROM loans l
       WHERE l.branch_id = b.branch_id AND l.status = 'Active')      AS active_loan_count,
    (SELECT COALESCE(SUM(loan_amount),0) FROM loans l
       WHERE l.branch_id = b.branch_id AND l.status = 'Active')      AS total_loan_principal
FROM branches b;

-- ----------------------------------------------------------------------------
-- 3. v_daily_transaction_summary
-- Aggregates the transactions table by calendar day and transaction type.
-- ----------------------------------------------------------------------------
CREATE VIEW v_daily_transaction_summary AS
SELECT
    DATE(transaction_date)              AS txn_date,
    transaction_type,
    COUNT(*)                            AS txn_count,
    SUM(amount)                         AS total_amount,
    AVG(amount)                         AS avg_amount,
    MIN(amount)                         AS min_amount,
    MAX(amount)                         AS max_amount
FROM transactions
WHERE status = 'Completed'
GROUP BY DATE(transaction_date), transaction_type;

-- ----------------------------------------------------------------------------
-- 4. v_loan_portfolio
-- Loan list enriched with computed remaining balance and payment status counts.
-- ----------------------------------------------------------------------------
CREATE VIEW v_loan_portfolio AS
SELECT
    l.loan_id,
    l.loan_code,
    l.customer_id,
    c.full_name                                      AS customer_name,
    b.branch_name,
    l.loan_amount,
    l.interest_rate,
    l.term_months,
    l.start_date,
    l.end_date,
    l.status,
    fn_GetLoanRemainingBalance(l.loan_id)            AS remaining_balance,
    (SELECT COUNT(*) FROM loan_payments lp
       WHERE lp.loan_id = l.loan_id AND lp.status = 'Paid')    AS paid_count,
    (SELECT COUNT(*) FROM loan_payments lp
       WHERE lp.loan_id = l.loan_id AND lp.status = 'Late')    AS late_count,
    (SELECT COUNT(*) FROM loan_payments lp
       WHERE lp.loan_id = l.loan_id AND lp.status = 'Missed')  AS missed_count
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
JOIN branches  b ON l.branch_id   = b.branch_id;

-- ----------------------------------------------------------------------------
-- 5. v_top_customers
-- Top 100 customers ranked by total active-account balance.
-- ----------------------------------------------------------------------------
CREATE VIEW v_top_customers AS
SELECT
    cs.customer_id,
    cs.cust_code,
    cs.full_name,
    cs.city,
    cs.active_accounts,
    cs.total_balance,
    cs.active_loans
FROM v_customer_summary cs
ORDER BY cs.total_balance DESC
LIMIT 100;

-- ----------------------------------------------------------------------------
-- 6. v_overdue_loans
-- Loan-payment rows that are past their scheduled date and not yet paid.
-- ----------------------------------------------------------------------------
CREATE VIEW v_overdue_loans AS
SELECT
    l.loan_id,
    l.loan_code,
    c.full_name                                      AS customer_name,
    lp.payment_id,
    lp.scheduled_date,
    lp.amount,
    DATEDIFF(CURDATE(), lp.scheduled_date)           AS days_overdue,
    lp.status,
    fn_GetLoanRemainingBalance(l.loan_id)            AS loan_remaining_balance
FROM loan_payments lp
JOIN loans     l ON lp.loan_id = l.loan_id
JOIN customers c ON l.customer_id = c.customer_id
WHERE lp.status IN ('Scheduled','Late','Missed')
  AND lp.scheduled_date < CURDATE()
  AND lp.actual_date IS NULL;

-- ----------------------------------------------------------------------------
-- 7. v_transaction_audit_trail
-- Transactions joined with operator and customer for compliance audit.
-- ----------------------------------------------------------------------------
CREATE VIEW v_transaction_audit_trail AS
SELECT
    t.transaction_id,
    t.transaction_date,
    t.transaction_type,
    t.amount,
    t.balance_after,
    t.status,
    a.account_number,
    c.cust_code                AS customer_code,
    c.full_name                AS customer_name,
    e.emp_code                 AS employee_code,
    e.full_name                AS processed_by,
    e.position                 AS processed_by_position,
    b.branch_name
FROM transactions t
JOIN accounts a  ON t.account_id  = a.account_id
JOIN customers c ON a.customer_id = c.customer_id
JOIN branches  b ON a.branch_id   = b.branch_id
LEFT JOIN employees e ON t.employee_id = e.employee_id;

-- ============================================================================
-- End of views (7 total)
-- ============================================================================
