"""
Banking Management System — Sample Data Loader
================================================

Populates the `banking_system` database with realistic sample data.

Sources:
    - Customer demographics (names, gender, age, balance, geography) are
      sourced from the Kaggle "Bank Customer Churn Modelling" dataset
      (file: Churn_Modelling.csv) when present at data/raw/Churn_Modelling.csv.
      Geography is remapped from {France, Spain, Germany} to
      {Hanoi, Ho Chi Minh City, Da Nang} for Vietnamese context.
    - All other tables are synthesized via the Faker library.
    - If the Kaggle CSV is absent, customers are also fully Faker-generated.
"""

import argparse
import csv
import hashlib
import os
import random
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path

import mysql.connector
from faker import Faker

# ---------------------------------------------------------------------------- 
# Configuration
# ---------------------------------------------------------------------------- 

RANDOM_SEED        = 42
NUM_BRANCHES       = 10
NUM_EMPLOYEES      = 100
NUM_CUSTOMERS      = 1500
ACCOUNTS_PER_CUST  = (1, 3)          # uniform [1,2] in practice
NUM_TRANSACTIONS   = 50_000
NUM_LOANS          = 300
NUM_CARDS_RATIO    = 0.70            # ~70% of accounts have a card
TX_DATE_RANGE_DAYS = 365             # one year of activity ending today

ENCRYPTION_KEY = 'BMS_AES_KEY_2026'  # AES key for PII encryption (demo)

KAGGLE_CSV = Path(__file__).parent / 'raw' / 'Churn_Modelling.csv'

CITIES_VN = ['Hanoi', 'Ho Chi Minh City', 'Da Nang', 'Hai Phong', 'Can Tho']
GEO_REMAP = {'France': 'Hanoi', 'Germany': 'Ho Chi Minh City', 'Spain': 'Da Nang'}

random.seed(RANDOM_SEED)
fake    = Faker(['vi_VN', 'en_US'])
fake.seed_instance(RANDOM_SEED)
fake_en = Faker('en_US')
fake_en.seed_instance(RANDOM_SEED)


# ---------------------------------------------------------------------------- 
# Helpers
# ---------------------------------------------------------------------------- 

def sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def random_date(start: date, end: date) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))


def random_phone() -> str:
    return '0' + str(random.choice([3, 5, 7, 8, 9])) + ''.join(
        random.choices('0123456789', k=8))


def random_account_number() -> str:
    return ''.join(random.choices('0123456789', k=14))


def random_card_number() -> str:
    return ''.join(random.choices('0123456789', k=16))


# ---------------------------------------------------------------------------- 
# Generators per table
# ---------------------------------------------------------------------------- 

def gen_branches(n: int):
    rows = []
    base_date = date(2010, 1, 1)
    for i in range(n):
        city = CITIES_VN[i % len(CITIES_VN)]
        rows.append((
            f'BR{i+1:03d}',
            f'{city} Branch {i+1}',
            fake['vi_VN'].street_address(),
            city,
            random_phone(),
            random_date(base_date, date(2023, 12, 31)),
        ))
    return rows


def gen_employees(n: int, branch_ids: list[int]):
    """Generate employees. First N get manager seats, rest are tellers/auditors."""
    rows = []
    positions_dist = ['Manager'] * 8 + ['Auditor'] * 5 + ['Admin'] * 2 + ['Teller'] * 85
    for i in range(n):
        position = random.choice(positions_dist)
        first    = fake_en.first_name()
        last     = fake_en.last_name()
        rows.append((
            f'EMP{i+1:04d}',
            f'{first} {last}',
            position,
            random.choice(branch_ids),
            f'{first.lower()}.{last.lower()}{i}@bms.com.vn',
            random_phone(),
            random_date(date(2015, 1, 1), date(2024, 12, 31)),
            round(random.uniform(8_000_000, 60_000_000), 2),
        ))
    return rows


def gen_customers_from_kaggle(csv_path: Path, n: int):
    """Read Kaggle CSV, sample n rows, enrich with Faker."""
    rows = []
    with open(csv_path, encoding='utf-8') as f:
        reader = list(csv.DictReader(f))
    sampled = random.sample(reader, min(n, len(reader)))
    today = date.today()
    for i, r in enumerate(sampled):
        gender   = 'Male' if r['Gender'] == 'Male' else 'Female'
        age      = int(r['Age'])
        dob      = date(today.year - age, random.randint(1, 12), random.randint(1, 28))
        city     = GEO_REMAP.get(r['Geography'], random.choice(CITIES_VN))
        first    = fake_en.first_name_male() if gender == 'Male' else fake_en.first_name_female()
        full_name = f"{first} {r['Surname']}"
        register_dt = random_date(date(2018, 1, 1), date(2024, 12, 31))
        rows.append({
            'cust_code':    f'CUST{i+1:05d}',
            'full_name':    full_name,
            'gender':       gender,
            'date_of_birth': dob,
            'national_id':  ''.join(random.choices('0123456789', k=12)),
            'phone':        random_phone(),
            'email':        f'{first.lower()}.{r["Surname"].lower()}{i}@example.com',
            'address':      fake['vi_VN'].street_address(),
            'city':         city,
            'register_date': register_dt,
            'credit_score': int(r['CreditScore']),
            'kg_balance':   float(r['Balance']),
            'kg_products':  int(r['NumOfProducts']),
            'kg_tenure':    int(r['Tenure']),
        })
    return rows


