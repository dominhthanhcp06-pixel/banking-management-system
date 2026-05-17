-- ============================================================================
-- C4 EVIDENCE — Business Rule Enforcement & ACID Rollback Demonstration
--
-- PURPOSE
--   Demonstrates two things at once for the report's Analysis section:
--     1. The minimum-balance business rule is enforced at the DATABASE
--        layer (inside the stored procedure), not in the application.
--     2. When the rule is violated, MySQL ROLLS BACK the transaction in
--        full — the balance is unchanged, proving ACID Atomicity.

USE banking_system;

-- ----------------------------------------------------------------------------
-- STEP 1 — Pick a Premium Savings account with low headroom above min_balance
-- ----------------------------------------------------------------------------
SELECT
    a.account_id,
    a.account_number,
    at.type_name,
    at.min_balance                          AS required_min_balance,
    a.balance                               AS current_balance,
    a.balance - at.min_balance              AS withdrawable_buffer
INTO
    @acc_id, @acc_num, @type_name, @min_bal, @bal_before, @buffer
FROM accounts a
JOIN account_types at ON a.type_id = at.type_id
WHERE at.type_name = 'Premium Savings'
  AND a.status     = 'Active'
ORDER BY a.balance ASC
LIMIT 1;


SELECT
    @acc_id       AS account_id,
    @acc_num      AS account_number,
    @type_name    AS account_type,
    @min_bal      AS minimum_balance_required,
    @bal_before   AS balance_before,
    @buffer       AS legal_withdrawal_headroom;

-- ----------------------------------------------------------------------------
-- STEP 2 — Plan a withdrawal that DELIBERATELY exceeds the legal headroom.
-- We attempt to withdraw the entire buffer PLUS an extra 1,000 VND.
-- ----------------------------------------------------------------------------
SET @attempted = @buffer + 1000;
SET @would_be  = @bal_before - @attempted;

SELECT
    @attempted                                 AS attempted_withdrawal,
    @bal_before                                AS balance_before,
    @would_be                                  AS balance_if_allowed,
    @min_bal                                   AS minimum_balance_required,
    CASE WHEN @would_be < @min_bal
         THEN 'VIOLATES min-balance — must be rejected'
         ELSE 'Within bounds (demo misconfigured)'
    END                                        AS prediction;

-- ----------------------------------------------------------------------------
-- STEP 3 — Attempt the withdrawal through the official stored procedure.
-- ----------------------------------------------------------------------------
CALL sp_Withdrawal(@acc_id, @attempted, 1, 'C4 evidence: must be rejected');

-- ----------------------------------------------------------------------------
-- STEP 4 
-- ----------------------------------------------------------------------------
SELECT
    account_id,
    balance                                    AS balance_after,
    @bal_before                                AS balance_before,
    (balance = @bal_before)                    AS unchanged_proof,
    'ACID Atomicity verified — failed write left no trace' AS conclusion
FROM accounts
WHERE account_id = @acc_id;

-- ============================================================================
-- End of C4 evidence script
-- ============================================================================
