-- ============================================================
-- AML TRIAGE PIPELINE - TABLE CREATION SCRIPT (schema.sql)
-- Run this FIRST in DB Browser for SQLite, in the "Execute SQL" tab.
-- ============================================================

DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id         TEXT PRIMARY KEY,
    full_name           TEXT NOT NULL,
    date_of_birth       TEXT,
    nationality         TEXT,
    occupation          TEXT,
    customer_since      TEXT,
    risk_rating         TEXT,      -- Low / Medium / High (bank-assigned at onboarding)
    country_of_residence TEXT
);

DROP TABLE IF EXISTS accounts;
CREATE TABLE accounts (
    account_id      TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL,
    account_type    TEXT,          -- Checking / Savings / Business
    open_date       TEXT,
    status          TEXT,          -- Active / Dormant / Closed
    branch_country  TEXT,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

DROP TABLE IF EXISTS transactions;
CREATE TABLE transactions (
    transaction_id      TEXT PRIMARY KEY,
    account_id           TEXT NOT NULL,
    transaction_date     TEXT NOT NULL,   -- 'YYYY-MM-DD HH:MM:SS'
    amount                REAL NOT NULL,
    currency              TEXT,
    transaction_type      TEXT,   -- Deposit / Withdrawal / WireTransfer / ACH / CashDeposit
    counterparty_name     TEXT,
    counterparty_country  TEXT,
    channel               TEXT,   -- Branch / Online / ATM / Wire
    FOREIGN KEY (account_id) REFERENCES accounts(account_id)
);

DROP TABLE IF EXISTS watchlist;
CREATE TABLE watchlist (
    watchlist_id    TEXT PRIMARY KEY,
    entity_name     TEXT NOT NULL,
    entity_type     TEXT,   -- Country / Individual / Organization
    risk_reason     TEXT,
    list_source     TEXT,
    date_added      TEXT
);
