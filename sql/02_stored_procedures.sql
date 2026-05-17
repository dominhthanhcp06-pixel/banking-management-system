-- ============================================================================
-- Banking Management System — Stored Procedures
-- Covers all transactional and lifecycle operations:
--   sp_OpenAccount, sp_CloseAccount, sp_FreezeAccount, sp_UnfreezeAccount
--   sp_Deposit, sp_Withdrawal, sp_Transfer
--   sp_OriginateLoan, sp_RecordLoanPayment
--   sp_IssueCard, sp_BlockCard
--   sp_ApplyMonthlyInterest
-- ============================================================================

USE banking_system;

DROP PROCEDURE IF EXISTS sp_OpenAccount;
DROP PROCEDURE IF EXISTS sp_CloseAccount;
DROP PROCEDURE IF EXISTS sp_FreezeAccount;
DROP PROCEDURE IF EXISTS sp_UnfreezeAccount;
DROP PROCEDURE IF EXISTS sp_Deposit;
DROP PROCEDURE IF EXISTS sp_Withdrawal;
DROP PROCEDURE IF EXISTS sp_Transfer;
DROP PROCEDURE IF EXISTS sp_OriginateLoan;
DROP PROCEDURE IF EXISTS sp_RecordLoanPayment;
DROP PROCEDURE IF EXISTS sp_IssueCard;
DROP PROCEDURE IF EXISTS sp_BlockCard;
DROP PROCEDURE IF EXISTS sp_ApplyMonthlyInterest;

DELIMITER //

