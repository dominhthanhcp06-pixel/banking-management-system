"""Accounts tab — list accounts, open new, freeze/unfreeze, close."""

import tkinter as tk
from tkinter import ttk, messagebox

from db import fetch_all, fetch_one, callproc


class AccountTab:
    def __init__(self, parent: ttk.Frame, user: dict):
        self.parent = parent
        self.user = user
        self._build_ui()
        self.refresh()

    def _build_ui(self):
        toolbar = ttk.Frame(self.parent)
        toolbar.pack(fill="x", pady=(0, 6))
        ttk.Label(toolbar, text="Filter customer ID:").pack(side="left")
        self.filter_var = tk.StringVar()
        ent = ttk.Entry(toolbar, textvariable=self.filter_var, width=15)
        ent.pack(side="left", padx=4)
        ent.bind("<Return>", lambda e: self.refresh())
        ttk.Button(toolbar, text="Filter", command=self.refresh).pack(side="left")
        ttk.Button(toolbar, text="Clear",
                   command=lambda: (self.filter_var.set(""), self.refresh())
                   ).pack(side="left", padx=4)

        ttk.Button(toolbar, text="+ Open Account",
                   command=self._open_dialog).pack(side="right")
        ttk.Button(toolbar, text="Freeze",
                   command=lambda: self._status_action('sp_FreezeAccount', 'frozen')
                   ).pack(side="right", padx=4)
        ttk.Button(toolbar, text="Unfreeze",
                   command=lambda: self._status_action('sp_UnfreezeAccount', 'unfrozen')
                   ).pack(side="right", padx=4)
        ttk.Button(toolbar, text="Close",
                   command=self._close_action).pack(side="right", padx=4)

        cols = ('account_id', 'account_number', 'customer_name', 'type_name',
                'branch_name', 'balance', 'status', 'open_date')
        self.tree = ttk.Treeview(self.parent, columns=cols, show='headings', height=22)
        for c, w in zip(cols, (70, 140, 180, 110, 140, 120, 80, 100)):
            self.tree.heading(c, text=c.replace('_', ' ').title())
            self.tree.column(c, width=w, anchor='w')
        self.tree.pack(fill="both", expand=True, side="left")

        sb = ttk.Scrollbar(self.parent, orient="vertical", command=self.tree.yview)
        sb.pack(side="right", fill="y")
        self.tree.configure(yscrollcommand=sb.set)

    # ------------------------------------------------------------------
    def refresh(self):
        cid = self.filter_var.get().strip()
        where = ""
        params = ()
        if cid:
            where = "WHERE a.customer_id = %s"
            params = (cid,)
        sql = f"""
            SELECT a.account_id, a.account_number, c.full_name AS customer_name,
                   at.type_name, b.branch_name, a.balance, a.status, a.open_date
            FROM accounts a
            JOIN customers     c  ON a.customer_id = c.customer_id
            JOIN account_types at ON a.type_id     = at.type_id
            JOIN branches      b  ON a.branch_id   = b.branch_id
            {where}
            ORDER BY a.account_id DESC
            LIMIT 500
        """
        try:
            rows = fetch_all(sql, params)
        except Exception as e:
            messagebox.showerror("Database error", str(e))
            return
        self.tree.delete(*self.tree.get_children())
        for r in rows:
            self.tree.insert("", "end", values=(
                r['account_id'], r['account_number'], r['customer_name'],
                r['type_name'], r['branch_name'], f"{r['balance']:,.2f}",
                r['status'], r['open_date'],
            ))

    # ------------------------------------------------------------------
    def _selected_account_id(self) -> int | None:
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("Select", "Please select an account row first.")
            return None
        vals = self.tree.item(sel[0])['values']
        return int(vals[0])

    def _status_action(self, proc: str, verb: str):
        if self.user['role'] not in ('Admin', 'Manager'):
            messagebox.showwarning("Permission",
                                   "Only Admin or Manager can change account status.")
            return
        acc = self._selected_account_id()
        if acc is None:
            return
        try:
            callproc(proc, [acc])
            messagebox.showinfo("Done", f"Account {acc} has been {verb}.")
            self.refresh()
        except Exception as e:
            messagebox.showerror("Stored-procedure error", str(e))

    def _close_action(self):
        if self.user['role'] not in ('Admin', 'Manager'):
            messagebox.showwarning("Permission",
                                   "Only Admin or Manager can close accounts.")
            return
        acc = self._selected_account_id()
        if acc is None:
            return
        if not messagebox.askyesno("Confirm", f"Close account {acc}?\n"
                                    "Balance must be exactly 0."):
            return
        try:
            callproc('sp_CloseAccount', [acc])
            messagebox.showinfo("Done", f"Account {acc} closed.")
            self.refresh()
        except Exception as e:
            messagebox.showerror("Cannot close", str(e))

    # ------------------------------------------------------------------
    def _open_dialog(self):
        if self.user['role'] not in ('Admin', 'Manager', 'Teller'):
            messagebox.showwarning("Permission",
                                   "Your role cannot open accounts.")
            return
        OpenAccountDialog(self.parent.winfo_toplevel(), on_save=self.refresh)


