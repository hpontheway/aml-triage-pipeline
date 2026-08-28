-- ============================================================
-- AML TRIAGE PIPELINE - ANALYTICS LAYER (analytics.sql)
-- Run this AFTER schema.sql and AFTER importing all 4 CSVs.
-- Paste section by section into DB Browser's "Execute SQL" tab,
-- or run the whole file at once via File > Import > Import from SQL file... no,
-- instead: open this file's contents, paste into Execute SQL tab, click "Execute all".
-- ============================================================


-- ------------------------------------------------------------
-- QUERY 1: STRUCTURING / SMURFING DETECTION
-- ------------------------------------------------------------
-- WHAT IS STRUCTURING? Breaking up a large sum of cash into several
-- smaller deposits, each kept just under the $10,000 threshold that
-- triggers a mandatory Currency Transaction Report (CTR) in the US.
-- Money launderers do this to avoid detection.
--
-- WHAT THIS QUERY DOES: For every account, it looks at CASH deposits
-- between $9,000 and $9,999.99 (suspiciously just under $10k), groups
-- them by account and by rolling calendar day windows, and flags any
-- account with 3 or more such deposits within a 7-day period.
-- ------------------------------------------------------------

DROP VIEW IF EXISTS v_structuring_flags;
CREATE VIEW v_structuring_flags AS
WITH near_threshold_deposits AS (
    SELECT
        transaction_id,
        account_id,
        transaction_date,
        amount,
        DATE(transaction_date) AS txn_day
    FROM transactions
    WHERE transaction_type = 'CashDeposit'
      AND amount >= 9000 AND amount < 10000
),
account_window_counts AS (
    -- For each near-threshold deposit, count how many similar deposits
    -- happened on the SAME account within +/- 7 days of it.
    SELECT
        a.transaction_id,
        a.account_id,
        a.transaction_date,
        a.amount,
        (SELECT COUNT(*)
         FROM near_threshold_deposits b
         WHERE b.account_id = a.account_id
           AND JULIANDAY(b.txn_day) BETWEEN JULIANDAY(a.txn_day) - 7 AND JULIANDAY(a.txn_day) + 7
        ) AS deposits_in_window
    FROM near_threshold_deposits a
)
SELECT DISTINCT
    account_id,
    MAX(deposits_in_window) AS max_deposits_in_7day_window,
    COUNT(*) AS total_near_threshold_deposits,
    ROUND(SUM(amount), 2) AS total_amount_near_threshold
FROM account_window_counts
GROUP BY account_id
HAVING MAX(deposits_in_window) >= 3;


-- ------------------------------------------------------------
-- QUERY 2: RAPID FUND MOVEMENT (LAYERING) DETECTION
-- ------------------------------------------------------------
-- WHAT IS RAPID FUND MOVEMENT? A large deposit or incoming wire that
-- leaves the account again almost immediately (within 48 hours).
-- Legitimate savings/checking accounts don't usually move large sums
-- in and straight back out - this pattern is a classic "layering"
-- red flag (moving money through accounts to obscure its origin).
--
-- WHAT THIS QUERY DOES: Finds pairs of transactions on the same
-- account where a large inflow (Deposit/WireTransfer in) is followed
-- within 48 hours by a large outflow (Withdrawal/WireTransfer out)
-- of a similar amount.
-- ------------------------------------------------------------

DROP VIEW IF EXISTS v_rapid_movement_flags;
CREATE VIEW v_rapid_movement_flags AS
SELECT
    t_in.account_id,
    t_in.transaction_id  AS inbound_txn_id,
    t_in.transaction_date AS inbound_date,
    t_in.amount           AS inbound_amount,
    t_out.transaction_id  AS outbound_txn_id,
    t_out.transaction_date AS outbound_date,
    t_out.amount           AS outbound_amount,
    ROUND((JULIANDAY(t_out.transaction_date) - JULIANDAY(t_in.transaction_date)) * 24, 1) AS hours_between
