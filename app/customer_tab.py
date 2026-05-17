"""Customers tab — list, search, add customers."""

import tkinter as tk
from tkinter import ttk, messagebox
from datetime import date

from db import fetch_all, execute


class CustomerTab:
    def __init__(self, parent: ttk.Frame, user: dict):
        self.parent = parent
        self.user = user
        self._build_ui()
        self.refresh()

    # ------------------------------------------------------------------
    def _build_ui(self):
        toolbar = ttk.Frame(self.parent)
        toolbar.pack(fill="x", pady=(0, 6))

        ttk.Label(toolbar, text="Search:").pack(side="left", padx=(0, 4))
        self.search_var = tk.StringVar()
        ent = ttk.Entry(toolbar, textvariable=self.search_var, width=30)
        ent.pack(side="left", padx=(0, 6))
        ent.bind("<Return>", lambda e: self.refresh())
        ttk.Button(toolbar, text="Search", command=self.refresh).pack(side="left")
        ttk.Button(toolbar, text="Refresh", command=self._clear_search).pack(side="left", padx=4)
        ttk.Button(toolbar, text="+ New Customer",
                   command=self._open_new_dialog).pack(side="right")

        # Treeview
        columns = ('customer_id', 'cust_code', 'full_name', 'gender',
                   'date_of_birth', 'phone', 'city', 'credit_score', 'register_date')
        self.tree = ttk.Treeview(self.parent, columns=columns, show='headings', height=22)
        for col, w in zip(columns, (60, 80, 200, 60, 100, 110, 110, 90, 110)):
            self.tree.heading(col, text=col.replace('_', ' ').title())
            self.tree.column(col, width=w, anchor='w')
        self.tree.pack(fill="both", expand=True, side="left")

        sb = ttk.Scrollbar(self.parent, orient="vertical", command=self.tree.yview)
        sb.pack(side="right", fill="y")
        self.tree.configure(yscrollcommand=sb.set)

    # ------------------------------------------------------------------
    def _clear_search(self):
        self.search_var.set("")
        self.refresh()

    def refresh(self):
        q = self.search_var.get().strip()
        if q:
            sql = ("SELECT customer_id, cust_code, full_name, gender, date_of_birth, "
                   "phone, city, credit_score, register_date "
                   "FROM customers "
                   "WHERE full_name LIKE %s OR cust_code LIKE %s OR phone LIKE %s "
                   "ORDER BY customer_id LIMIT 500")
            like = f"%{q}%"
            params = (like, like, like)
        else:
            sql = ("SELECT customer_id, cust_code, full_name, gender, date_of_birth, "
                   "phone, city, credit_score, register_date "
                   "FROM customers ORDER BY customer_id LIMIT 500")
            params = ()
        try:
            rows = fetch_all(sql, params)
        except Exception as e:
            messagebox.showerror("Database error", str(e))
            return
        self.tree.delete(*self.tree.get_children())
        for r in rows:
            self.tree.insert("", "end", values=(
                r['customer_id'], r['cust_code'], r['full_name'], r['gender'],
                r['date_of_birth'], r['phone'], r['city'],
                r['credit_score'], r['register_date'],
            ))

    # ------------------------------------------------------------------
    def _open_new_dialog(self):
        if self.user['role'] not in ('Admin', 'Manager', 'Teller'):
            messagebox.showwarning("Permission",
                                   "Your role cannot create customers.")
            return
        CustomerDialog(self.parent.winfo_toplevel(), on_save=self.refresh)


# ----------------------------------------------------------------------
class CustomerDialog:
    """Modal dialog for creating a new customer."""

    def __init__(self, parent, on_save):
        self.on_save = on_save
        self.win = tk.Toplevel(parent)
        self.win.title("New Customer")
        self.win.geometry("420x460")
        self.win.transient(parent)
        self.win.grab_set()

        body = ttk.Frame(self.win, padding=14)
        body.pack(fill="both", expand=True)

        self.entries: dict[str, tk.Variable] = {}
        fields = [
            ('full_name',     'Full name *',          'entry'),
            ('gender',        'Gender',               'combo', ['Male','Female','Other']),
            ('date_of_birth', 'Date of birth (YYYY-MM-DD) *', 'entry'),
            ('national_id',   'National ID *',        'entry'),
            ('phone',         'Phone',                'entry'),
            ('email',         'Email',                'entry'),
            ('address',       'Address',              'entry'),
            ('city',          'City',                 'combo',
                ['Hanoi','Ho Chi Minh City','Da Nang','Hai Phong','Can Tho']),
            ('credit_score',  'Credit score (300–850)', 'entry'),
        ]
        for i, f in enumerate(fields):
            ttk.Label(body, text=f[1]).grid(row=i, column=0, sticky="w", pady=4)
            var = tk.StringVar()
            self.entries[f[0]] = var
            if f[2] == 'combo':
                w = ttk.Combobox(body, textvariable=var, values=f[3],
                                 state='readonly', width=28)
            else:
                w = ttk.Entry(body, textvariable=var, width=30)
            w.grid(row=i, column=1, sticky="we", pady=4, padx=8)

        body.columnconfigure(1, weight=1)

        btns = ttk.Frame(self.win, padding=(14, 0, 14, 14))
        btns.pack(fill="x")
        ttk.Button(btns, text="Cancel", command=self.win.destroy).pack(side="right", padx=(8, 0))
        ttk.Button(btns, text="Save", command=self._save).pack(side="right")

    def _save(self):
        v = {k: var.get().strip() for k, var in self.entries.items()}
        if not v['full_name'] or not v['date_of_birth'] or not v['national_id']:
            messagebox.showerror("Validation", "Name, DoB, and National ID are required.",
                                 parent=self.win)
            return
        try:
            # Generate cust_code as CUSTxxxxx based on next id
            cust_code = f"CUSTNEW{int(__import__('time').time()) % 100000:05d}"
            execute(
                "INSERT INTO customers "
                "(cust_code, full_name, gender, date_of_birth, national_id, "
                " phone, email, address, city, register_date, credit_score) "
                "VALUES (%s,%s,%s,%s, AES_ENCRYPT(%s, %s), %s,%s,%s,%s, %s, %s)",
                (cust_code, v['full_name'], v['gender'] or None,
                 v['date_of_birth'], v['national_id'],
                 'BMS_AES_KEY_2026',
                 v['phone'] or None, v['email'] or None,
                 v['address'] or None, v['city'] or None,
                 date.today(),
                 int(v['credit_score']) if v['credit_score'] else None)
            )
            messagebox.showinfo("Success", f"Customer created with code {cust_code}",
                                parent=self.win)
            self.on_save()
            self.win.destroy()
        except Exception as e:
            messagebox.showerror("Database error", str(e), parent=self.win)
