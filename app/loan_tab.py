"""Loans tab — list, originate, view amortization schedule, record payment."""

import tkinter as tk
from tkinter import ttk, messagebox
from datetime import date

from db import fetch_all, fetch_one, callproc


class LoanTab:
    def __init__(self, parent: ttk.Frame, user: dict):
        self.parent = parent
        self.user = user
        self._build_ui()
        self.refresh()

    def _build_ui(self):
        toolbar = ttk.Frame(self.parent)
        toolbar.pack(fill="x", pady=(0, 6))
        ttk.Button(toolbar, text="Refresh", command=self.refresh).pack(side="left")
        ttk.Button(toolbar, text="+ Originate Loan",
                   command=self._open_dialog).pack(side="right")
        ttk.Button(toolbar, text="View Schedule",
                   command=self._view_schedule).pack(side="right", padx=4)

        cols = ('loan_id', 'loan_code', 'customer_name', 'loan_amount',
                'interest_rate', 'term_months', 'start_date', 'status',
                'remaining_balance')
        self.tree = ttk.Treeview(self.parent, columns=cols, show='headings', height=22)
        for c, w in zip(cols, (60, 100, 180, 140, 90, 90, 110, 90, 140)):
            self.tree.heading(c, text=c.replace('_', ' ').title())
            self.tree.column(c, width=w, anchor='w')
        self.tree.pack(fill="both", expand=True, side="left")
        sb = ttk.Scrollbar(self.parent, orient="vertical", command=self.tree.yview)
        sb.pack(side="right", fill="y")
        self.tree.configure(yscrollcommand=sb.set)

    def refresh(self):
        try:
            rows = fetch_all(
                "SELECT loan_id, loan_code, customer_name, loan_amount, "
                "       interest_rate, term_months, start_date, status, "
                "       remaining_balance "
                "FROM v_loan_portfolio ORDER BY loan_id DESC LIMIT 500"
            )
        except Exception as e:
            messagebox.showerror("Database error", str(e))
            return
        self.tree.delete(*self.tree.get_children())
        for r in rows:
            self.tree.insert("", "end", values=(
                r['loan_id'], r['loan_code'], r['customer_name'],
                f"{r['loan_amount']:,.2f}",
                f"{r['interest_rate']*100:.2f}%",
                r['term_months'], r['start_date'], r['status'],
                f"{r['remaining_balance']:,.2f}",
            ))

    def _selected_loan_id(self) -> int | None:
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("Select", "Select a loan row first.")
            return None
        return int(self.tree.item(sel[0])['values'][0])

    def _open_dialog(self):
        if self.user['role'] not in ('Admin', 'Manager'):
            messagebox.showwarning("Permission",
                                   "Only Manager or Admin can originate loans.")
            return
        LoanDialog(self.parent.winfo_toplevel(),
                   user=self.user,
                   on_save=self.refresh)

    def _view_schedule(self):
        loan_id = self._selected_loan_id()
        if loan_id is None:
            return
        LoanScheduleWindow(self.parent.winfo_toplevel(), loan_id, self.user)