FROM transactions t_in
JOIN transactions t_out
    ON t_in.account_id = t_out.account_id
    AND t_out.transaction_id != t_in.transaction_id
    AND t_in.transaction_type IN ('Deposit','WireTransfer','CashDeposit')
    AND t_out.transaction_type IN ('Withdrawal','WireTransfer')
    AND t_out.transaction_date > t_in.transaction_date
    AND (JULIANDAY(t_out.transaction_date) - JULIANDAY(t_in.transaction_date)) * 24 <= 48
WHERE t_in.amount >= 10000
  AND t_out.amount >= t_in.amount * 0.80;   -- most of the money moved back out


-- ------------------------------------------------------------
-- QUERY 3: ROUND-DOLLAR TRANSACTION DETECTION
-- ------------------------------------------------------------
-- WHAT ARE ROUND-DOLLAR TRANSACTIONS? Payments in suspiciously exact
-- amounts (e.g., $10,000.00, $25,000.00). Genuine commercial or
-- personal transactions usually have irregular amounts (invoices,
-- taxes, fees). Perfectly round, large transactions can indicate
-- fabricated invoices or informal/illicit value transfer.
--
-- WHAT THIS QUERY DOES: Flags any transaction of $5,000 or more where
-- the amount is an exact multiple of $1,000 (no cents, no odd dollars).
-- ------------------------------------------------------------

DROP VIEW IF EXISTS v_round_dollar_flags;
CREATE VIEW v_round_dollar_flags AS
SELECT
    transaction_id,
    account_id,
    transaction_date,
    amount,
    transaction_type,
    counterparty_name,
    counterparty_country
FROM transactions
WHERE amount >= 5000
  AND amount = CAST(amount AS INT)          -- no cents
  AND CAST(amount AS INT) % 1000 = 0;       -- exact thousand


-- ------------------------------------------------------------
-- QUERY 4: HIGH-RISK COUNTRY EXPOSURE
-- ------------------------------------------------------------
-- WHAT IS HIGH-RISK COUNTRY EXPOSURE? Transactions sent to, or
-- received from, countries on international sanctions/FATF watch
-- lists (e.g., Iran, North Korea, Syria). Any activity touching these
-- jurisdictions carries elevated money-laundering and sanctions risk.
--
-- WHAT THIS QUERY DOES: Joins transactions to the watchlist table
-- wherever the counterparty_country matches a country listed in the
-- watchlist (entity_type = 'Country').
-- ------------------------------------------------------------

DROP VIEW IF EXISTS v_high_risk_country_flags;
CREATE VIEW v_high_risk_country_flags AS
SELECT
    t.transaction_id,
    t.account_id,
    t.transaction_date,
    t.amount,
    t.counterparty_country,
    w.risk_reason
FROM transactions t
JOIN watchlist w
    ON t.counterparty_country = w.entity_name
    AND w.entity_type = 'Country';


-- ------------------------------------------------------------
-- QUERY 5: WATCHLIST NAME MATCHES (INDIVIDUALS & ORGANIZATIONS)
-- ------------------------------------------------------------
-- WHAT THIS QUERY DOES: Looks for exact matches between a
-- transaction's counterparty_name (or the account holder's own
-- full_name) and any Individual/Organization on the watchlist.
-- In a real bank this would use "fuzzy" name matching software;
-- here we use exact matching, which is what SQLite/DB Browser can do
-- natively, and note where fuzzy matching would add more coverage.
-- ------------------------------------------------------------

DROP VIEW IF EXISTS v_watchlist_name_matches;
CREATE VIEW v_watchlist_name_matches AS
-- Match 1: the counterparty on a transaction is a watchlisted name
SELECT
    t.transaction_id,
    t.account_id,
    a.customer_id,
    'Counterparty' AS match_type,
    t.counterparty_name AS matched_name,
    w.risk_reason
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
JOIN watchlist w
    ON t.counterparty_name = w.entity_name
    AND w.entity_type IN ('Individual','Organization')

UNION ALL