def gen_customers_faker(n: int):
    rows = []
    for i in range(n):
        gender = random.choice(['Male', 'Female'])
        age    = random.randint(18, 75)
        dob    = date(date.today().year - age, random.randint(1, 12), random.randint(1, 28))
        first  = fake_en.first_name_male() if gender == 'Male' else fake_en.first_name_female()
        last   = fake_en.last_name()
        rows.append({
            'cust_code':    f'CUST{i+1:05d}',
            'full_name':    f'{first} {last}',
            'gender':       gender,
            'date_of_birth': dob,
            'national_id':  ''.join(random.choices('0123456789', k=12)),
            'phone':        random_phone(),
            'email':        f'{first.lower()}.{last.lower()}{i}@example.com',
            'address':      fake['vi_VN'].street_address(),
            'city':         random.choice(CITIES_VN),
            'register_date': random_date(date(2018, 1, 1), date(2024, 12, 31)),
            'credit_score': random.randint(350, 820),
            'kg_balance':   round(random.uniform(0, 200_000_000), 2),
            'kg_products':  random.randint(1, 3),
            'kg_tenure':    random.randint(0, 10),
        })
    return rows


def gen_accounts(customers: list[dict], type_ids: list[int], branch_ids: list[int]):
    """Each customer gets between 1 and kg_products accounts."""
    rows = []
    for cust in customers:
        n_accounts = max(1, min(cust['kg_products'], 3))
        for j in range(n_accounts):
            type_id   = random.choice(type_ids)
            balance   = round(cust['kg_balance'] / n_accounts if j == 0 else random.uniform(0, 50_000_000), 2)
            open_date = cust['register_date'] + timedelta(days=random.randint(0, 30))
            rows.append({
                'account_number': random_account_number(),
                'customer_id':    cust['_id'],
                'type_id':        type_id,
                'branch_id':      random.choice(branch_ids),
                'balance':        balance,
                'open_date':      open_date,
            })
    return rows


def gen_transactions(n: int, account_ids: list[int], employee_ids: list[int]):
    rows = []
    end_dt   = datetime.now()
    start_dt = end_dt - timedelta(days=TX_DATE_RANGE_DAYS)
    span     = (end_dt - start_dt).total_seconds()
    types    = ['Deposit', 'Withdrawal', 'Transfer_Out', 'Transfer_In']
    weights  = [40, 35, 12, 13]
    for _ in range(n):
        ttype = random.choices(types, weights=weights)[0]
        acc   = random.choice(account_ids)
        related = random.choice(account_ids) if ttype.startswith('Transfer') else None
        if related == acc:
            related = None
        amount = round(random.choice([
            random.uniform(50_000, 500_000),
            random.uniform(500_000, 5_000_000),
            random.uniform(5_000_000, 50_000_000),
        ]), 2)
        tx_dt = start_dt + timedelta(seconds=random.uniform(0, span))
        rows.append({
            'account_id':         acc,
            'related_account_id': related,
            'transaction_type':   ttype,
            'amount':             amount,
            'transaction_date':   tx_dt,
            'description':        f'{ttype} via system seed',
            'employee_id':        random.choice(employee_ids),
        })
    return rows


def gen_loans(n: int, customer_ids: list[int], branch_ids: list[int],
              employee_ids: list[int]):
    rows = []
    for i in range(n):
        amount  = round(random.uniform(50_000_000, 2_000_000_000), 2)
        rate    = round(random.uniform(0.06, 0.15), 4)
        term    = random.choice([12, 24, 36, 48, 60])
        start   = random_date(date(2022, 1, 1), date(2024, 12, 31))
        end     = start + timedelta(days=term * 30)
        rows.append({
            'loan_code':    f'LN{i+1:05d}',
            'customer_id':  random.choice(customer_ids),
            'loan_amount':  amount,
            'interest_rate': rate,
            'term_months':  term,
            'start_date':   start,
            'end_date':     end,
            'branch_id':    random.choice(branch_ids),
            'employee_id':  random.choice(employee_ids),
        })
    return rows