# ----------------------------------------------------------------------
class LoanDialog:
    def __init__(self, parent, user, on_save):
        self.user = user
        self.on_save = on_save
        self.win = tk.Toplevel(parent)
        self.win.title("Originate loan")
        self.win.geometry("420x380")
        self.win.transient(parent)
        self.win.grab_set()

        body = ttk.Frame(self.win, padding=14)
        body.pack(fill="both", expand=True)

        self.cust_var   = tk.StringVar()
        self.amount_var = tk.StringVar()
        self.rate_var   = tk.StringVar(value="0.10")
        self.term_var   = tk.StringVar(value="24")
        self.branch_var = tk.StringVar()

        ttk.Label(body, text="Customer ID *").grid(row=0, column=0, sticky="w", pady=5)
        ttk.Entry(body, textvariable=self.cust_var, width=24).grid(row=0, column=1, pady=5, sticky="we")

        ttk.Label(body, text="Loan amount (VND) *").grid(row=1, column=0, sticky="w", pady=5)
        ttk.Entry(body, textvariable=self.amount_var, width=24).grid(row=1, column=1, pady=5, sticky="we")

        ttk.Label(body, text="Annual rate (e.g. 0.10) *").grid(row=2, column=0, sticky="w", pady=5)
        ttk.Entry(body, textvariable=self.rate_var, width=24).grid(row=2, column=1, pady=5, sticky="we")

        ttk.Label(body, text="Term in months *").grid(row=3, column=0, sticky="w", pady=5)
        ttk.Entry(body, textvariable=self.term_var, width=24).grid(row=3, column=1, pady=5, sticky="we")

        ttk.Label(body, text="Branch *").grid(row=4, column=0, sticky="w", pady=5)
        branches = fetch_all("SELECT branch_id, branch_name FROM branches ORDER BY branch_id")
        self.branch_map = {b['branch_name']: b['branch_id'] for b in branches}
        ttk.Combobox(body, textvariable=self.branch_var,
                     values=list(self.branch_map.keys()),
                     state='readonly', width=22).grid(row=4, column=1, pady=5, sticky="we")

        body.columnconfigure(1, weight=1)

        ttk.Label(body,
                  text="Stored procedure sp_OriginateLoan will auto-generate\n"
                       "the full amortization schedule in the same transaction.",
                  foreground="gray", font=("Segoe UI", 8)).grid(
                  row=5, column=0, columnspan=2, sticky="w", pady=10)

        btns = ttk.Frame(self.win, padding=(14, 0, 14, 14))
        btns.pack(fill="x")
        ttk.Button(btns, text="Cancel", command=self.win.destroy).pack(side="right", padx=(8, 0))
        ttk.Button(btns, text="Originate", command=self._save).pack(side="right")

    def _save(self):
        try:
            cust   = int(self.cust_var.get().strip())
            amount = float(self.amount_var.get().strip())
            rate   = float(self.rate_var.get().strip())
            term   = int(self.term_var.get().strip())
            branch = self.branch_map[self.branch_var.get()]
        except (ValueError, KeyError):
            messagebox.showerror("Validation", "Please fill all fields with valid values.",
                                 parent=self.win)
            return
        emp = self.user['employee_id'] or 1
        try:
            out = callproc('sp_OriginateLoan',
                           [cust, amount, rate, term, branch, emp, 0],
                           out_indices=[6])
            loan_id = out[0]
            messagebox.showinfo("Success",
                f"Loan {loan_id} originated. Amortization schedule generated.",
                parent=self.win)
            self.on_save()
            self.win.destroy()
        except Exception as e:
            messagebox.showerror("Stored-procedure error", str(e), parent=self.win)


# ----------------------------------------------------------------------
class LoanScheduleWindow:
    """Show amortization schedule of a loan with a Record Payment button."""

    def __init__(self, parent, loan_id: int, user: dict):
        self.loan_id = loan_id
        self.user = user
        self.win = tk.Toplevel(parent)
        self.win.title(f"Loan {loan_id} — Amortization Schedule")
        self.win.geometry("780x520")
        self.win.transient(parent)

        toolbar = ttk.Frame(self.win, padding=8)
        toolbar.pack(fill="x")
        ttk.Button(toolbar, text="Record selected payment",
                   command=self._record_payment).pack(side="left")
        ttk.Button(toolbar, text="Refresh", command=self.refresh).pack(side="left", padx=6)
        ttk.Button(toolbar, text="Close", command=self.win.destroy).pack(side="right")

        cols = ('payment_id', 'scheduled_date', 'actual_date',
                'amount', 'principal', 'interest', 'status')
        self.tree = ttk.Treeview(self.win, columns=cols, show='headings', height=18)
        for c, w in zip(cols, (90, 130, 130, 120, 120, 120, 100)):
            self.tree.heading(c, text=c.replace('_', ' ').title())
            self.tree.column(c, width=w, anchor='w')
        self.tree.pack(fill="both", expand=True, padx=8, pady=(0, 8))

        self.refresh()

    def refresh(self):
        try:
            rows = fetch_all(
                "SELECT payment_id, scheduled_date, actual_date, amount, "
                "       principal, interest, status "
                "FROM loan_payments WHERE loan_id = %s ORDER BY scheduled_date",
                (self.loan_id,))
        except Exception as e:
            messagebox.showerror("Database error", str(e), parent=self.win)
            return
        self.tree.delete(*self.tree.get_children())
        for r in rows:
            self.tree.insert("", "end", values=(
                r['payment_id'], r['scheduled_date'], r['actual_date'] or '',
                f"{r['amount']:,.2f}",
                f"{r['principal']:,.2f}",
                f"{r['interest']:,.2f}",
                r['status'],
            ))

    def _record_payment(self):
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("Select", "Select a payment row first.", parent=self.win)
            return
        vals = self.tree.item(sel[0])['values']
        payment_id = int(vals[0])
        if vals[6] == 'Paid':
            messagebox.showinfo("Already paid",
                                "This installment is already recorded.", parent=self.win)
            return
        try:
            callproc('sp_RecordLoanPayment', [payment_id, date.today()])
            messagebox.showinfo("Done", f"Payment {payment_id} recorded.", parent=self.win)
            self.refresh()
        except Exception as e:
            messagebox.showerror("Stored-procedure error", str(e), parent=self.win)
