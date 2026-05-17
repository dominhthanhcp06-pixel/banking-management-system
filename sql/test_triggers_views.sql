-- ============================================================================
-- Test Script — Triggers and Views
-- Verifies that triggers fire correctly and views return sensible data.
-- Run after 04_triggers.sql and 05_views.sql are installed.
-- ============================================================================

USE banking_system;

-- ----------------------------------------------------------------------------
-- TRIGGER TESTS
-- ----------------------------------------------------------------------------

-- T-1  trg_customers_after_insert: insert a new customer and verify audit row
INSERT INTO customers (cust_code, full_name, gender, date_of_birth,
                       phone, email, address, city, register_date, credit_score)
VALUES ('TESTCUST01', 'Test Customer A', 'Female', '1990-01-01',
        '0900000001', 'testa@example.com', '1 Test St', 'Hanoi',
        CURDATE(), 700);

SELECT log_id, table_name, operation_type, record_id, new_values, changed_at
FROM audit_log
WHERE table_name = 'customers'
ORDER BY log_id DESC
LIMIT 1;
-- Expected: 1 row with operation_type='INSERT' and JSON of the new customer.

-- T-2  trg_customers_after_update: update phone, verify old/new captured
UPDATE customers SET phone = '0900000999' WHERE cust_code = 'TESTCUST01';

SELECT log_id, operation_type, old_values, new_values
FROM audit_log
WHERE table_name = 'customers'
ORDER BY log_id DESC
LIMIT 1;
-- Expected: UPDATE row whose old_values.phone = '0900000001' and new_values.phone = '0900000999'.

-- T-3  trg_transactions_large_amount: a 60 M VND deposit fires the SUSPICIOUS flag
-- (Pick an active account)
SET @acc := (SELECT account_id FROM accounts WHERE status='Active' LIMIT 1);
CALL sp_Deposit(@acc, 60000000, 1, 'Test large deposit (should flag SUSPICIOUS)');

SELECT log_id, table_name, operation_type, record_id, new_values
FROM audit_log
WHERE table_name = 'SUSPICIOUS_ACTIVITY'
ORDER BY log_id DESC
LIMIT 1;
-- Expected: 1 row with new_values.flag = 'LARGE_AMOUNT'.

-- T-4  trg_accounts_before_update: defense-in-depth blocks raw-SQL bypass
-- This UPDATE bypasses sp_Withdrawal. The trigger should reject it.
-- (Uncomment to see the rejection.)
-- UPDATE accounts SET balance = 0 WHERE account_id = @acc;
-- Expected error: "Trigger guard: balance update would violate minimum balance..."

-- ----------------------------------------------------------------------------
-- VIEW TESTS
-- ----------------------------------------------------------------------------

-- V-1  v_customer_summary
SELECT * FROM v_customer_summary
ORDER BY total_balance DESC
LIMIT 10;

-- V-2  v_branch_performance
SELECT * FROM v_branch_performance
ORDER BY total_deposits DESC;

-- V-3  v_daily_transaction_summary
SELECT * FROM v_daily_transaction_summary
WHERE txn_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
ORDER BY txn_date DESC, transaction_type;

-- V-4  v_loan_portfolio (first 10 active loans)
SELECT loan_id, loan_code, customer_name, loan_amount, interest_rate,
       remaining_balance, paid_count, late_count, missed_count
FROM v_loan_portfolio
WHERE status = 'Active'
ORDER BY loan_amount DESC
LIMIT 10;

-- V-5  v_top_customers
SELECT * FROM v_top_customers LIMIT 10;

-- V-6  v_overdue_loans
SELECT * FROM v_overdue_loans
ORDER BY days_overdue DESC
LIMIT 20;

-- V-7  v_transaction_audit_trail
SELECT transaction_id, transaction_date, transaction_type, amount,
       account_number, customer_name, processed_by, branch_name
FROM v_transaction_audit_trail
ORDER BY transaction_date DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- CLEANUP — remove the test customer (will also trigger trg_customers_after_delete)
-- ----------------------------------------------------------------------------
-- DELETE FROM customers WHERE cust_code = 'TESTCUST01';
-- (Uncomment if you want to test the delete trigger too. Note: the customer
-- has no accounts or loans so this is safe.)

-- ============================================================================

SELECT log_id, table_name, operation_type, record_id, new_values, changed_at
FROM audit_log
ORDER BY log_id DESC
LIMIT 5;

SELECT log_id, table_name, record_id, new_values
FROM audit_log
WHERE table_name = 'SUSPICIOUS_ACTIVITY';

SELECT * FROM v_customer_summary
ORDER BY total_balance DESC
LIMIT 10;
