# AML Triage Pipeline — Portfolio Project

A complete, resume-ready Anti-Money Laundering (AML) transaction monitoring and alert triage
pipeline, built entirely with **DB Browser for SQLite** and **Tableau Public** (both free).

No coding experience, SQL knowledge, or AML background required — every term is defined
the first time it's used, and every step is numbered.

---

## Step 1: What is an AML triage pipeline, and what does this project cover?

**AML (Anti-Money Laundering)** refers to the laws, processes, and systems banks use to
detect and stop criminals from disguising illegally obtained money as legitimate funds
("laundering" it).

A **transaction monitoring system** is software that watches every transaction moving
through a bank and looks for suspicious patterns ("red flags").

**Alert triage** is the human/analytical process of taking every red flag the system finds,
scoring how serious it is, and deciding what to do about it — investigate further, keep
watching, or dismiss it as a false alarm.

### Scope of this project
This project builds a simplified but realistic version of that pipeline:

1. **Customers** — the bank's account holders (fictional, synthetic people).
2. **Accounts** — each customer's checking/savings/business accounts.
3. **Transactions** — a year of deposits, withdrawals, wires, and ACH transfers.
4. **Watchlist** — a reference list of sanctioned countries, individuals, and organizations
   (all fictional — this is NOT a real sanctions list).
5. **Risk scoring & red-flag detection** — SQL logic that flags 6 classic AML red flag
   patterns (defined in Step 4).
6. **Alert triage table** — a final output that scores every customer and assigns a
   disposition: **Escalate**, **Monitor**, or **Close**.
7. **Tableau dashboard** — a visual, interactive way to explore the alerts.

Everything is 100% synthetic (fake) data, generated specifically for this project. No real
customer, transaction, or sanctions data is used anywhere.

---

## Step 2: The synthetic dataset

Four CSV files were generated. Exact row counts and columns below.

### File: `customers.csv` (200 rows)
| Column | Description |
|---|---|
| customer_id | Unique ID, e.g. `CUST0001` |
| full_name | Customer's full name |
| date_of_birth | YYYY-MM-DD |
| nationality | Country of citizenship |
| occupation | Job title (some occupations are cash-heavy / higher AML risk, e.g. "Currency Exchange Operator") |
| customer_since | Date the customer opened their first account |
| risk_rating | Bank-assigned rating at onboarding: `Low`, `Medium`, or `High` |
| country_of_residence | Where the customer currently lives |

### File: `accounts.csv` (329 rows)
| Column | Description |
|---|---|
| account_id | Unique ID, e.g. `ACCT00001` |
| customer_id | Links to `customers.customer_id` |
| account_type | `Checking`, `Savings`, or `Business` |
| open_date | YYYY-MM-DD |
| status | `Active`, `Dormant` (no recent use), or `Closed` |
| branch_country | Country where the account is held |

### File: `transactions.csv` (3,385 rows)
| Column | Description |
|---|---|
| transaction_id | Unique ID, e.g. `TXN000001` |
| account_id | Links to `accounts.account_id` |
| transaction_date | YYYY-MM-DD HH:MM:SS (all of 2025) |
| amount | USD amount ($32.48 to $93,443.96) |
| currency | Always `USD` in this dataset |
| transaction_type | `Deposit`, `CashDeposit`, `Withdrawal`, `WireTransfer`, `ACH` |
| counterparty_name | The other party in the transaction |
| counterparty_country | Counterparty's country |
| channel | `Branch`, `Online`, `ATM`, `Wire` |

### File: `watchlist.csv` (23 rows)
| Column | Description |
|---|---|
| watchlist_id | Unique ID, e.g. `WL0001` |
| entity_name | Name of the sanctioned country, person, or organization (all fictional except country names, which are used only as illustrative "high-risk jurisdiction" examples) |
| entity_type | `Country`, `Individual`, or `Organization` |
| risk_reason | Why the entity is listed |
| list_source | Fictional source label, e.g. `OFAC_SDN` |
| date_added | When the entity was added to the list |

### Red flags baked into the data
The transactions file deliberately contains these classic AML patterns so your queries have
real signal to detect (all explained in plain language in Step 4):
1. **Structuring/smurfing** — repeated cash deposits just under $10,000.
2. **Rapid fund movement** — large money in, then straight back out within 48 hours.
3. **Round-dollar transactions** — suspiciously exact amounts like $10,000.00, $25,000.00.
4. **High-risk country exposure** — wires to/from sanctioned countries.
5. **Dormant account reactivation** — an inactive account suddenly receiving a large transaction.
6. **Watchlist name matches** — a transaction counterparty (or the account holder) shares a
   name with someone on the watchlist.