-- ----------------------------------------------------------------------------
-- sp_OpenAccount
-- Opens a new account for an existing customer with optional initial deposit.
-- Validates customer existence, type validity, and minimum-balance compliance.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_OpenAccount(
    IN  p_customer_id      INT,
    IN  p_type_id          INT,
    IN  p_branch_id        INT,
    IN  p_initial_deposit  DECIMAL(15,2),
    OUT p_account_id       INT
)
BEGIN
    DECLARE v_account_number VARCHAR(20);
    DECLARE v_min_balance    DECIMAL(12,2);
    DECLARE v_customer_count INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_customer_count
    FROM customers WHERE customer_id = p_customer_id;
    IF v_customer_count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer does not exist';
    END IF;

    SELECT min_balance INTO v_min_balance
    FROM account_types WHERE type_id = p_type_id;
    IF v_min_balance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid account type';
    END IF;

    IF p_initial_deposit < v_min_balance THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Initial deposit below minimum balance for this account type';
    END IF;

    -- 14-digit account number: 8-digit zero-padded customer_id + 6-digit random
    SET v_account_number = CONCAT(
        LPAD(p_customer_id, 8, '0'),
        LPAD(FLOOR(RAND() * 1000000), 6, '0')
    );

    INSERT INTO accounts (account_number, customer_id, type_id, branch_id, balance, open_date)
    VALUES (v_account_number, p_customer_id, p_type_id, p_branch_id, p_initial_deposit, CURDATE());

    SET p_account_id = LAST_INSERT_ID();

    IF p_initial_deposit > 0 THEN
        INSERT INTO transactions
            (account_id, transaction_type, amount, balance_after, description)
        VALUES
            (p_account_id, 'Deposit', p_initial_deposit, p_initial_deposit,
             'Initial deposit at account opening');
    END IF;

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- sp_Deposit
-- Atomically credits an active account and records the transaction.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_Deposit(
    IN p_account_id  INT,
    IN p_amount      DECIMAL(15,2),
    IN p_employee_id INT,
    IN p_description VARCHAR(255)
)
BEGIN
    DECLARE v_status      ENUM('Active','Frozen','Closed');
    DECLARE v_new_balance DECIMAL(15,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deposit amount must be positive';
    END IF;

    START TRANSACTION;

    SELECT status, balance + p_amount
      INTO v_status, v_new_balance
    FROM accounts
    WHERE account_id = p_account_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF v_status <> 'Active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is not Active';
    END IF;

    UPDATE accounts SET balance = v_new_balance WHERE account_id = p_account_id;

    INSERT INTO transactions
        (account_id, transaction_type, amount, balance_after, employee_id, description)
    VALUES
        (p_account_id, 'Deposit', p_amount, v_new_balance, p_employee_id, p_description);

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- sp_Withdrawal
-- Atomically debits an active account, enforcing minimum-balance rule.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_Withdrawal(
    IN p_account_id  INT,
    IN p_amount      DECIMAL(15,2),
    IN p_employee_id INT,
    IN p_description VARCHAR(255)
)
BEGIN
    DECLARE v_balance     DECIMAL(15,2);
    DECLARE v_status      ENUM('Active','Frozen','Closed');
    DECLARE v_min_balance DECIMAL(12,2);
    DECLARE v_new_balance DECIMAL(15,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Withdrawal amount must be positive';
    END IF;

    START TRANSACTION;

    SELECT a.balance, a.status, at.min_balance
      INTO v_balance, v_status, v_min_balance
    FROM accounts a
    JOIN account_types at ON a.type_id = at.type_id
    WHERE a.account_id = p_account_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF v_status <> 'Active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is not Active';
    END IF;

    SET v_new_balance = v_balance - p_amount;
    IF v_new_balance < v_min_balance THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient funds: minimum-balance rule would be violated';
    END IF;

    UPDATE accounts SET balance = v_new_balance WHERE account_id = p_account_id;

    INSERT INTO transactions
        (account_id, transaction_type, amount, balance_after, employee_id, description)
    VALUES
        (p_account_id, 'Withdrawal', p_amount, v_new_balance, p_employee_id, p_description);

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- sp_Transfer
-- Atomic dual-leg transfer between two accounts. Locks rows in deterministic
-- order (smaller id first) to prevent deadlocks under concurrent transfers.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_Transfer(
    IN p_from_account INT,
    IN p_to_account   INT,
    IN p_amount       DECIMAL(15,2),
    IN p_employee_id  INT,
    IN p_description  VARCHAR(255)
)
BEGIN
    DECLARE v_from_balance DECIMAL(15,2);
    DECLARE v_to_balance   DECIMAL(15,2);
    DECLARE v_from_status  ENUM('Active','Frozen','Closed');
    DECLARE v_to_status    ENUM('Active','Frozen','Closed');
    DECLARE v_from_min     DECIMAL(12,2);
    DECLARE v_new_from     DECIMAL(15,2);
    DECLARE v_new_to       DECIMAL(15,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    IF p_from_account = p_to_account THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot transfer to the same account';
    END IF;
    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer amount must be positive';
    END IF;

    START TRANSACTION;

    -- Lock rows in deterministic order to avoid deadlock
    IF p_from_account < p_to_account THEN
        SELECT a.balance, a.status, at.min_balance
          INTO v_from_balance, v_from_status, v_from_min
        FROM accounts a JOIN account_types at ON a.type_id = at.type_id
        WHERE a.account_id = p_from_account FOR UPDATE;

        SELECT balance, status INTO v_to_balance, v_to_status
        FROM accounts WHERE account_id = p_to_account FOR UPDATE;
    ELSE
        SELECT balance, status INTO v_to_balance, v_to_status
        FROM accounts WHERE account_id = p_to_account FOR UPDATE;

        SELECT a.balance, a.status, at.min_balance
          INTO v_from_balance, v_from_status, v_from_min
        FROM accounts a JOIN account_types at ON a.type_id = at.type_id
        WHERE a.account_id = p_from_account FOR UPDATE;
    END IF;

    IF v_from_status IS NULL OR v_to_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'One or both accounts do not exist';
    END IF;
    IF v_from_status <> 'Active' OR v_to_status <> 'Active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Both accounts must be Active for transfer';
    END IF;

    SET v_new_from = v_from_balance - p_amount;
    SET v_new_to   = v_to_balance   + p_amount;

    IF v_new_from < v_from_min THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient funds in source account';
    END IF;

    UPDATE accounts SET balance = v_new_from WHERE account_id = p_from_account;
    UPDATE accounts SET balance = v_new_to   WHERE account_id = p_to_account;

    INSERT INTO transactions
        (account_id, related_account_id, transaction_type, amount, balance_after, employee_id, description)
    VALUES
        (p_from_account, p_to_account, 'Transfer_Out', p_amount, v_new_from, p_employee_id, p_description),
        (p_to_account,   p_from_account, 'Transfer_In',  p_amount, v_new_to,   p_employee_id, p_description);

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- sp_CloseAccount  —  requires zero balance
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_CloseAccount(IN p_account_id INT)
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_status  ENUM('Active','Frozen','Closed');

    SELECT balance, status INTO v_balance, v_status
    FROM accounts WHERE account_id = p_account_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF v_status = 'Closed' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is already closed';
    END IF;
    IF v_balance <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot close account with non-zero balance';
    END IF;

    UPDATE accounts SET status = 'Closed', close_date = CURDATE()
    WHERE account_id = p_account_id;
END //

-- ----------------------------------------------------------------------------
-- sp_FreezeAccount / sp_UnfreezeAccount
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_FreezeAccount(IN p_account_id INT)
BEGIN
    UPDATE accounts SET status = 'Frozen'
    WHERE account_id = p_account_id AND status = 'Active';
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account not found or not in Active state';
    END IF;
END //

CREATE PROCEDURE sp_UnfreezeAccount(IN p_account_id INT)
BEGIN
    UPDATE accounts SET status = 'Active'
    WHERE account_id = p_account_id AND status = 'Frozen';
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account not found or not in Frozen state';
    END IF;
END //

-- ----------------------------------------------------------------------------
-- sp_OriginateLoan
-- Creates a loan and its full amortization schedule (equal monthly installment).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_OriginateLoan(
    IN  p_customer_id    INT,
    IN  p_loan_amount    DECIMAL(15,2),
    IN  p_interest_rate  DECIMAL(5,4),
    IN  p_term_months    INT,
    IN  p_branch_id      INT,
    IN  p_employee_id    INT,
    OUT p_loan_id        INT
)
BEGIN
    DECLARE v_loan_code     VARCHAR(15);
    DECLARE v_emi           DECIMAL(15,2);
    DECLARE v_monthly_rate  DECIMAL(10,8);
    DECLARE v_balance       DECIMAL(15,2);
    DECLARE v_interest      DECIMAL(15,2);
    DECLARE v_principal     DECIMAL(15,2);
    DECLARE i               INT DEFAULT 1;
    DECLARE v_start_date    DATE DEFAULT CURDATE();
    DECLARE v_end_date      DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    IF p_loan_amount   <= 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'loan_amount must be positive';   END IF;
    IF p_interest_rate <= 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'interest_rate must be positive'; END IF;
    IF p_term_months   <= 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'term_months must be positive';   END IF;

    START TRANSACTION;

    SET v_end_date     = DATE_ADD(v_start_date, INTERVAL p_term_months MONTH);
    SET v_monthly_rate = p_interest_rate / 12.0;
    SET v_emi = ROUND(
        p_loan_amount * v_monthly_rate * POW(1 + v_monthly_rate, p_term_months) /
        (POW(1 + v_monthly_rate, p_term_months) - 1),
        2
    );

    SET v_loan_code = CONCAT('LN', LPAD(FLOOR(RAND() * 1000000), 6, '0'));

    INSERT INTO loans
        (loan_code, customer_id, loan_amount, interest_rate, term_months,
         start_date, end_date, branch_id, employee_id)
    VALUES
        (v_loan_code, p_customer_id, p_loan_amount, p_interest_rate, p_term_months,
         v_start_date, v_end_date, p_branch_id, p_employee_id);

    SET p_loan_id = LAST_INSERT_ID();

    -- Build amortization schedule
    SET v_balance = p_loan_amount;
    WHILE i <= p_term_months DO
        SET v_interest  = ROUND(v_balance * v_monthly_rate, 2);
        SET v_principal = v_emi - v_interest;
        SET v_balance   = v_balance - v_principal;

        INSERT INTO loan_payments (loan_id, scheduled_date, amount, principal, interest)
        VALUES (p_loan_id, DATE_ADD(v_start_date, INTERVAL i MONTH),
                v_emi, v_principal, v_interest);

        SET i = i + 1;
    END WHILE;

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- sp_RecordLoanPayment
-- Marks a scheduled payment as Paid (or Late if past due).
-- Auto-closes the loan when no remaining payments.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_RecordLoanPayment(
    IN p_payment_id  INT,
    IN p_actual_date DATE
)
BEGIN
    DECLARE v_loan_id   INT;
    DECLARE v_status    ENUM('Scheduled','Paid','Late','Missed');
    DECLARE v_remaining INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;

    SELECT loan_id, status INTO v_loan_id, v_status
    FROM loan_payments WHERE payment_id = p_payment_id FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment record not found';
    END IF;
    IF v_status = 'Paid' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment already recorded';
    END IF;

    UPDATE loan_payments
    SET actual_date = p_actual_date,
        status = CASE WHEN p_actual_date > scheduled_date THEN 'Late' ELSE 'Paid' END
    WHERE payment_id = p_payment_id;

    -- If all payments settled, mark the loan paid off
    SELECT COUNT(*) INTO v_remaining
    FROM loan_payments
    WHERE loan_id = v_loan_id AND status IN ('Scheduled','Missed');

    IF v_remaining = 0 THEN
        UPDATE loans SET status = 'PaidOff' WHERE loan_id = v_loan_id;
    END IF;

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- sp_IssueCard / sp_BlockCard
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_IssueCard(
    IN  p_account_id INT,
    IN  p_card_type  ENUM('ATM','Debit','Credit'),
    IN  p_pin        VARCHAR(10),
    OUT p_card_id    INT
)
BEGIN
    DECLARE v_card_number VARCHAR(20);
    DECLARE v_status      ENUM('Active','Frozen','Closed');

    SELECT status INTO v_status FROM accounts WHERE account_id = p_account_id;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF v_status <> 'Active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot issue card on a non-active account';
    END IF;

    SET v_card_number = CONCAT('4', LPAD(FLOOR(RAND() * 999999999999999), 15, '0'));

    INSERT INTO cards (card_number, account_id, card_type, issue_date, expiry_date, pin_hash)
    VALUES (v_card_number, p_account_id, p_card_type,
            CURDATE(), DATE_ADD(CURDATE(), INTERVAL 5 YEAR),
            SHA2(p_pin, 256));

    SET p_card_id = LAST_INSERT_ID();
END //

CREATE PROCEDURE sp_BlockCard(IN p_card_id INT)
BEGIN
    UPDATE cards SET status = 'Blocked'
    WHERE card_id = p_card_id AND status = 'Active';
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Card not found or not in Active state';
    END IF;
END //

-- ----------------------------------------------------------------------------
-- sp_ApplyMonthlyInterest
-- Batch operation: credits monthly interest to every active interest-bearing
-- account. Demonstrates cursor-based row iteration.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_ApplyMonthlyInterest()
BEGIN
    DECLARE v_done           INT DEFAULT FALSE;
    DECLARE v_account_id     INT;
    DECLARE v_balance        DECIMAL(15,2);
    DECLARE v_rate           DECIMAL(5,4);
    DECLARE v_interest       DECIMAL(15,2);
    DECLARE v_credited_count INT DEFAULT 0;

    DECLARE cur CURSOR FOR
        SELECT a.account_id, a.balance, at.interest_rate
        FROM accounts a
        JOIN account_types at ON a.type_id = at.type_id
        WHERE a.status = 'Active'
          AND at.interest_rate > 0
          AND at.type_name IN ('Savings','Premium Savings','Student');

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    OPEN cur;
    interest_loop: LOOP
        FETCH cur INTO v_account_id, v_balance, v_rate;
        IF v_done THEN LEAVE interest_loop; END IF;

        SET v_interest = ROUND(v_balance * v_rate / 12.0, 2);
        IF v_interest > 0 THEN
            UPDATE accounts SET balance = balance + v_interest
            WHERE account_id = v_account_id;

            INSERT INTO transactions
                (account_id, transaction_type, amount, balance_after, description)
            VALUES
                (v_account_id, 'Interest', v_interest, v_balance + v_interest,
                 'Monthly interest accrual');

            SET v_credited_count = v_credited_count + 1;
        END IF;
    END LOOP;
    CLOSE cur;

    SELECT v_credited_count AS accounts_credited;
END //

DELIMITER ;

-- ============================================================================
-- End of stored procedures
-- ============================================================================