def gen_loan_payments(loans: list[dict]):
    """Generate amortization schedule for each loan (equal-monthly-installment)."""
    rows = []
    for loan in loans:
        P    = float(loan['loan_amount'])
        r    = float(loan['interest_rate']) / 12.0
        n    = loan['term_months']
        emi  = P * r * (1 + r) ** n / ((1 + r) ** n - 1)
        bal  = P
        for m in range(1, n + 1):
            interest  = bal * r
            principal = emi - interest
            bal      -= principal
            sched_dt  = loan['start_date'] + timedelta(days=30 * m)
            rows.append({
                'loan_id':        loan['_id'],
                'scheduled_date': sched_dt,
                'amount':         round(emi, 2),
                'principal':      round(principal, 2),
                'interest':       round(interest, 2),
            })
    return rows


def gen_cards(account_ids: list[int], ratio: float):
    rows = []
    for acc in random.sample(account_ids, int(len(account_ids) * ratio)):
        issue  = random_date(date(2022, 1, 1), date(2024, 12, 31))
        expiry = issue + timedelta(days=365 * 5)
        rows.append({
            'card_number': random_card_number(),
            'account_id':  acc,
            'card_type':   random.choice(['ATM', 'Debit', 'ATM']),
            'issue_date':  issue,
            'expiry_date': expiry,
            'pin_hash':    sha256(str(random.randint(1000, 9999))),
        })
    return rows


def gen_users(employees: list[tuple]):
    """Create one demo user per role + one user per Manager/Admin employee."""
    rows = [
        ('admin',    sha256('admin123'),    None, 'Admin'),
        ('manager1', sha256('manager123'),  None, 'Manager'),
        ('teller1',  sha256('teller123'),   None, 'Teller'),
        ('auditor1', sha256('auditor123'),  None, 'Auditor'),
    ]
    return rows


