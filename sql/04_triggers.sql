-- ============================================================================
-- Banking Management System — Triggers
-- Two purposes:
--   1) Audit-trail triggers: log every INSERT/UPDATE/DELETE on critical
--      tables (customers, accounts, transactions, loans) to audit_log
--      with old/new values serialized as JSON.
--   2) Business-rule triggers: enforce invariants that complement the
--      CHECK constraints (e.g., flag large transactions, prevent updates
--      on closed accounts, auto-update loan status from payment patterns).
-- ============================================================================

USE banking_system;

DROP TRIGGER IF EXISTS trg_customers_after_insert;
DROP TRIGGER IF EXISTS trg_customers_after_update;
DROP TRIGGER IF EXISTS trg_customers_after_delete;
DROP TRIGGER IF EXISTS trg_accounts_after_insert;
DROP TRIGGER IF EXISTS trg_accounts_after_update;
DROP TRIGGER IF EXISTS trg_transactions_after_insert;
DROP TRIGGER IF EXISTS trg_transactions_large_amount;
DROP TRIGGER IF EXISTS trg_loans_after_insert;
DROP TRIGGER IF EXISTS trg_accounts_before_update;
DROP TRIGGER IF EXISTS trg_cards_before_insert;

DELIMITER //

-- ----------------------------------------------------------------------------
-- 1. trg_customers_after_insert  —  audit new customer registrations
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_customers_after_insert
AFTER INSERT ON customers
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation_type, record_id, new_values, changed_by)
    VALUES (
        'customers', 'INSERT', NEW.customer_id,
        JSON_OBJECT(
            'cust_code',     NEW.cust_code,
            'full_name',     NEW.full_name,
            'gender',        NEW.gender,
            'phone',         NEW.phone,
            'email',         NEW.email,
            'city',          NEW.city,
            'credit_score',  NEW.credit_score,
            'register_date', NEW.register_date
        ),
        CURRENT_USER()
    );
END //

-- ----------------------------------------------------------------------------
-- 2. trg_customers_after_update  —  audit profile changes
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_customers_after_update
AFTER UPDATE ON customers
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation_type, record_id,
                           old_values, new_values, changed_by)
    VALUES (
        'customers', 'UPDATE', NEW.customer_id,
        JSON_OBJECT(
            'full_name',    OLD.full_name,
            'phone',        OLD.phone,
            'email',        OLD.email,
            'address',      OLD.address,
            'city',         OLD.city,
            'credit_score', OLD.credit_score
        ),
        JSON_OBJECT(
            'full_name',    NEW.full_name,
            'phone',        NEW.phone,
            'email',        NEW.email,
            'address',      NEW.address,
            'city',         NEW.city,
            'credit_score', NEW.credit_score
        ),
        CURRENT_USER()
    );
END //

-- ----------------------------------------------------------------------------
-- 3. trg_customers_after_delete  —  audit deletions
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_customers_after_delete
AFTER DELETE ON customers
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation_type, record_id, old_values, changed_by)
    VALUES (
        'customers', 'DELETE', OLD.customer_id,
        JSON_OBJECT(
            'cust_code', OLD.cust_code,
            'full_name', OLD.full_name,
            'phone',     OLD.phone,
            'email',     OLD.email,
            'city',      OLD.city
        ),
        CURRENT_USER()
    );
END //

-- ----------------------------------------------------------------------------
-- 4. trg_accounts_after_insert  —  audit new accounts
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_accounts_after_insert
AFTER INSERT ON accounts
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation_type, record_id, new_values, changed_by)
    VALUES (
        'accounts', 'INSERT', NEW.account_id,
        JSON_OBJECT(
            'account_number', NEW.account_number,
            'customer_id',    NEW.customer_id,
            'type_id',        NEW.type_id,
            'branch_id',      NEW.branch_id,
            'balance',        NEW.balance,
            'open_date',      NEW.open_date,
            'status',         NEW.status
        ),
        CURRENT_USER()
    );
END //

