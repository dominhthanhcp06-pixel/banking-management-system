"""
Transactions tab — three sub-forms (Deposit / Withdrawal / Transfer)
plus a list of recent transactions. Every money operation goes through
the corresponding stored procedure (sp_Deposit, sp_Withdrawal, sp_Transfer).
"""

import tkinter as tk
from tkinter import ttk, messagebox

from db import fetch_all, callproc


class TransactionTab:
    def __init__(self, parent: ttk.Frame, user: dict):
        self.parent = parent
        self.user = user
        self._build_ui()
        self.refresh_recent()

    def _build_ui(self):
        # Top: three side-by-side forms
        forms = ttk.Frame(self.parent)
        forms.pack(fill="x", pady=(0, 8))

        self._build_deposit_form(forms).pack(side="left", fill="both", expand=True, padx=4)
        self._build_withdraw_form(forms).pack(side="left", fill="both", expand=True, padx=4)
        self._build_transfer_form(forms).pack(side="left", fill="both", expand=True, padx=4)

        # Bottom: recent transactions list
        bottom = ttk.LabelFrame(self.parent, text="Recent transactions (last 100)", padding=6)
        bottom.pack(fill="both", expand=True)

        ttk.Button(bottom, text="Refresh", command=self.refresh_recent).pack(anchor="ne", pady=(0, 4))
        cols = ('transaction_id', 'transaction_date', 'transaction_type',
                'account_id', 'related_account_id', 'amount', 'balance_after',
                'employee_id', 'description')
        self.tree = ttk.Treeview(bottom, columns=cols, show='headings', height=12)
        for c, w in zip(cols, (90, 140, 110, 90, 90, 120, 120, 80, 240)):
            self.tree.heading(c, text=c.replace('_', ' ').title())
            self.tree.column(c, width=w, anchor='w')
        self.tree.pack(fill="both", expand=True, side="left")
        sb = ttk.Scrollbar(bottom, orient="vertical", command=self.tree.yview)
        sb.pack(side="right", fill="y")
        self.tree.configure(yscrollcommand=sb.set)

    # ------------------------------------------------------------------
    def _build_deposit_form(self, parent):
        frame = ttk.LabelFrame(parent, text="Deposit", padding=10)
        self.dep_account = tk.StringVar()
        self.dep_amount  = tk.StringVar()
        self.dep_desc    = tk.StringVar(value="Counter deposit")

        ttk.Label(frame, text="Account ID *").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.dep_account, width=18).grid(row=0, column=1, pady=4, sticky="we")

        ttk.Label(frame, text="Amount (VND) *").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.dep_amount, width=18).grid(row=1, column=1, pady=4, sticky="we")

        ttk.Label(frame, text="Description").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.dep_desc, width=18).grid(row=2, column=1, pady=4, sticky="we")

        frame.columnconfigure(1, weight=1)
        ttk.Button(frame, text="Deposit", command=self._do_deposit).grid(row=3, column=0, columnspan=2, pady=(10, 0), sticky="we")
        return frame

    def _build_withdraw_form(self, parent):
        frame = ttk.LabelFrame(parent, text="Withdrawal", padding=10)
        self.wd_account = tk.StringVar()
        self.wd_amount  = tk.StringVar()
        self.wd_desc    = tk.StringVar(value="Counter withdrawal")

        ttk.Label(frame, text="Account ID *").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.wd_account, width=18).grid(row=0, column=1, pady=4, sticky="we")

        ttk.Label(frame, text="Amount (VND) *").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.wd_amount, width=18).grid(row=1, column=1, pady=4, sticky="we")

        ttk.Label(frame, text="Description").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.wd_desc, width=18).grid(row=2, column=1, pady=4, sticky="we")

        frame.columnconfigure(1, weight=1)
        ttk.Button(frame, text="Withdraw", command=self._do_withdraw).grid(row=3, column=0, columnspan=2, pady=(10, 0), sticky="we")
        return frame

    def _build_transfer_form(self, parent):
        frame = ttk.LabelFrame(parent, text="Transfer", padding=10)
        self.tx_from = tk.StringVar()
        self.tx_to   = tk.StringVar()
        self.tx_amt  = tk.StringVar()
        self.tx_desc = tk.StringVar(value="Internal transfer")

        ttk.Label(frame, text="From account *").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.tx_from, width=18).grid(row=0, column=1, pady=4, sticky="we")

        ttk.Label(frame, text="To account *").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.tx_to, width=18).grid(row=1, column=1, pady=4, sticky="we")

        ttk.Label(frame, text="Amount (VND) *").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.tx_amt, width=18).grid(row=2, column=1, pady=4, sticky="we")

        ttk.Label(frame, text="Description").grid(row=3, column=0, sticky="w", pady=4)
        ttk.Entry(frame, textvariable=self.tx_desc, width=18).grid(row=3, column=1, pady=4, sticky="we")

        frame.columnconfigure(1, weight=1)
        ttk.Button(frame, text="Transfer", command=self._do_transfer).grid(row=4, column=0, columnspan=2, pady=(10, 0), sticky="we")
        return frame

    # ------------------------------------------------------------------
    def _emp(self) -> int:
        return self.user['employee_id'] or 1

    def _do_deposit(self):
        try:
            acc = int(self.dep_account.get().strip())
            amt = float(self.dep_amount.get().strip())
            desc = self.dep_desc.get().strip() or "Deposit"
        except ValueError:
            messagebox.showerror("Validation",
                                 "Please provide valid account ID and amount.")
            return
        try:
            callproc('sp_Deposit', [acc, amt, self._emp(), desc])
            messagebox.showinfo("Done", f"Deposited {amt:,.2f} VND to account {acc}.")
            self.dep_amount.set("")
            self.refresh_recent()
        except Exception as e:
            messagebox.showerror("Stored-procedure error", str(e))

    def _do_withdraw(self):
        try:
            acc = int(self.wd_account.get().strip())
            amt = float(self.wd_amount.get().strip())
            desc = self.wd_desc.get().strip() or "Withdrawal"
        except ValueError:
            messagebox.showerror("Validation",
                                 "Please provide valid account ID and amount.")
            return
        try:
            callproc('sp_Withdrawal', [acc, amt, self._emp(), desc])
            messagebox.showinfo("Done", f"Withdrew {amt:,.2f} VND from account {acc}.")
            self.wd_amount.set("")
            self.refresh_recent()
        except Exception as e:
            messagebox.showerror("Stored-procedure error", str(e))

    def _do_transfer(self):
        try:
            src = int(self.tx_from.get().strip())
            dst = int(self.tx_to.get().strip())
            amt = float(self.tx_amt.get().strip())
            desc = self.tx_desc.get().strip() or "Transfer"
        except ValueError:
            messagebox.showerror("Validation",
                                 "Please provide valid account IDs and amount.")
            return
        try:
            callproc('sp_Transfer', [src, dst, amt, self._emp(), desc])
            messagebox.showinfo("Done",
                                f"Transferred {amt:,.2f} VND from {src} to {dst}.")
            self.tx_amt.set("")
            self.refresh_recent()
        except Exception as e:
            messagebox.showerror("Stored-procedure error", str(e))

    # ------------------------------------------------------------------
    def refresh_recent(self):
        try:
            rows = fetch_all(
                "SELECT transaction_id, transaction_date, transaction_type, "
                "       account_id, related_account_id, amount, balance_after, "
                "       employee_id, description "
                "FROM transactions ORDER BY transaction_id DESC LIMIT 100"
            )
        except Exception as e:
            messagebox.showerror("Database error", str(e))
            return
        self.tree.delete(*self.tree.get_children())
        for r in rows:
            self.tree.insert("", "end", values=(
                r['transaction_id'], r['transaction_date'], r['transaction_type'],
                r['account_id'], r['related_account_id'],
                f"{r['amount']:,.2f}", f"{r['balance_after']:,.2f}",
                r['employee_id'], r['description'],
            ))
