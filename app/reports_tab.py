"""
Reports tab — exposes each of the 7 views as a selectable report.
A CSV export button writes the current Treeview content to disk so the
auditor or manager can take the data offline.
"""

import csv
import tkinter as tk
from tkinter import ttk, messagebox, filedialog

from db import fetch_all


REPORTS = {
    "Customer Summary":           "SELECT * FROM v_customer_summary ORDER BY total_balance DESC LIMIT 500",
    "Branch Performance":         "SELECT * FROM v_branch_performance ORDER BY total_deposits DESC",
    "Daily Transaction Summary":  "SELECT * FROM v_daily_transaction_summary "
                                  "WHERE txn_date >= DATE_SUB(CURDATE(), INTERVAL 60 DAY) "
                                  "ORDER BY txn_date DESC, transaction_type",
    "Loan Portfolio":             "SELECT * FROM v_loan_portfolio ORDER BY loan_amount DESC LIMIT 500",
    "Top Customers (100)":        "SELECT * FROM v_top_customers",
    "Overdue Loans":              "SELECT * FROM v_overdue_loans ORDER BY days_overdue DESC LIMIT 500",
    "Transaction Audit Trail":    "SELECT * FROM v_transaction_audit_trail "
                                  "ORDER BY transaction_date DESC LIMIT 500",
}


class ReportsTab:
    def __init__(self, parent: ttk.Frame, user: dict):
        self.parent = parent
        self.user = user
        self.current_rows: list[dict] = []
        self.current_columns: list[str] = []
        self._build_ui()

    def _build_ui(self):
        toolbar = ttk.Frame(self.parent)
        toolbar.pack(fill="x", pady=(0, 6))

        ttk.Label(toolbar, text="Report:").pack(side="left")
        self.report_var = tk.StringVar(value=list(REPORTS.keys())[0])
        ttk.Combobox(toolbar, textvariable=self.report_var,
                     values=list(REPORTS.keys()),
                     state='readonly', width=32).pack(side="left", padx=6)
        ttk.Button(toolbar, text="Run", command=self.run_report).pack(side="left", padx=4)
        ttk.Button(toolbar, text="Export CSV…",
                   command=self._export_csv).pack(side="right")

        self.info_label = ttk.Label(self.parent, text="", foreground="gray")
        self.info_label.pack(fill="x", pady=(0, 4))

        # Container for Treeview that we rebuild on each report run
        self.tree_frame = ttk.Frame(self.parent)
        self.tree_frame.pack(fill="both", expand=True)
        self.tree = None

    def run_report(self):
        name = self.report_var.get()
        sql  = REPORTS[name]
        try:
            rows = fetch_all(sql)
        except Exception as e:
            messagebox.showerror("Database error", str(e))
            return
        self.current_rows = rows
        self.current_columns = list(rows[0].keys()) if rows else []
        self._rebuild_tree()
        self.info_label.configure(text=f"{name} — {len(rows)} row(s)")

    def _rebuild_tree(self):
        for w in self.tree_frame.winfo_children():
            w.destroy()
        if not self.current_columns:
            ttk.Label(self.tree_frame, text="(no data)",
                      foreground="gray").pack(pady=20)
            return
        self.tree = ttk.Treeview(self.tree_frame,
                                 columns=self.current_columns,
                                 show='headings', height=22)
        for c in self.current_columns:
            self.tree.heading(c, text=c.replace('_', ' ').title())
            self.tree.column(c, width=130, anchor='w')
        self.tree.pack(fill="both", expand=True, side="left")

        sb = ttk.Scrollbar(self.tree_frame, orient="vertical", command=self.tree.yview)
        sb.pack(side="right", fill="y")
        self.tree.configure(yscrollcommand=sb.set)

        for r in self.current_rows:
            self.tree.insert("", "end",
                             values=[self._fmt(r[c]) for c in self.current_columns])

    @staticmethod
    def _fmt(v):
        if isinstance(v, (int,)):
            return v
        if isinstance(v, float):
            return f"{v:,.2f}"
        return str(v) if v is not None else ""

    def _export_csv(self):
        if not self.current_rows:
            messagebox.showinfo("Nothing to export",
                                "Run a report first, then export.")
            return
        path = filedialog.asksaveasfilename(
            defaultextension=".csv",
            filetypes=[("CSV files", "*.csv")],
            initialfile=self.report_var.get().lower().replace(' ', '_') + '.csv',
        )
        if not path:
            return
        try:
            with open(path, 'w', newline='', encoding='utf-8') as f:
                w = csv.DictWriter(f, fieldnames=self.current_columns)
                w.writeheader()
                for r in self.current_rows:
                    w.writerow(r)
            messagebox.showinfo("Export", f"Saved to {path}")
        except Exception as e:
            messagebox.showerror("Export error", str(e))