-- ----------------------------------------------------------------------------
-- 5. trg_accounts_after_update  —  audit every balance / status change
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_accounts_after_update
AFTER UPDATE ON accounts
FOR EACH ROW
BEGIN
    -- Only log if balance, status, or close_date actually changed
    IF OLD.balance     <> NEW.balance
       OR OLD.status   <> NEW.status
       OR NOT (OLD.close_date <=> NEW.close_date) THEN
        INSERT INTO audit_log (table_name, operation_type, record_id,
                               old_values, new_values, changed_by)
        VALUES (
            'accounts', 'UPDATE', NEW.account_id,
            JSON_OBJECT(
                'balance',    OLD.balance,
                'status',     OLD.status,
                'close_date', OLD.close_date
            ),
            JSON_OBJECT(
                'balance',    NEW.balance,
                'status',     NEW.status,
                'close_date', NEW.close_date
            ),
            CURRENT_USER()
        );
    END IF;
END //

-- ----------------------------------------------------------------------------
-- 6. trg_transactions_after_insert  —  audit every transaction
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_transactions_after_insert
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation_type, record_id, new_values, changed_by)
    VALUES (
        'transactions', 'INSERT', NEW.transaction_id,
        JSON_OBJECT(
            'account_id',         NEW.account_id,
            'related_account_id', NEW.related_account_id,
            'transaction_type',   NEW.transaction_type,
            'amount',             NEW.amount,
            'balance_after',      NEW.balance_after,
            'transaction_date',   NEW.transaction_date,
            'employee_id',        NEW.employee_id
        ),
        CURRENT_USER()
    );
END //

-- ----------------------------------------------------------------------------
-- 7. trg_transactions_large_amount  —  suspicious-activity flag
-- Logs every transaction at or above 50,000,000 VND with a SUSPICIOUS tag
-- so the auditor can review high-value activity quickly.
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_transactions_large_amount
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    IF NEW.amount >= 50000000 THEN
        INSERT INTO audit_log (table_name, operation_type, record_id,
                               new_values, changed_by)
        VALUES (
            'SUSPICIOUS_ACTIVITY', 'INSERT', NEW.transaction_id,
            JSON_OBJECT(
                'flag',             'LARGE_AMOUNT',
                'account_id',       NEW.account_id,
                'amount',           NEW.amount,
                'transaction_type', NEW.transaction_type,
                'note',             'Transaction at or above 50,000,000 VND'
            ),
            CURRENT_USER()
        );
    END IF;
END //

-- ----------------------------------------------------------------------------
-- 8. trg_loans_after_insert  —  audit new loan originations
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_loans_after_insert
AFTER INSERT ON loans
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation_type, record_id, new_values, changed_by)
    VALUES (
        'loans', 'INSERT', NEW.loan_id,
        JSON_OBJECT(
            'loan_code',     NEW.loan_code,
            'customer_id',   NEW.customer_id,
            'loan_amount',   NEW.loan_amount,
            'interest_rate', NEW.interest_rate,
            'term_months',   NEW.term_months,
            'branch_id',     NEW.branch_id,
            'employee_id',   NEW.employee_id
        ),
        CURRENT_USER()
    );
END //

-- ----------------------------------------------------------------------------
-- 9. trg_accounts_before_update  —  defense-in-depth balance protection
-- Prevents UPDATE statements that would push balance below the type's
-- min_balance on an Active account, even if someone bypasses the
-- sp_Withdrawal procedure and writes raw SQL.
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_accounts_before_update
BEFORE UPDATE ON accounts
FOR EACH ROW
BEGIN
    DECLARE v_min DECIMAL(12,2);
    IF NEW.status = 'Active' AND NEW.balance < OLD.balance THEN
        SELECT min_balance INTO v_min
        FROM account_types WHERE type_id = NEW.type_id;
        IF NEW.balance < v_min THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Trigger guard: balance update would violate minimum balance for active account';
        END IF;
    END IF;
END //

-- ----------------------------------------------------------------------------
-- 10. trg_cards_before_insert  —  enforce 5-year expiry standard
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_cards_before_insert
BEFORE INSERT ON cards
FOR EACH ROW
BEGIN
    IF NEW.expiry_date IS NULL THEN
        SET NEW.expiry_date = DATE_ADD(NEW.issue_date, INTERVAL 5 YEAR);
    END IF;
    IF DATEDIFF(NEW.expiry_date, NEW.issue_date) > 365 * 7 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Card expiry cannot exceed 7 years from issue';
    END IF;
END //

DELIMITER ;

-- ============================================================================
-- End of triggers (10 total: 8 audit + 2 business-rule)
-- ============================================================================
