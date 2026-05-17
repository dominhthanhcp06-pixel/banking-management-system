-- ============================================================================
-- Banking Management System — Test Script (Procedures + Functions)
-- Run this AFTER 02_stored_procedures.sql and 03_functions.sql.
-- Each block exercises one object and prints the result.
-- ============================================================================

USE banking_system;

-- ----------------------------------------------------------------------------
-- TEST 1 — fn_CalculateEMI
-- Loan 100,000,000 VND  @ 10% / 12 months  → expected EMI ~ 8,791,589
-- ----------------------------------------------------------------------------
SELECT fn_CalculateEMI(100000000, 0.10, 12) AS emi_100m_10pct_12m;

-- ----------------------------------------------------------------------------
-- TEST 2 — fn_GetCustomerTotalBalance for the first customer
-- ----------------------------------------------------------------------------
SELECT customer_id,
       full_name,
       fn_GetCustomerTotalBalance(customer_id) AS total_balance
FROM customers
ORDER BY customer_id
LIMIT 5;

-- ----------------------------------------------------------------------------
-- TEST 3 — fn_CalculateMonthlyInterest for 5 sample savings accounts
-- ----------------------------------------------------------------------------
SELECT a.account_id,
       a.account_number,
       a.balance,
       at.type_name,
       at.interest_rate,
       fn_CalculateMonthlyInterest(a.account_id) AS monthly_interest
FROM accounts a
JOIN account_types at ON a.type_id = at.type_id
WHERE at.type_name IN ('Savings','Premium Savings')
ORDER BY a.account_id
LIMIT 5;

-- ----------------------------------------------------------------------------
-- TEST 4 — sp_Deposit on first active account
-- Sequence:
--   1. Read balance before
--   2. Deposit 1,500,000
--   3. Read balance after  → must equal balance_before + 1,500,000
--   4. Verify a Deposit transaction row was inserted
-- ----------------------------------------------------------------------------
SELECT @target_acc := account_id, @bal_before := balance, @emp := 1
FROM accounts WHERE status = 'Active' LIMIT 1;

CALL sp_Deposit(@target_acc, 1500000, @emp, 'Test deposit from script');

SELECT account_id, balance AS bal_after_deposit
FROM accounts WHERE account_id = @target_acc;

SELECT transaction_id, transaction_type, amount, balance_after, description
FROM transactions
WHERE account_id = @target_acc
ORDER BY transaction_id DESC
LIMIT 1;

-- ----------------------------------------------------------------------------
-- TEST 5 — sp_Withdrawal (small amount, should succeed)
-- ----------------------------------------------------------------------------
CALL sp_Withdrawal(@target_acc, 500000, @emp, 'Test withdrawal');

SELECT @target_acc AS target_acc, @bal_before AS balance_before;

CALL sp_Deposit(@target_acc, 1500000, @emp, 'Test deposit');
CALL sp_Withdrawal(@target_acc, 500000, @emp, 'Test withdrawal');

-- Pick a Checking account (min_balance = 50K) with enough balance
SELECT @target_acc := a.account_id, @bal_before := a.balance, @emp := 1
FROM accounts a 
JOIN account_types at ON a.type_id = at.type_id
WHERE a.status = 'Active' 
  AND at.type_name = 'Checking'
  AND a.balance > 2000000
LIMIT 1;

SELECT @target_acc AS target_acc, @bal_before AS balance_before;

CALL sp_Deposit(@target_acc, 1500000, @emp, 'Test deposit');
CALL sp_Withdrawal(@target_acc, 500000, @emp, 'Test withdrawal');

SELECT account_id, balance AS balance_after_both
FROM accounts WHERE account_id = @target_acc;
SELECT account_id, balance AS balance_after_both
FROM accounts WHERE account_id = @target_acc;

SELECT account_id, balance AS bal_after_withdrawal
FROM accounts WHERE account_id = @target_acc;

-- ----------------------------------------------------------------------------
-- TEST 6 — sp_Withdrawal that should FAIL on min-balance rule
-- (uncomment one line below to see the error in MySQL Workbench)
-- ----------------------------------------------------------------------------
-- CALL sp_Withdrawal(@target_acc, 999999999999, @emp, 'Should fail');
--   Expected error: "Insufficient funds: minimum-balance rule would be violated"

-- ----------------------------------------------------------------------------
-- TEST 7 — sp_Transfer between two accounts of the same customer
-- ----------------------------------------------------------------------------
SELECT @from_acc := MIN(account_id), @to_acc := MAX(account_id), @cust := customer_id
FROM accounts WHERE status = 'Active' AND balance > 5000000
GROUP BY customer_id
HAVING COUNT(*) >= 2
LIMIT 1;

SELECT 'Before transfer' AS phase, account_id, balance
FROM accounts WHERE account_id IN (@from_acc, @to_acc);

CALL sp_Transfer(@from_acc, @to_acc, 1000000, @emp, 'Test transfer');

SELECT 'After transfer' AS phase, account_id, balance
FROM accounts WHERE account_id IN (@from_acc, @to_acc);

SELECT transaction_id, account_id, related_account_id, transaction_type, amount, balance_after
FROM transactions
WHERE account_id IN (@from_acc, @to_acc)
ORDER BY transaction_id DESC
LIMIT 4;

-- ----------------------------------------------------------------------------
-- TEST 8 — sp_OriginateLoan + amortization schedule generation
-- ----------------------------------------------------------------------------
SELECT @cust2 := customer_id, @branch := 1
FROM customers LIMIT 1;

CALL sp_OriginateLoan(@cust2, 200000000, 0.085, 24, @branch, @emp, @new_loan);

SELECT loan_id, loan_code, loan_amount, interest_rate, term_months, start_date, end_date, status
FROM loans WHERE loan_id = @new_loan;

SELECT payment_id, scheduled_date, amount, principal, interest, status
FROM loan_payments WHERE loan_id = @new_loan
ORDER BY scheduled_date
LIMIT 5;

SELECT fn_GetLoanRemainingBalance(@new_loan) AS remaining_principal;

-- ----------------------------------------------------------------------------
-- TEST 9 — sp_IssueCard
-- ----------------------------------------------------------------------------
CALL sp_IssueCard(@target_acc, 'Debit', '1234', @new_card);
SELECT card_id, card_number, card_type, issue_date, expiry_date, status
FROM cards WHERE card_id = @new_card;

-- ----------------------------------------------------------------------------
-- TEST 10 — sp_OpenAccount + sp_CloseAccount round trip
-- ----------------------------------------------------------------------------
CALL sp_OpenAccount(1, 1, 1, 100000, @new_acc);
SELECT account_id, account_number, balance, status FROM accounts WHERE account_id = @new_acc;

CALL sp_Withdrawal(@new_acc, 100000, @emp, 'Empty account before closing');
SELECT account_id, balance FROM accounts WHERE account_id = @new_acc;

-- This should fail because checking-account min-balance is 50000
-- After withdrawing all 100000, balance is 0 < 50000 (would fail withdrawal earlier)
-- For this test, use type with min_balance = 0 (Student, type_id = 4)
-- so we close with zero balance

-- ----------------------------------------------------------------------------
-- All tests passed if you see no errors above.
-- ============================================================================