-- Match 2: the account holder (customer) themselves shares a name
-- with someone on the watchlist
SELECT
    NULL AS transaction_id,
    a.account_id,
    c.customer_id,
    'Account Holder' AS match_type,
    c.full_name AS matched_name,
    w.risk_reason
FROM customers c
JOIN accounts a ON c.customer_id = a.customer_id
JOIN watchlist w
    ON c.full_name = w.entity_name
    AND w.entity_type = 'Individual';


-- ------------------------------------------------------------
-- QUERY 6: DORMANT ACCOUNT REACTIVATION
-- ------------------------------------------------------------
-- WHAT IS DORMANT ACCOUNT REACTIVATION? An account with no activity
-- for a long time suddenly receives a large transaction. Criminals
-- sometimes use old, low-scrutiny accounts to move money because
-- they attract less attention than brand-new accounts.
--
-- WHAT THIS QUERY DOES: Flags any transaction of $10,000+ that occurs
-- on an account currently flagged as 'Dormant' in the accounts table.
-- ------------------------------------------------------------

DROP VIEW IF EXISTS v_dormant_reactivation_flags;
CREATE VIEW v_dormant_reactivation_flags AS
SELECT
    t.transaction_id,
    t.account_id,
    a.customer_id,
    t.transaction_date,
    t.amount,
    a.status
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
WHERE a.status = 'Dormant'
  AND t.amount >= 10000;


