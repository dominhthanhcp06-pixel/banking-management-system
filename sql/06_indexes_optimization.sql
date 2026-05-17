-- ============================================================================
-- Banking Management System — Indexes & Query Optimization
-- This file does three things:
--   1. Adds a small number of composite / covering indexes beyond those
--      already declared in 01_create_database.sql, targeted at the
--      slowest reporting queries identified during testing.
--   2. Provides paired EXPLAIN queries that demonstrate the impact of
--      each new index — run before and after CREATE INDEX to see the
--      improvement.
--   3. Documents the reasoning for each index in inline comments so the
--      analysis section of the report can quote them directly.
--
-- HOW TO USE THIS FILE FOR THE REPORT (Section C4 — Analysis):
--   a. Run the BEFORE EXPLAIN block first, screenshot the result.
--   b. Run the CREATE INDEX block.
--   c. Run the AFTER EXPLAIN block, screenshot the result.
--   d. Paste the two screenshots side-by-side in the report and refer
--      to the "rows" and "type" columns to discuss the improvement.
-- ============================================================================

USE banking_system;

-- ----------------------------------------------------------------------------
-- BEFORE-AFTER PAIR 1
-- Query: "Get the last 50 transactions for one account, newest first."
-- This is the core workload behind the account-statement screen.
-- ----------------------------------------------------------------------------

-- BEFORE  (composite index idx_tx_acc_date already exists from schema; to
-- demonstrate the impact we temporarily drop it and rerun the same query):
ALTER TABLE transactions DROP INDEX idx_tx_acc_date;

EXPLAIN
SELECT transaction_id, transaction_type, amount, balance_after, transaction_date
FROM transactions
WHERE account_id = 100
ORDER BY transaction_date DESC
LIMIT 50;
-- Expected pre-index outcome: type=ref on idx_tx_account, ORDER BY needs a
-- filesort; the larger the per-account history, the worse the sort gets.
-- Look at the "Extra" column for "Using filesort".

-- AFTER  (recreate the composite index):
CREATE INDEX idx_tx_acc_date ON transactions(account_id, transaction_date);

EXPLAIN
SELECT transaction_id, transaction_type, amount, balance_after, transaction_date
FROM transactions
WHERE account_id = 100
ORDER BY transaction_date DESC
LIMIT 50;
-- Expected post-index outcome: type=ref on idx_tx_acc_date, ORDER BY
-- satisfied by the index ordering — no filesort, fewer rows examined.
-- Note: with InnoDB and DESC ordering on a B-tree, MySQL 8 can use the
-- index in reverse for the LIMIT.

-- ----------------------------------------------------------------------------
-- BEFORE-AFTER PAIR 2
-- Query: "Daily transaction totals by type for the last month."
-- This powers v_daily_transaction_summary when filtered by date range.
-- ----------------------------------------------------------------------------

-- BEFORE
EXPLAIN
SELECT DATE(transaction_date) AS d, transaction_type, COUNT(*), SUM(amount)
FROM transactions
WHERE transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY DATE(transaction_date), transaction_type;
-- Expect: type=range on idx_tx_date but the GROUP BY still creates a
-- temporary table.

-- AFTER (composite index covering date + type so the GROUP BY can use it)
CREATE INDEX idx_tx_date_type ON transactions(transaction_date, transaction_type);

EXPLAIN
SELECT DATE(transaction_date) AS d, transaction_type, COUNT(*), SUM(amount)
FROM transactions
WHERE transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY DATE(transaction_date), transaction_type;
-- Expect: index used for both filter and grouping. "Using index" appears
-- in the Extra column for covered access.

-- ----------------------------------------------------------------------------
-- BEFORE-AFTER PAIR 3
-- Query: "Find all overdue loan payments for the dashboard."
-- ----------------------------------------------------------------------------

-- BEFORE
EXPLAIN
SELECT payment_id, loan_id, scheduled_date, amount, status
FROM loan_payments
WHERE status IN ('Scheduled','Late','Missed')
  AND scheduled_date < CURDATE()
  AND actual_date IS NULL;
-- Expect: type=ref on idx_pay_status, but the date filter still scans
-- those rows.

-- AFTER  (composite to push both predicates to the index)
CREATE INDEX idx_pay_status_sched ON loan_payments(status, scheduled_date);

EXPLAIN
SELECT payment_id, loan_id, scheduled_date, amount, status
FROM loan_payments
WHERE status IN ('Scheduled','Late','Missed')
  AND scheduled_date < CURDATE()
  AND actual_date IS NULL;

-- ----------------------------------------------------------------------------
-- BEFORE-AFTER PAIR 4
-- Query: "Top customers in Hanoi by balance."
-- ----------------------------------------------------------------------------

-- BEFORE  (no compound index on city + status path for accounts.customer_id
-- → customers.city, MySQL must join then filter)
EXPLAIN
SELECT c.full_name, c.city, SUM(a.balance) AS bal
FROM customers c
JOIN accounts  a ON c.customer_id = a.customer_id
WHERE c.city = 'Hanoi'
  AND a.status = 'Active'
GROUP BY c.customer_id
ORDER BY bal DESC
LIMIT 20;

-- AFTER  (cover the join's filter side with a compound index)
CREATE INDEX idx_acc_cust_status ON accounts(customer_id, status);

EXPLAIN
SELECT c.full_name, c.city, SUM(a.balance) AS bal
FROM customers c
JOIN accounts  a ON c.customer_id = a.customer_id
WHERE c.city = 'Hanoi'
  AND a.status = 'Active'
GROUP BY c.customer_id
ORDER BY bal DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- INDEX INVENTORY  —  what we end up with after this script
-- Run this to populate the index list for the report's Appendix.
-- ----------------------------------------------------------------------------
SELECT TABLE_NAME, INDEX_NAME,
       GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns,
       NON_UNIQUE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'banking_system'
GROUP BY TABLE_NAME, INDEX_NAME, NON_UNIQUE
ORDER BY TABLE_NAME, INDEX_NAME;

-- ============================================================================
-- End of indexes & optimization
-- ============================================================================
SHOW TRIGGERS FROM banking_system;
SHOW FULL TABLES IN banking_system WHERE Table_type = 'VIEW';