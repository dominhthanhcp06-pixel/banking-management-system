"""Cards tab — list, issue new, block."""

import tkinter as tk
from tkinter import ttk, messagebox

from db import fetch_all, callproc


class CardTab:
    def __init__(self, parent: ttk.Frame, user: dict):
        self.parent = parent
        self.user = user
        self._build_ui()
        self.refresh()

    def _build_ui(self):
        toolbar = ttk.Frame(self.parent)
        toolbar.pack(fill="x", pady=(0, 6))
        ttk.Button(toolbar, text="Refresh", command=self.refresh).pack(side="left")
        ttk.Button(toolbar, text="+ Issue Card",
                   command=self._issue_dialog).pack(side="right")
        ttk.Button(toolbar, text="Block selected",
                   command=self._block_action).pack(side="right", padx=4)

        cols = ('card_id', 'card_number_masked', 'account_id', 'card_type',
                'issue_date', 'expiry_date', 'status')
        self.tree = ttk.Treeview(self.parent, columns=cols, show='headings', height=22)
        for c, w in zip(cols, (70, 180, 90, 90, 110, 110, 90)):
            self.tree.heading(c, text=c.replace('_', ' ').title())
            self.tree.column(c, width=w, anchor='w')
        self.tree.pack(fill="both", expand=True, side="left")
        sb = ttk.Scrollbar(self.parent, orient="vertical", command=self.tree.yview)
        sb.pack(side="right", fill="y")
        self.tree.configure(yscrollcommand=sb.set)

    def refresh(self):
        try:
            rows = fetch_all(
                "SELECT card_id, card_number, account_id, card_type, "
                "       issue_date, expiry_date, status "
                "FROM cards ORDER BY card_id DESC LIMIT 500"
            )
        except Exception as e:
            messagebox.showerror("Database error", str(e))
            return
        self.tree.delete(*self.tree.get_children())
        for r in rows:
            cn = r['card_number']
            # mask all but last 4 digits
            masked = '*' * 12 + cn[-4:] if len(cn) >= 4 else cn
            self.tree.insert("", "end", values=(
                r['card_id'], masked, r['account_id'], r['card_type'],
                r['issue_date'], r['expiry_date'], r['status'],
            ))

    def _block_action(self):
        if self.user['role'] not in ('Admin', 'Manager', 'Teller'):
            messagebox.showwarning("Permission",
                                   "Your role cannot block cards.")
            return
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("Select", "Select a card row first.")
            return
        card_id = int(self.tree.item(sel[0])['values'][0])
        if not messagebox.askyesno("Confirm", f"Block card {card_id}?"):
            return
        try:
            callproc('sp_BlockCard', [card_id])
            messagebox.showinfo("Done", f"Card {card_id} blocked.")
            self.refresh()
        except Exception as e:
            messagebox.showerror("Stored-procedure error", str(e))

    def _issue_dialog(self):
        if self.user['role'] not in ('Admin', 'Manager', 'Teller'):
            messagebox.showwarning("Permission",
                                   "Your role cannot issue cards.")
            return
        IssueCardDialog(self.parent.winfo_toplevel(), on_save=self.refresh)


# ----------------------------------------------------------------------
class IssueCardDialog:
    def __init__(self, parent, on_save):
        self.on_save = on_save
        self.win = tk.Toplevel(parent)
        self.win.title("Issue card")
        self.win.geometry("380x250")
        self.win.transient(parent)
        self.win.grab_set()

        body = ttk.Frame(self.win, padding=14)
        body.pack(fill="both", expand=True)

        self.acc_var  = tk.StringVar()
        self.type_var = tk.StringVar(value="ATM")
        self.pin_var  = tk.StringVar()

        ttk.Label(body, text="Account ID *").grid(row=0, column=0, sticky="w", pady=6)
        ttk.Entry(body, textvariable=self.acc_var, width=20).grid(row=0, column=1, sticky="we", pady=6)

        ttk.Label(body, text="Card type *").grid(row=1, column=0, sticky="w", pady=6)
        ttk.Combobox(body, textvariable=self.type_var,
                     values=['ATM','Debit','Credit'],
                     state='readonly', width=18).grid(row=1, column=1, sticky="we", pady=6)

        ttk.Label(body, text="4-digit PIN *").grid(row=2, column=0, sticky="w", pady=6)
        ttk.Entry(body, textvariable=self.pin_var, show='•',
                  width=20).grid(row=2, column=1, sticky="we", pady=6)

        body.columnconfigure(1, weight=1)

        btns = ttk.Frame(self.win, padding=(14, 0, 14, 14))
        btns.pack(fill="x")
        ttk.Button(btns, text="Cancel", command=self.win.destroy).pack(side="right", padx=(8, 0))
        ttk.Button(btns, text="Issue", command=self._save).pack(side="right")

    def _save(self):
        try:
            acc = int(self.acc_var.get().strip())
            ctype = self.type_var.get()
            pin = self.pin_var.get().strip()
            if not pin.isdigit() or len(pin) != 4:
                raise ValueError("PIN must be exactly 4 digits.")
        except ValueError as e:
            messagebox.showerror("Validation", str(e), parent=self.win)
            return
        try:
            out = callproc('sp_IssueCard',
                           [acc, ctype, pin, 0],
                           out_indices=[3])
            messagebox.showinfo("Success", f"Card {out[0]} issued.", parent=self.win)
            self.on_save()
            self.win.destroy()
        except Exception as e:
            messagebox.showerror("Stored-procedure error", str(e), parent=self.win)
