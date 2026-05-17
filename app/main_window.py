"""
Main window for the Banking Management System.

Hosts a ttk.Notebook with tabs filtered by the logged-in user's role:
    Admin    — all tabs
    Manager  — Customers, Accounts, Loans, Cards, Reports
    Teller   — Customers, Accounts, Transactions, Cards
    Auditor  — Reports (read-only)
"""

import tkinter as tk
from tkinter import ttk

from customer_tab    import CustomerTab
from account_tab     import AccountTab
from transaction_tab import TransactionTab
from loan_tab        import LoanTab
from card_tab        import CardTab
from reports_tab     import ReportsTab


# Which tabs each role sees
ROLE_TABS = {
    'Admin':    ['Customers', 'Accounts', 'Transactions', 'Loans', 'Cards', 'Reports'],
    'Manager':  ['Customers', 'Accounts', 'Loans', 'Cards', 'Reports'],
    'Teller':   ['Customers', 'Accounts', 'Transactions', 'Cards'],
    'Auditor':  ['Reports'],
}

TAB_CLASSES = {
    'Customers':    CustomerTab,
    'Accounts':     AccountTab,
    'Transactions': TransactionTab,
    'Loans':        LoanTab,
    'Cards':        CardTab,
    'Reports':      ReportsTab,
}


class MainWindow:
    def __init__(self, root: tk.Tk, user: dict):
        self.root = root
        self.user = user
        root.title(f"Banking Management System — {user['username']} ({user['role']})")
        root.geometry("1200x720")
        root.minsize(1024, 640)
        root.protocol("WM_DELETE_WINDOW", root.destroy)
        self._build_ui()

    def _build_ui(self):
        # Top banner
        banner = tk.Frame(self.root, bg="#1a3a5c", height=56)
        banner.pack(fill="x")
        banner.pack_propagate(False)

        tk.Label(banner, text="BANKING MANAGEMENT SYSTEM",
                 fg="white", bg="#1a3a5c",
                 font=("Segoe UI", 13, "bold")).pack(side="left", padx=18, pady=14)

        user_frame = tk.Frame(banner, bg="#1a3a5c")
        user_frame.pack(side="right", padx=18, pady=10)
        tk.Label(user_frame,
                 text=f"{self.user['username']}",
                 fg="white", bg="#1a3a5c",
                 font=("Segoe UI", 10, "bold")).pack(anchor="e")
        tk.Label(user_frame,
                 text=f"Role: {self.user['role']}",
                 fg="#a9c3da", bg="#1a3a5c",
                 font=("Segoe UI", 8)).pack(anchor="e")

        # Notebook
        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill="both", expand=True, padx=10, pady=(8, 6))

        allowed_tabs = ROLE_TABS.get(self.user['role'], [])
        for tab_name in allowed_tabs:
            cls = TAB_CLASSES[tab_name]
            frame = ttk.Frame(self.notebook, padding=8)
            instance = cls(frame, self.user)
            self.notebook.add(frame, text=tab_name)

        # Status bar
        status = tk.Frame(self.root, bg="#e7eaef", height=22)
        status.pack(fill="x", side="bottom")
        status.pack_propagate(False)
        tk.Label(status,
                 text=f"Logged in as {self.user['username']} ({self.user['role']})  "
                      f"| Access: {len(allowed_tabs)} module(s)",
                 bg="#e7eaef", fg="#555",
                 font=("Segoe UI", 8)).pack(side="left", padx=10)
        tk.Label(status,
                 text="MySQL: banking_system",
                 bg="#e7eaef", fg="#555",
                 font=("Segoe UI", 8)).pack(side="right", padx=10)
