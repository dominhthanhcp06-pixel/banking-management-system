"""
Banking Management System — main entry point.

Run:
    cd app
    python main.py

Edit `config.py` first to set the MySQL password.
"""

import sys
import tkinter as tk
from tkinter import messagebox

from db import test_connection
from login_view import LoginWindow
from main_window import MainWindow


def main():
    # Hidden root window — keeps Tkinter happy with multiple top-levels
    root = tk.Tk()
    root.withdraw()

    # Sanity check: can we even reach MySQL?
    ok, msg = test_connection()
    if not ok:
        messagebox.showerror("Database error",
            f"Cannot connect to MySQL.\n\n{msg}\n\n"
            "Edit app/config.py with the correct credentials and try again.")
        root.destroy()
        sys.exit(1)

    # 1) LOGIN
    login = LoginWindow(root)
    root.wait_window(login.window)
    if login.user is None:
        root.destroy()
        return

    # 2) MAIN WINDOW (becomes the new root for the app)
    MainWindow(root, login.user)
    root.deiconify()
    root.mainloop()


if __name__ == "__main__":
    main()