# ----------------------------------------------------------------------
class OpenAccountDialog:
    """Modal dialog that calls sp_OpenAccount."""

    def __init__(self, parent, on_save):
        self.on_save = on_save
        self.win = tk.Toplevel(parent)
        self.win.title("Open new account")
        self.win.geometry("420x320")
        self.win.transient(parent)
        self.win.grab_set()

        body = ttk.Frame(self.win, padding=14)
        body.pack(fill="both", expand=True)

        ttk.Label(body, text="Customer ID *").grid(row=0, column=0, sticky="w", pady=6)
        self.cust_var = tk.StringVar()
        ttk.Entry(body, textvariable=self.cust_var, width=20).grid(row=0, column=1, sticky="we", pady=6)

        ttk.Label(body, text="Account type *").grid(row=1, column=0, sticky="w", pady=6)
        self.type_var = tk.StringVar()
        types = fetch_all("SELECT type_id, type_name, min_balance, interest_rate "
                          "FROM account_types ORDER BY type_id")
        self.type_map = {f"{t['type_name']} (min {t['min_balance']:,.0f})": t['type_id']
                         for t in types}
        ttk.Combobox(body, textvariable=self.type_var,
                     values=list(self.type_map.keys()),
                     state='readonly', width=28).grid(row=1, column=1, sticky="we", pady=6)

        ttk.Label(body, text="Branch *").grid(row=2, column=0, sticky="w", pady=6)
        self.branch_var = tk.StringVar()
        branches = fetch_all("SELECT branch_id, branch_name FROM branches ORDER BY branch_id")
        self.branch_map = {b['branch_name']: b['branch_id'] for b in branches}
        ttk.Combobox(body, textvariable=self.branch_var,
                     values=list(self.branch_map.keys()),
                     state='readonly', width=28).grid(row=2, column=1, sticky="we", pady=6)

        ttk.Label(body, text="Initial deposit").grid(row=3, column=0, sticky="w", pady=6)
        self.init_var = tk.StringVar(value="0")
        ttk.Entry(body, textvariable=self.init_var, width=20).grid(row=3, column=1, sticky="we", pady=6)

        body.columnconfigure(1, weight=1)

        ttk.Label(body, text="(must be ≥ minimum balance of type)",
                  foreground="gray").grid(row=4, column=1, sticky="w")

        btns = ttk.Frame(self.win, padding=(14, 0, 14, 14))
        btns.pack(fill="x")
        ttk.Button(btns, text="Cancel", command=self.win.destroy).pack(side="right", padx=(8, 0))
        ttk.Button(btns, text="Open", command=self._save).pack(side="right")

    def _save(self):
        try:
            cust_id  = int(self.cust_var.get().strip())
            type_id  = self.type_map[self.type_var.get()]
            branch_id = self.branch_map[self.branch_var.get()]
            initial  = float(self.init_var.get().strip() or 0)
        except (ValueError, KeyError):
            messagebox.showerror("Validation",
                                 "Please fill all required fields with valid values.",
                                 parent=self.win)
            return

        try:
            out = callproc('sp_OpenAccount',
                           [cust_id, type_id, branch_id, initial, 0],
                           out_indices=[4])
            new_id = out[0]
            messagebox.showinfo("Success",
                                f"Account {new_id} opened successfully.",
                                parent=self.win)
            self.on_save()
            self.win.destroy()
        except Exception as e:
            messagebox.showerror("Stored-procedure error",
                                 str(e), parent=self.win)