> The full CSV files are attached to this project alongside this README — you don't need to
> retype anything, just download and use them directly.

---

## Step 3: Build the database in DB Browser for SQLite

**DB Browser for SQLite** is a free desktop app that lets you create and query a database
without writing any command-line code. Download it from https://sqlitebrowser.org/ if you
don't have it.

1. Open **DB Browser for SQLite**.
2. Click **New Database**. Name it `aml_triage.sqlite` and save it in your project folder.
   (A small "Edit table definition" popup may appear — click **Cancel**, we'll create tables
   with SQL instead.)
3. Click the **Execute SQL** tab (top of the window).
4. Open the file `schema.sql` (provided with this project), copy its entire contents, and
   paste it into the Execute SQL text box.
5. Click the **▶ Execute all** button (or press Ctrl+Return / Cmd+Return). This creates all
   four empty tables: `customers`, `accounts`, `transactions`, `watchlist`.
6. Click **Write Changes** (top toolbar) to save.

### Import each CSV into its matching table
Repeat this sub-process 4 times, once per file:

7. Go to **File → Import → Table from CSV file...**
8. Select `customers.csv`.
9. In the import dialog: set **Table name** to `customers` (it should detect the existing
   table). Make sure **Column names in first line** is checked. Click **OK**.
10. A popup will ask "Table already exists. Do you want to modify it?" — click **No** (we
    already created the correct structure) if prompted, or if DB Browser asks whether to
    import into the existing table, choose that option so it appends the CSV rows into your
    empty `customers` table rather than creating a new one.
11. Repeat steps 7–10 for `accounts.csv` → table `accounts`, `transactions.csv` → table
    `transactions`, and `watchlist.csv` → table `watchlist`.
12. Click **Write Changes** to save the database file.
13. Verify: click the **Browse Data** tab, select each table from the dropdown, and confirm
    row counts match Step 2 (200 customers, 329 accounts, 3,385 transactions, 23 watchlist
    entries).

---

## Step 4: SQL analytics layer

Now we'll add the "brains" of the pipeline — SQL views that scan the transactions and flag
suspicious patterns. A **view** is a saved query that behaves like a table you can query
again and again without re-running the logic manually each time.

14. Go back to the **Execute SQL** tab.
15. Open the file `analytics.sql` (provided with this project), copy its entire contents,
    and paste it into the Execute SQL box.
16. Click **▶ Execute all**. This creates 8 views. If you see a red error, make sure Step 3
    was completed fully first (the views depend on the 4 tables already existing and being
    populated).
17. Click **Write Changes** to save.

### What each view does (already tested against the real dataset)

| View | Rows returned | Plain-English explanation |
|---|---|---|
| `v_structuring_flags` | 8 accounts | Finds accounts with 3+ cash deposits between $9,000–$9,999.99 within any 7-day window — the classic "stay under the CTR threshold" trick. |
| `v_rapid_movement_flags` | 10 pairs | Finds a large deposit/wire-in followed within 48 hours by a similarly-sized withdrawal/wire-out on the same account. |
| `v_round_dollar_flags` | 48 transactions | Flags transactions of $5,000+ that are an exact multiple of $1,000 (no cents, no odd dollars) — a common indicator of fabricated invoices or informal value transfer. |
| `v_high_risk_country_flags` | 295 transactions | Joins transactions to the watchlist wherever the counterparty's country is a listed high-risk jurisdiction. |
| `v_watchlist_name_matches` | 13 matches | Finds exact name matches between a transaction counterparty (or the account holder) and a sanctioned individual/organization. (Real banks use "fuzzy" matching for spelling variations — noted as a possible future enhancement.) |
| `v_dormant_reactivation_flags` | 76 transactions | Flags $10,000+ transactions occurring on an account currently marked `Dormant`. |
| `v_customer_risk_score` | 200 customers (all of them) | Rolls every red flag above up to the customer level and computes a composite point score (see scoring table below). |
| `v_alert_triage` | 54 customers | The **final output**: every customer with a non-zero risk score, their reason codes, and a disposition decision. |

### Risk scoring logic (illustrative, not a real regulatory standard)
| Signal | Points |
|---|---|
| Bank's own risk_rating = High | +30 |
| Structuring pattern | +25 |
| Rapid fund movement | +20 |
| Round-dollar transactions | +15 |
| High-risk country exposure | +20 |
| Watchlist name match | +30 |
| Dormant account reactivation | +15 |

### Disposition thresholds
| Composite score | Disposition |
|---|---|
| 60+ | **Escalate** — file/investigate as a likely Suspicious Activity Report (SAR) case |
| 30–59 | **Monitor** — keep watching, not yet actionable |
| 1–29 | not shown in final view (below the threshold to even generate an alert) |

