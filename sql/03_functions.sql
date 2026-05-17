-- ============================================================================
-- Banking Management System — User-Defined Functions
-- Pure read-only / deterministic computations callable in SELECT, WHERE, etc.
--   fn_CalculateEMI                 — equated monthly installment
--   fn_GetCustomerTotalBalance      — sum of active balances per customer
--   fn_CheckSufficientBalance       — minimum-balance compliance check
--   fn_CalculateMonthlyInterest     — monthly interest for an account
--   fn_GetAccountAge                — days since account opened
--   fn_GetLoanRemainingBalance      — outstanding principal on a loan
-- ============================================================================

USE banking_system;

DROP FUNCTION IF EXISTS fn_CalculateEMI;
DROP FUNCTION IF EXISTS fn_GetCustomerTotalBalance;
DROP FUNCTION IF EXISTS fn_CheckSufficientBalance;
DROP FUNCTION IF EXISTS fn_CalculateMonthlyInterest;
DROP FUNCTION IF EXISTS fn_GetAccountAge;
DROP FUNCTION IF EXISTS fn_GetLoanRemainingBalance;

DELIMITER //

-- ----------------------------------------------------------------------------
-- fn_CalculateEMI
-- Standard amortization formula:  EMI = P*r*(1+r)^n / ((1+r)^n - 1)
-- where P = principal, r = monthly rate, n = months.
-- DETERMINISTIC + NO SQL → safe to use in WHERE clauses with index.
-- ----------------------------------------------------------------------------
CREATE FUNCTION fn_CalculateEMI(
    p_principal    DECIMAL(15,2),
    p_annual_rate  DECIMAL(5,4),
    p_term_months  INT
) RETURNS DECIMAL(15,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_monthly_rate DECIMAL(10,8);
    SET v_monthly_rate = p_annual_rate / 12.0;
    RETURN ROUND(
        p_principal * v_monthly_rate * POW(1 + v_monthly_rate, p_term_months) /
        (POW(1 + v_monthly_rate, p_term_months) - 1),
        2
    );
END //

-- ----------------------------------------------------------------------------
-- fn_GetCustomerTotalBalance
-- Sums balances across all active accounts of a customer.
-- ----------------------------------------------------------------------------
CREATE FUNCTION fn_GetCustomerTotalBalance(p_customer_id INT)
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(15,2);
    SELECT COALESCE(SUM(balance), 0) INTO v_total
    FROM accounts
    WHERE customer_id = p_customer_id AND status = 'Active';
    RETURN v_total;
END //

-- ----------------------------------------------------------------------------
-- fn_CheckSufficientBalance
-- Returns TRUE if a withdrawal of p_amount from the account would leave the
-- balance >= the type's minimum balance.
-- ----------------------------------------------------------------------------
CREATE FUNCTION fn_CheckSufficientBalance(
    p_account_id INT,
    p_amount     DECIMAL(15,2)
) RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_balance     DECIMAL(15,2);
    DECLARE v_min_balance DECIMAL(12,2);

    SELECT a.balance, at.min_balance
      INTO v_balance, v_min_balance
    FROM accounts a
    JOIN account_types at ON a.type_id = at.type_id
    WHERE a.account_id = p_account_id;

    IF v_balance IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN (v_balance - p_amount) >= v_min_balance;
END //

-- ----------------------------------------------------------------------------
-- fn_CalculateMonthlyInterest
-- Per-account monthly interest = balance * annual_rate / 12.
-- ----------------------------------------------------------------------------
CREATE FUNCTION fn_CalculateMonthlyInterest(p_account_id INT)
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_interest DECIMAL(15,2);
    SELECT ROUND(a.balance * at.interest_rate / 12.0, 2)
      INTO v_interest
    FROM accounts a
    JOIN account_types at ON a.type_id = at.type_id
    WHERE a.account_id = p_account_id;
    RETURN COALESCE(v_interest, 0);
END //

-- ----------------------------------------------------------------------------
-- fn_GetAccountAge — in days
-- ----------------------------------------------------------------------------
CREATE FUNCTION fn_GetAccountAge(p_account_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_days INT;
    SELECT DATEDIFF(CURDATE(), open_date)
      INTO v_days
    FROM accounts
    WHERE account_id = p_account_id;
    RETURN COALESCE(v_days, 0);
END //

-- ----------------------------------------------------------------------------
-- fn_GetLoanRemainingBalance
-- Outstanding principal = sum of principal portions of unpaid scheduled rows.
-- ----------------------------------------------------------------------------
CREATE FUNCTION fn_GetLoanRemainingBalance(p_loan_id INT)
RETURNS DECIMAL(15,2)
READS SQL DATA
BEGIN
    DECLARE v_remaining DECIMAL(15,2);
    SELECT COALESCE(SUM(principal), 0)
      INTO v_remaining
    FROM loan_payments
    WHERE loan_id = p_loan_id
      AND status IN ('Scheduled','Late','Missed');
    RETURN v_remaining;
END //

DELIMITER ;

-- ============================================================================
-- End of functions
-- ============================================================================