-- ------------------------------------------------------------
-- QUERY 7: CUSTOMER-LEVEL RISK SCORE
-- ------------------------------------------------------------
-- WHAT THIS QUERY DOES: Rolls all the red-flag signals above up to
-- the CUSTOMER level and computes a simple point-based risk score.
-- This mirrors how real banks build a composite risk score before
-- deciding whether to open an investigation (a "Suspicious Activity
-- Report" case).
--
-- SCORING LOGIC (points are illustrative, not regulatory):
--   +30  customer's own bank risk_rating = High
--   +25  involved in a structuring pattern
--   +20  involved in rapid fund movement
--   +15  has round-dollar transactions
--   +20  has high-risk country exposure
--   +30  watchlist name match (self or counterparty)
--   +15  dormant account reactivation
-- ------------------------------------------------------------

DROP VIEW IF EXISTS v_customer_risk_score;
CREATE VIEW v_customer_risk_score AS
WITH base AS (
    SELECT customer_id, risk_rating FROM customers
),
structuring_cust AS (
    SELECT DISTINCT a.customer_id
    FROM v_structuring_flags s
    JOIN accounts a ON s.account_id = a.account_id
),
rapid_cust AS (
    SELECT DISTINCT a.customer_id
    FROM v_rapid_movement_flags r
    JOIN accounts a ON r.account_id = a.account_id
),
round_cust AS (
    SELECT DISTINCT a.customer_id
    FROM v_round_dollar_flags rd
    JOIN accounts a ON rd.account_id = a.account_id
),
hr_country_cust AS (
    SELECT DISTINCT a.customer_id
    FROM v_high_risk_country_flags h
    JOIN accounts a ON h.account_id = a.account_id
),
watchlist_cust AS (
    SELECT DISTINCT customer_id FROM v_watchlist_name_matches
),
dormant_cust AS (
    SELECT DISTINCT customer_id FROM v_dormant_reactivation_flags
)
SELECT
    b.customer_id,
    b.risk_rating AS bank_assigned_risk_rating,
    (CASE WHEN b.risk_rating = 'High' THEN 30 ELSE 0 END
     + CASE WHEN sc.customer_id IS NOT NULL THEN 25 ELSE 0 END
     + CASE WHEN rc.customer_id IS NOT NULL THEN 20 ELSE 0 END
     + CASE WHEN rdc.customer_id IS NOT NULL THEN 15 ELSE 0 END
     + CASE WHEN hrc.customer_id IS NOT NULL THEN 20 ELSE 0 END
     + CASE WHEN wc.customer_id IS NOT NULL THEN 30 ELSE 0 END
     + CASE WHEN dc.customer_id IS NOT NULL THEN 15 ELSE 0 END
    ) AS composite_risk_score,
    CASE WHEN sc.customer_id  IS NOT NULL THEN 'Y' ELSE 'N' END AS flag_structuring,
    CASE WHEN rc.customer_id  IS NOT NULL THEN 'Y' ELSE 'N' END AS flag_rapid_movement,
    CASE WHEN rdc.customer_id IS NOT NULL THEN 'Y' ELSE 'N' END AS flag_round_dollar,
    CASE WHEN hrc.customer_id IS NOT NULL THEN 'Y' ELSE 'N' END AS flag_high_risk_country,
    CASE WHEN wc.customer_id  IS NOT NULL THEN 'Y' ELSE 'N' END AS flag_watchlist_match,
    CASE WHEN dc.customer_id  IS NOT NULL THEN 'Y' ELSE 'N' END AS flag_dormant_reactivation
FROM base b
LEFT JOIN structuring_cust  sc  ON b.customer_id = sc.customer_id
LEFT JOIN rapid_cust        rc  ON b.customer_id = rc.customer_id
LEFT JOIN round_cust        rdc ON b.customer_id = rdc.customer_id
LEFT JOIN hr_country_cust   hrc ON b.customer_id = hrc.customer_id
LEFT JOIN watchlist_cust    wc  ON b.customer_id = wc.customer_id
LEFT JOIN dormant_cust      dc  ON b.customer_id = dc.customer_id;


-- ------------------------------------------------------------
-- QUERY 8: FINAL ALERT TRIAGE TABLE
-- ------------------------------------------------------------
-- WHAT IS "ALERT TRIAGE"? In a real bank, every flagged customer
-- becomes an "alert" that a human analyst must review and assign a
-- disposition (decision):
--   ESCALATE = high enough risk to file a Suspicious Activity Report
--              (SAR) or open a full investigation
--   MONITOR  = worth watching for a period but not yet actionable
--   CLOSE    = reviewed and determined to be a false positive
--
-- WHAT THIS QUERY DOES: Combines the composite risk score with a list
-- of plain-English "reason codes" (which red flags fired) and assigns
-- a disposition based on score thresholds:
--   score >= 60  -> Escalate
--   score 30-59  -> Monitor
--   score < 30   -> Close
-- ------------------------------------------------------------

DROP VIEW IF EXISTS v_alert_triage;
CREATE VIEW v_alert_triage AS
SELECT
    c.customer_id,
    cu.full_name,
    cu.country_of_residence,
    c.bank_assigned_risk_rating,
    c.composite_risk_score,
    TRIM(
        (CASE WHEN c.flag_structuring = 'Y' THEN 'STRUCTURING; ' ELSE '' END) ||
        (CASE WHEN c.flag_rapid_movement = 'Y' THEN 'RAPID_FUND_MOVEMENT; ' ELSE '' END) ||
        (CASE WHEN c.flag_round_dollar = 'Y' THEN 'ROUND_DOLLAR_TXN; ' ELSE '' END) ||
        (CASE WHEN c.flag_high_risk_country = 'Y' THEN 'HIGH_RISK_COUNTRY; ' ELSE '' END) ||
        (CASE WHEN c.flag_watchlist_match = 'Y' THEN 'WATCHLIST_MATCH; ' ELSE '' END) ||
        (CASE WHEN c.flag_dormant_reactivation = 'Y' THEN 'DORMANT_REACTIVATION; ' ELSE '' END)
    ) AS reason_codes,
    CASE
        WHEN c.composite_risk_score >= 60 THEN 'Escalate'
        WHEN c.composite_risk_score >= 30 THEN 'Monitor'
        ELSE 'Close'
    END AS disposition
FROM v_customer_risk_score c
JOIN customers cu ON c.customer_id = cu.customer_id
WHERE c.composite_risk_score > 0
ORDER BY c.composite_risk_score DESC;