18. To see the final result yourself: in **Execute SQL**, run:
    ```sql
    SELECT * FROM v_alert_triage;
    ```
    You should see 54 rows, sorted by risk score descending, with the highest scoring
    around 135 points and disposition `Escalate`.

---

## Step 5: Export tables for Tableau

Tableau Public reads CSV files, not `.sqlite` files directly, so we export the tables we
need. Four export files are provided with this project (already generated and tested), but
here's how to regenerate them yourself if you want practice:

19. In **Execute SQL**, run `SELECT * FROM v_alert_triage;` then click the **Export** icon
    above the results grid (or right-click the results → **Export results as CSV**). Save
    as `export_alert_triage.csv`.
20. Run this enrichment query (joins transactions to customer info for dashboard filtering),
    then export the results as `export_transactions_enriched.csv`:
    ```sql
    SELECT t.transaction_id, t.account_id, a.customer_id, t.transaction_date, t.amount,
           t.transaction_type, t.counterparty_name, t.counterparty_country, t.channel,
           cu.full_name, cu.risk_rating, cu.country_of_residence
    FROM transactions t
    JOIN accounts a ON t.account_id = a.account_id
    JOIN customers cu ON a.customer_id = cu.customer_id;
    ```
21. Run `SELECT * FROM v_high_risk_country_flags;` and export as
    `export_high_risk_country_flags.csv`.
22. Run `SELECT * FROM v_customer_risk_score;` and export as
    `export_customer_risk_score.csv`.

You now have exactly the 4 files Tableau needs:
`export_alert_triage.csv`, `export_transactions_enriched.csv`,
`export_high_risk_country_flags.csv`, `export_customer_risk_score.csv`.

---

## Step 6: Build the Tableau Public dashboard

Download **Tableau Public** free from https://public.tableau.com/ if you don't have it.

### Connect your data
23. Open Tableau Public. Under **Connect → To a File**, click **Text file**.
24. Select `export_transactions_enriched.csv`. It opens on the canvas as a data source.
25. Click the **+** next to the data source tab at the bottom, or drag a second file:
    add `export_alert_triage.csv`, `export_high_risk_country_flags.csv`, and
    `export_customer_risk_score.csv` the same way (**Connect → To a File → Text file**).
26. You do not need to join these files — we'll use each one on its own worksheet.

### View 1: "Alert Volume & Risk Trend" (line/bar combo)
27. Click the **Sheet 1** tab at the bottom. Rename it (double-click the tab) to
    `Alert Volume & Risk Trend`.
28. In the **Data** pane (left side), make sure `export_transactions_enriched.csv` is the
    active data source (click its name at the top of the Data pane if not).
29. Drag **transaction_date** from the Data pane onto the **Columns** shelf (top of canvas).
    Tableau will auto-create a date hierarchy — right-click the new pill on the Columns
    shelf and choose **Month** (under the "More" or date-part options) so the trend groups
    by month.
30. Drag **amount** onto the **Rows** shelf. Right-click the new pill → **Measure** →
    confirm it's set to **Sum**.
31. From the toolbar, click the **Show Me** panel (top right) and select the **line chart**
    icon to render it as a trend line.
32. Drag **risk_rating** onto the **Color** shelf (under the Marks card, left of the canvas)
    to color the trend line by customer risk rating (Low/Medium/High).
33. Rename the axis: double-click the vertical axis label and change it to
    "Total Transaction Amount ($)".

### View 2: "Geographic / High-Risk Country Exposure" (map)
34. Right-click the sheet tabs area at the bottom → **New Worksheet**. Rename it
    `High-Risk Country Exposure`.
35. Switch the active data source (Data pane) to `export_high_risk_country_flags.csv`.
36. Drag **counterparty_country** onto the canvas — Tableau should auto-detect it as a
    geographic field and generate a filled map. If it shows a warning icon, right-click the
    field in the Data pane → **Geographic Role → Country/Region**.
37. Drag **amount** onto the **Color** shelf on the Marks card — this shades each country by
    total flagged transaction value.
38. Drag **transaction_id** onto the **Label** shelf, then right-click it on the Marks card →
    **Measure → Count** to also show the number of flagged transactions per country as a
    label.
39. From **Show Me**, confirm the **filled map** view is selected.

### View 3: "Top Flagged Customers" (horizontal bar chart)
40. Create another new worksheet, rename it `Top Flagged Customers`.
41. Switch the active data source to `export_alert_triage.csv`.
42. Drag **full_name** onto the **Rows** shelf.
43. Drag **composite_risk_score** onto the **Columns** shelf.
44. Click the sort icon (small bar-chart icon with an arrow, appears near the top of the
    Rows shelf/axis when you hover) to sort descending by risk score.
