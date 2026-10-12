import tkinter as tk
from tkinter import ttk
import webbrowser
from pl_highlights_links import fetch_highlights, load_existing_flags, save_flags

class HighlightsApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Premier League Highlights")
        self.flags = load_existing_flags()
        self.bool_vars = {}

        # Uniform background color matching Watch button
        self.BG_COLOR = "#f0f0f0"

        # Scrollable frame setup
        self.frame = ttk.Frame(root)
        self.frame.pack(fill="both", expand=True)

        self.canvas = tk.Canvas(self.frame, borderwidth=0, highlightthickness=0, background=self.BG_COLOR)
        self.scrollbar = ttk.Scrollbar(self.frame, orient="vertical", command=self.canvas.yview)
        self.scrollable_frame = tk.Frame(self.canvas, background=self.BG_COLOR)

        self.scrollable_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        )

        self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)

        self.canvas.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="right", fill="y")

        # Fetch button
        self.update_button = ttk.Button(root, text="Fetch Latest Highlights", command=self.update_highlights)
        self.update_button.pack(pady=10)

        self.rows = []

        # Column headers
        headers = ["Watched", "Title", "Link", "Uploaded"]
        header_font = ("TkDefaultFont", 12, "bold")
        for col, h in enumerate(headers):
            lbl = tk.Label(self.scrollable_frame, text=h, font=header_font, bg=self.BG_COLOR)
            lbl.grid(row=0, column=col, sticky="w", padx=5, pady=2)
        self.scrollable_frame.grid_columnconfigure(1, weight=1)  # Title column expands

        # Fetch automatically on startup
        self.update_highlights()

    def open_link(self, url):
        webbrowser.open_new_tab(url)

    def update_highlights(self):
        # Remove previous content rows (skip header row 0)
        for widget in self.scrollable_frame.winfo_children():
            if int(widget.grid_info().get("row", 0)) > 0:
                widget.destroy()
        self.rows.clear()
        self.bool_vars.clear()

        videos = fetch_highlights()

        for i, v in enumerate(videos, start=1):
            vid = v["videoId"]
            title = v["title"]
            dt = v["datetime_obj"]
            timestamp = dt.strftime("%A %-m/%-d, %-I:%M %p")
            timestamp = timestamp[:-2] + timestamp[-2:].lower()

            # BooleanVar for checkbox
            watched_flag = self.flags.get(vid, "NOT_WATCHED")
            bool_var = tk.BooleanVar(value=(watched_flag == "WATCHED"))
            self.bool_vars[vid] = bool_var  # keep reference alive

            # Checkbox
            cb = tk.Checkbutton(
                self.scrollable_frame,
                variable=bool_var,
                command=lambda vid=vid, var=bool_var: self.toggle_flag(vid, var),
                fg="black",
                bg=self.BG_COLOR,
                activebackground=self.BG_COLOR,
                highlightthickness=0,
                bd=0
            )
            cb.grid(row=i, column=0, sticky="nw", padx=5, pady=2)

            cb.update_idletasks()

            # Title label
            title_lbl = tk.Label(
                self.scrollable_frame,
                text=title,
                wraplength=600,
                justify="left",
                bg=self.BG_COLOR,
                font=("TkDefaultFont", 12)
            )
            title_lbl.grid(row=i, column=1, sticky="w", padx=5, pady=2)

            # Watch button
            link_btn = ttk.Button(
                self.scrollable_frame,
                text="Watch",
                command=lambda url=f"https://www.youtube.com/watch?v={vid}": self.open_link(url)
            )
            link_btn.grid(row=i, column=2, padx=5, pady=2)

            # Timestamp label
            ts_lbl = tk.Label(
                self.scrollable_frame,
                text=timestamp,
                bg=self.BG_COLOR,
                font=("TkDefaultFont", 12)
            )
            ts_lbl.grid(row=i, column=3, padx=5, pady=2)

            self.rows.append((cb, title_lbl, link_btn, ts_lbl))

        # Autosize window to content
        self.root.update_idletasks()
        width = self.scrollable_frame.winfo_reqwidth() + 40  # leave room for scrollbar
        height = min(self.scrollable_frame.winfo_reqheight() + 50, 800)
        self.root.geometry(f"{width}x{height}")

    def toggle_flag(self, vid, var):
        self.flags[vid] = "WATCHED" if var.get() else "NOT_WATCHED"
        save_flags(self.flags)

if __name__ == "__main__":
    root = tk.Tk()
    app = HighlightsApp(root)
    root.mainloop()
