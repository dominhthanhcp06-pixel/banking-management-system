"""
Login dialog — authenticates the bank-staff user against the `users` table.
SHA-256 hash comparison (matching the hash format seeded by load_data.py).
"""

import hashlib
import tkinter as tk
from tkinter import ttk, messagebox

from db import fetch_one, execute


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


class LoginWindow:
    def __init__(self, parent: tk.Tk):
        self.user: dict | None = None
        self.window = tk.Toplevel(parent)
        self.window.title("Banking Management System — Login")
        self.window.geometry("440x360")
        self.window.resizable(False, False)
        self.window.protocol("WM_DELETE_WINDOW", self._cancel)
        self._build_ui()
        self._center()

    def _center(self):
        self.window.update_idletasks()
        w = self.window.winfo_width()
        h = self.window.winfo_height()
        x = (self.window.winfo_screenwidth() - w) // 2
        y = (self.window.winfo_screenheight() - h) // 2
        self.window.geometry(f"+{x}+{y}")

    def _build_ui(self):
        # Header
        header = tk.Frame(self.window, bg="#1a3a5c", height=80)
        header.pack(fill="x")
        header.pack_propagate(False)
        tk.Label(header, text="BANKING MANAGEMENT SYSTEM",
                 fg="white", bg="#1a3a5c",
                 font=("Segoe UI", 14, "bold")).pack(pady=(15, 0))
        tk.Label(header, text="Internal Staff Portal",
                 fg="#a9c3da", bg="#1a3a5c",
                 font=("Segoe UI", 9)).pack()

        body = ttk.Frame(self.window, padding=(30, 25, 30, 10))
        body.pack(fill="both", expand=True)

        ttk.Label(body, text="Username").grid(row=0, column=0, sticky="w", pady=(0, 4))
        self.username_var = tk.StringVar()
        user_entry = ttk.Entry(body, textvariable=self.username_var, width=32)
        user_entry.grid(row=1, column=0, sticky="we", pady=(0, 10))

        ttk.Label(body, text="Password").grid(row=2, column=0, sticky="w", pady=(0, 4))
        self.password_var = tk.StringVar()
        ttk.Entry(body, textvariable=self.password_var, show="•",
                  width=32).grid(row=3, column=0, sticky="we", pady=(0, 14))

        # Demo credentials hint
        hint_frame = tk.Frame(body, bg="#f4f6f9", padx=10, pady=8)
        hint_frame.grid(row=4, column=0, sticky="we")
        tk.Label(hint_frame, text="Demo credentials",
                 fg="#666", bg="#f4f6f9",
                 font=("Segoe UI", 8, "bold")).pack(anchor="w")
        tk.Label(hint_frame,
                 text="admin / admin123        manager1 / manager123\n"
                      "teller1 / teller123       auditor1 / auditor123",
                 fg="#666", bg="#f4f6f9",
                 font=("Consolas", 8), justify="left").pack(anchor="w")

        btns = ttk.Frame(self.window, padding=(30, 0, 30, 15))
        btns.pack(fill="x")
        ttk.Button(btns, text="Cancel", command=self._cancel).pack(side="right", padx=(8, 0))
        ttk.Button(btns, text="Sign in", command=self._login).pack(side="right")

        self.window.bind("<Return>", lambda e: self._login())
        user_entry.focus_set()

    def _login(self):
        username = self.username_var.get().strip()
        password = self.password_var.get()
        if not username or not password:
            messagebox.showwarning("Validation",
                                   "Please enter both username and password.",
                                   parent=self.window)
            return
        try:
            row = fetch_one(
                "SELECT user_id, username, password_hash, employee_id, role, is_active "
                "FROM users WHERE username = %s", (username,))
        except Exception as e:
            messagebox.showerror("Database error", str(e), parent=self.window)
            return

        if not row:
            messagebox.showerror("Login failed",
                                 "User not found.", parent=self.window)
            return
        if not row['is_active']:
            messagebox.showerror("Login failed",
                                 "This account is inactive.", parent=self.window)
            return
        if row['password_hash'] != _sha256(password):
            messagebox.showerror("Login failed",
                                 "Incorrect password.", parent=self.window)
            return

        try:
            execute("UPDATE users SET last_login = NOW() WHERE user_id = %s",
                    (row['user_id'],))
        except Exception:
            pass

        self.user = {
            'user_id':     row['user_id'],
            'username':    row['username'],
            'role':        row['role'],
            'employee_id': row['employee_id'],
        }
        self.window.destroy()

    def _cancel(self):
        self.user = None
        self.window.destroy()