# ---------------------------------------------------------------------------- 
# DB orchestration
# ---------------------------------------------------------------------------- 

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host',     default='localhost')
    parser.add_argument('--user',     default='root')
    parser.add_argument('--password', default='')
    parser.add_argument('--database', default='banking_system')
    args = parser.parse_args()

    cnx = mysql.connector.connect(
        host=args.host, user=args.user,
        password=args.password, database=args.database,
        autocommit=False,
    )
    cur = cnx.cursor()
    print(f'[+] Connected to {args.database} on {args.host}')

    # 1. Branches
    branches = gen_branches(NUM_BRANCHES)
    cur.executemany(
        'INSERT INTO branches (branch_code, branch_name, address, city, phone, open_date) '
        'VALUES (%s,%s,%s,%s,%s,%s)', branches)
    cnx.commit()
    cur.execute('SELECT branch_id FROM branches')
    branch_ids = [r[0] for r in cur.fetchall()]
    print(f'[+] Inserted {len(branch_ids)} branches')

    # 2. Employees
    employees = gen_employees(NUM_EMPLOYEES, branch_ids)
    cur.executemany(
        'INSERT INTO employees (emp_code, full_name, position, branch_id, email, phone, hire_date, salary) '
        'VALUES (%s,%s,%s,%s,%s,%s,%s,%s)', employees)
    cnx.commit()
    cur.execute('SELECT employee_id, position FROM employees')
    emp_rows = cur.fetchall()
    employee_ids = [r[0] for r in emp_rows]
    manager_ids  = [r[0] for r in emp_rows if r[1] == 'Manager']
    print(f'[+] Inserted {len(employee_ids)} employees ({len(manager_ids)} managers)')

    # Wire managers
    for emp_id, _ in emp_rows:
        if manager_ids and random.random() < 0.7:
            mgr = random.choice(manager_ids)
            if mgr != emp_id:
                cur.execute('UPDATE employees SET manager_id=%s WHERE employee_id=%s',
                            (mgr, emp_id))
    cnx.commit()
    print('[+] Manager hierarchy wired')

    # 3. Customers
    if KAGGLE_CSV.exists():
        custs = gen_customers_from_kaggle(KAGGLE_CSV, NUM_CUSTOMERS)
        print(f'[+] Loaded {len(custs)} customers from Kaggle CSV')
    else:
        custs = gen_customers_faker(NUM_CUSTOMERS)
        print(f'[+] Kaggle CSV not found at {KAGGLE_CSV} — generated {len(custs)} customers via Faker')

    cur.executemany(
        'INSERT INTO customers (cust_code, full_name, gender, date_of_birth, national_id, '
        ' phone, email, address, city, register_date, credit_score) '
        'VALUES (%s,%s,%s,%s, AES_ENCRYPT(%s, %s), %s,%s,%s,%s,%s,%s)',
        [(c['cust_code'], c['full_name'], c['gender'], c['date_of_birth'],
          c['national_id'], ENCRYPTION_KEY,
          c['phone'], c['email'], c['address'], c['city'],
          c['register_date'], c['credit_score']) for c in custs])
    cnx.commit()
    cur.execute('SELECT customer_id, cust_code FROM customers ORDER BY customer_id')
    for cust, row in zip(custs, cur.fetchall()):
        cust['_id'] = row[0]
    customer_ids = [c['_id'] for c in custs]
    print(f'[+] Inserted {len(customer_ids)} customers (national_id encrypted via AES_ENCRYPT)')

    # 4. Account types are seeded by 01_create_database.sql; fetch IDs
    cur.execute('SELECT type_id FROM account_types')
    type_ids = [r[0] for r in cur.fetchall()]
    print(f'[+] Found {len(type_ids)} account types')

    # 5. Accounts
    accounts = gen_accounts(custs, type_ids, branch_ids)
    cur.executemany(
        'INSERT INTO accounts (account_number, customer_id, type_id, branch_id, balance, open_date) '
        'VALUES (%s,%s,%s,%s,%s,%s)',
        [(a['account_number'], a['customer_id'], a['type_id'], a['branch_id'],
          a['balance'], a['open_date']) for a in accounts])
    cnx.commit()
    cur.execute('SELECT account_id FROM accounts')
    account_ids = [r[0] for r in cur.fetchall()]
    print(f'[+] Inserted {len(account_ids)} accounts')

    # 6. Transactions (raw insert, balance_after computed simply for seed only)
    txs = gen_transactions(NUM_TRANSACTIONS, account_ids, employee_ids)
    print(f'[+] Generated {len(txs)} transactions, inserting in batches of 5000...')
    BATCH = 5000
    sql = ('INSERT INTO transactions (account_id, related_account_id, transaction_type, '
           'amount, balance_after, transaction_date, description, employee_id) '
           'VALUES (%s,%s,%s,%s,%s,%s,%s,%s)')
    for i in range(0, len(txs), BATCH):
        batch = [(t['account_id'], t['related_account_id'], t['transaction_type'],
                  t['amount'], t['amount'],     # balance_after seeded = amount (seed-only proxy)
                  t['transaction_date'], t['description'], t['employee_id'])
                 for t in txs[i:i + BATCH]]
        cur.executemany(sql, batch)
        cnx.commit()
    print('[+] Transactions inserted')

    # 7. Loans
    loans = gen_loans(NUM_LOANS, customer_ids, branch_ids, employee_ids)
    cur.executemany(
        'INSERT INTO loans (loan_code, customer_id, loan_amount, interest_rate, term_months, '
        'start_date, end_date, branch_id, employee_id) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)',
        [(l['loan_code'], l['customer_id'], l['loan_amount'], l['interest_rate'],
          l['term_months'], l['start_date'], l['end_date'], l['branch_id'],
          l['employee_id']) for l in loans])
    cnx.commit()
    cur.execute('SELECT loan_id, loan_code FROM loans ORDER BY loan_id')
    for loan, row in zip(loans, cur.fetchall()):
        loan['_id'] = row[0]
    print(f'[+] Inserted {len(loans)} loans')

    # 8. Loan Payments
    pays = gen_loan_payments(loans)
    cur.executemany(
        'INSERT INTO loan_payments (loan_id, scheduled_date, amount, principal, interest) '
        'VALUES (%s,%s,%s,%s,%s)',
        [(p['loan_id'], p['scheduled_date'], p['amount'], p['principal'], p['interest'])
         for p in pays])
    cnx.commit()
    print(f'[+] Inserted {len(pays)} loan payments')

    # 9. Cards
    cards = gen_cards(account_ids, NUM_CARDS_RATIO)
    cur.executemany(
        'INSERT INTO cards (card_number, account_id, card_type, issue_date, expiry_date, pin_hash) '
        'VALUES (%s,%s,%s,%s,%s,%s)',
        [(c['card_number'], c['account_id'], c['card_type'], c['issue_date'],
          c['expiry_date'], c['pin_hash']) for c in cards])
    cnx.commit()
    print(f'[+] Inserted {len(cards)} cards')

    # 10. Users
    users = gen_users(employees)
    cur.executemany(
        'INSERT INTO users (username, password_hash, employee_id, role) VALUES (%s,%s,%s,%s)',
        users)
    cnx.commit()
    print(f'[+] Inserted {len(users)} demo users')
    print('       Default credentials: admin/admin123 | manager1/manager123 | '
          'teller1/teller123 | auditor1/auditor123')

    cur.close()
    cnx.close()
    print('[✓] All data loaded successfully.')


if __name__ == '__main__':
    main()