45. Drag **disposition** onto the **Color** shelf so Escalate/Monitor bars are visually
    distinct.
46. Right-click the **full_name** field on Rows → **Filter...**, go to the **Top** tab,
    select **By field**, enter `10`, choose **composite_risk_score** and **Sum**, click
    **OK** — this limits the view to the top 10 highest-risk customers.
47. Drag **reason_codes** onto the **Tooltip** shelf so hovering over a bar shows exactly
    which red flags fired for that customer.

### Summary Dashboard
48. Right-click the sheet tabs area → **New Dashboard**. Rename it `AML Triage Summary`.
49. In the **Dashboard** pane (left side, "Sheets" list), drag `Alert Volume & Risk Trend`
    onto the canvas — drop it in the top half.
50. Drag `High-Risk Country Exposure` onto the canvas below/beside it (Tableau shows a blue
    highlight indicating where it will dock — drop it in the bottom-left).
51. Drag `Top Flagged Customers` into the remaining space (bottom-right).
52. Click **Dashboard → Actions...** in the top menu, click **Add Action → Filter**. Set
    **Source Sheet** to `Top Flagged Customers`, **Target Sheets** to the other two, **Run
    action on: Select**. Click **OK**. Now clicking a customer bar filters the other two
    views to that customer's activity.
53. Add a title: double-click the dashboard title placeholder at the top and type
    "AML Triage Pipeline — Alert Summary Dashboard".
54. Click **File → Save to Tableau Public As...**, sign in / create a free Tableau Public
    account if prompted, and save as `AML_Triage_Dashboard`. This publishes it online and
    also saves a local `.twbx` packaged workbook you can attach to your portfolio.

---

## Step 7: Deliverables checklist

Store all of these in a single GitHub repository, e.g. named `aml-triage-pipeline`:

```
aml-triage-pipeline/
├── README.md                          (this file)
├── data/
│   ├── customers.csv
│   ├── accounts.csv
│   ├── transactions.csv
│   └── watchlist.csv
├── sql/
│   ├── schema.sql
│   └── analytics.sql
├── exports/
│   ├── export_alert_triage.csv
│   ├── export_transactions_enriched.csv
│   ├── export_high_risk_country_flags.csv
│   └── export_customer_risk_score.csv
├── database/
│   └── aml_triage.sqlite
└── dashboard/
    └── AML_Triage_Dashboard.twbx
```

All of the above files are provided alongside this guide — download them, drop them into
this folder structure, then run `git init`, `git add .`, `git commit -m "Initial AML triage
pipeline"`, and push to a new GitHub repository.

---

## Step 8: LinkedIn post + resume bullets

### LinkedIn post caption (under 150 words)
> 🔍 New project: I built an end-to-end AML Transaction Monitoring & Alert Triage Pipeline
> from scratch — using SQL and Tableau to simulate how banks detect financial crime.
>
> The pipeline ingests synthetic customer, account, and transaction data, then flags six
> classic money-laundering red flags: structuring, rapid fund movement, round-dollar
> transactions, high-risk country exposure, watchlist matches, and dormant account
> reactivation. Each flagged customer gets a composite risk score and a triage disposition
> (Escalate / Monitor / Close) — just like a real compliance analyst's queue.
>
> I also built an interactive Tableau dashboard to visualize alert trends, geographic risk
> exposure, and top flagged accounts.
>
> Tools: SQLite, SQL, Tableau Public.
> Code + dashboard + full write-up on GitHub 👇
> [link]
>
> #AML #ComplianceAnalytics #DataAnalytics #SQL #Tableau #FinancialCrime

### Resume bullet points
- Designed and built an end-to-end AML transaction monitoring pipeline in SQL, engineering
  8 detection queries that identified structuring, rapid fund movement, and high-risk
  jurisdiction exposure across 3,300+ synthetic transactions.
- Developed a composite customer risk-scoring model and automated alert triage logic in
  SQLite, reducing a simulated 200-customer population to 54 prioritized, disposition-ready
  alerts (Escalate/Monitor/Close).
- Built an interactive 3-view Tableau dashboard visualizing alert volume trends, geographic
  risk concentration, and top flagged customers, enabling faster compliance analyst
  decision-making.

---

## Appendix: Everything is synthetic
All customers, accounts, transactions, and watchlist entries in this project are
computer-generated and fictional. Country names are used only as generic "high-risk
jurisdiction" examples for teaching purposes and do not reflect any real current sanctions
determination. This project is for educational/portfolio purposes only and does not
constitute AML compliance advice.
