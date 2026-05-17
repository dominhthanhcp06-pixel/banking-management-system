# Banking Management System

**Final Project — Database Management Systems**
**Đỗ Minh Thành — 11245932 — DSEB 66B**
**Lecturer: Trần Hùng | National Economics University | Spring 2026**

A comprehensive bank back-office system implemented in **MySQL 8** and **Python 3.11**
covering customer, account, transaction, loan, card, and employee management for a
retail bank.

---

## Project structure

```
banking_management_system/
├── README.md
├── docs/
│   ├── 01_requirements_analysis.md     ← C1 deliverable
│   ├── 02_database_design.md           ← C2 deliverable
│   ├── 03_advanced_objects.md          ← C3 deliverable (next step)
│   └── 04_application.md               ← C4 deliverable (next step)
├── sql/
│   ├── 01_create_database.sql          ← Schema (DDL) — 11 tables
│   ├── 02_advanced_objects.sql         ← Stored procs / triggers / views (next step)
│   └── 03_indexes_optimization.sql     ← Index strategy + EXPLAIN (next step)
├── data/
│   ├── load_data.py                    ← Data loader (Kaggle + Faker)
│   └── raw/
│       └── Churn_Modelling.csv         ← Place Kaggle CSV here
├── app/
│   └── main.py                         ← Tkinter app (next step)
└── screenshots/                        ← For inclusion in final report
```

---

## Prerequisites

- **MySQL 8.x** server running locally (or remote)
- **Python 3.11+** with `pip`
- A MySQL client: **MySQL Workbench** (recommended) or **DBeaver**

## Setup — Step by step

### 1. Install Python dependencies

```bash
pip install mysql-connector-python faker pandas
```

### 2. Download the Kaggle dataset (optional but recommended)

- Visit: <https://www.kaggle.com/datasets/shrutimechlearn/churn-modelling>
- Download `Churn_Modelling.csv`
- Place the file at `data/raw/Churn_Modelling.csv`

> If the CSV is not present, the loader falls back to fully Faker-generated
> customer data — the project still works end-to-end, only with less-realistic
> customer names.

### 3. Create the schema

In MySQL Workbench, open `sql/01_create_database.sql` and execute the entire script.
This will:

- Drop and recreate the `banking_system` database
- Create all 11 tables with constraints and indexes
- Seed the `account_types` reference table

Verify by running:
```sql
USE banking_system;
SHOW TABLES;
```
You should see 11 tables.

### 4. Load sample data

```bash
cd data
python load_data.py --host localhost --user root --password YOUR_MYSQL_PASSWORD
```

Expected output (approximate):
```
[+] Connected to banking_system on localhost
[+] Inserted 10 branches
[+] Inserted 100 employees (8 managers)
[+] Manager hierarchy wired
[+] Loaded 1500 customers from Kaggle CSV
[+] Inserted 1500 customers (national_id encrypted via AES_ENCRYPT)
[+] Found 4 account types
[+] Inserted ~2500 accounts
[+] Generated 50000 transactions, inserting in batches of 5000...
[+] Transactions inserted
[+] Inserted 300 loans
[+] Inserted ~6000 loan payments
[+] Inserted ~1750 cards
[+] Inserted 4 demo users
[✓] All data loaded successfully.
```

### 5. Generate the ER diagram (for the report)

In MySQL Workbench:
1. *Database → Reverse Engineer*
2. Choose connection, select `banking_system` schema
3. Click through the wizard to produce the visual diagram
4. *File → Export → Export as PNG* — save to `screenshots/erd.png`

This image goes into the report as Figure 2.1.

### 6. Default credentials (after data load)

| Username  | Password    | Role    |
|-----------|-------------|---------|
| admin     | admin123    | Admin   |
| manager1  | manager123  | Manager |
| teller1   | teller123   | Teller  |
| auditor1  | auditor123  | Auditor |

---

## Status

| Component | Status |
|---|---|
| C1 — Requirements Analysis | ✅ Done (`docs/01_requirements_analysis.md`) |
| C2 — Schema + DDL + Sample Data | ✅ Done (`sql/01_create_database.sql`, `data/load_data.py`) |
| C3 — Advanced DB Objects | ⏳ Next step |
| C4 — Python Application | ⏳ After C3 |
| C5 — Report | ⏳ Final step |

---

## Data sources

- **Kaggle — Bank Customer Churn Modelling** (Shrutimechlearn).
  <https://www.kaggle.com/datasets/shrutimechlearn/churn-modelling>
  Used for customer demographics (10 000 records sampled to 1 500).
  Geography remapped from `France/Spain/Germany` to `Hanoi/HCMC/Da Nang`.
- **Faker** library — synthetic data for branches, employees, accounts,
  transactions, loans, cards.
