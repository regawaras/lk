# lk
⚡ A lightning-fast, POSIX-compliant terminal journaling system. Features chronological logging, dynamic tags, XDG-standard paths, and hybrid interactive modes for dash/bash/zsh.

# 🗃️ LogKlerk (LK)

**LogKlerk** is a lightning-fast, highly structured, and **100% POSIX-compliant** terminal-based daily journaling and note-taking system. 

Designed for developers, sysadmins, and CLI enthusiasts, LogKlerk acts as your chronological brain dump. It uses standard UNIX tools to provide an interactive journaling experience, dynamic taxonomy (tagging), and advanced recursive search without the bloat of heavy GUI apps.

## ✨ Key Features

- **POSIX-Compliant Core**: Written in pure `sh`. Runs flawlessly on `dash`, `bash`, `zsh`, Alpine Linux, NixOS, and macOS.
- **Hybrid Interactive Mode**: Automatically detects if you are using `bash` to enable GNU Readline (arrow keys navigation), while safely falling back to standard `read` on strict POSIX shells like `dash`.
- **XDG Base Directory Standard**: Keeps your `$HOME` clean. Data goes to `~/.local/share/logklerk`, configs to `~/.config/logklerk`.
- **Concurrency Safe**: Uses file-descriptor locking (`flock -x 9`) to prevent data corruption if multiple terminals write simultaneously.
- **Dynamic Taxonomy**: Create custom quick-logging alias tags on the fly without touching the source code.
- **Location Manager**: Instantly move your data directory to synced folders (e.g., Dropbox, Nextcloud) with a built-in config manager.

---

## 🚀 Installation

Since LogKlerk is a collection of shell functions and aliases, it needs to be **sourced** into your active shell environment, not executed as a standalone binary.

**1. Download the script:**
```bash
mkdir -p ~/.config/logklerk
curl -o ~/.config/logklerk/lk.sh [https://raw.githubusercontent.com/regawaras/lk/main/lk.sh](https://raw.githubusercontent.com/regawaras/lk/main/lk.sh)
```

**2. Source it in your shell profile:**

For **Bash/Zsh** (`~/.bashrc` or `~/.zshrc`):
```bash
echo '. "$HOME/.config/logklerk/lk.sh"' >> ~/.bashrc
source ~/.bashrc
```

For strict **POSIX/Dash** (`~/.profile` and `~/.shinit`):
```bash
echo 'export ENV="$HOME/.shinit"' >> ~/.profile
echo '. "$HOME/.config/logklerk/lk.sh"' >> ~/.shinit
```

---

## 📖 Core Usage

LogKlerk uses simple commands for its core loop: **Write (`lk`)**, **Read (`clk`)**, and **Search (`lks`)**.

### 1. Writing Notes (`lk`)
```bash
# Add a quick one-liner
lk "Successfully migrated my server to NixOS"

# Open Interactive Mode (Chronological prompt)
lk
>> 

# Use predefined global tags
todo "Fix the Nginx reverse proxy routing"
ideas "Build an automated backup script using rsync"
sog "How to configure dash as default shell"
problems "Kernel panic after updating NVIDIA drivers"
```

### 2. Reading Notes (`clk`)
```bash
clk                 # View all notes for TODAY
clks                # View today's main summaries (Daily & Hourly)
clk 2026-04-12      # View notes from a specific date
clk -m              # View all daily summaries for the current month
clk 08-12           # View notes logged today between 08:00 and 12:00
```

### 3. Advanced Search (`lks`)
```bash
lks "Nginx"            # Search recursively across all notes globally
lks -t "Nginx"         # Search only in today's notes
lks -08 "server"       # Search across all time, but ONLY at 08:xx AM
lks 2026-04 "Linux"    # Search within a specific month (April 2026)
```

---

## ⚙️ Advanced Configuration

### 🏷️ Dynamic Custom Tags
You can generate your own custom logging aliases on the fly. These are saved persistently in `~/.config/logklerk/lk_tags`.

```bash
# Create a tag 'wrv' for Vim writing
lk -add wrv "Writing on Vim"

# Use it immediately
wrv "Drafting the README.md documentation"
# Output: - 15:30:00 - [[Writing on Vim]] >> Drafting the README.md documentation
```

### 📁 Location Manager
Don't want your notes in `~/.local/share`? Move them to your synced folders seamlessly:

```bash
# Change the default directory to a custom path
lk -set -dir ~/Dropbox/LogKlerk

# Reset to XDG default (~/.local/share/logklerk)
lk -set -dir -default

# Set to ~/LogKlerk
lk -set -dir -home
```

### 📝 Daily & Hourly Summaries
Add high-level summaries to the top of your markdown files to build a table of contents over time.
```bash
# Set today's main summary
lk -set -today "Focused on backend optimization"

# Set a summary for a specific historical date
lk -set 2026-04-10 "Vacation day"

# Set a summary for a specific time block today (e.g., 08:00 to 10:00)
lk -set 08-10 "Deep Work: Database Refactoring"
```

### ⌨️ Manual Editing
Need to fix a typo? Drop directly into your favorite `$EDITOR` (defaults to `vim`):
```bash
vlk                 # Edit today's markdown file
vlk 2026-04-10      # Edit a specific past date
```

---

## 🏗️ Data Structure Under the Hood

LogKlerk generates clean, readable Markdown files structured hierarchically by Year and Month (`YYYY/YYYY-MM/YYYY-MM-DD.md`). You are never locked into a proprietary database.

**Example output of `~/.local/share/logklerk/2026/2026-04/2026-04-12.md`:**
```markdown
- [[2026-04-12]] - Focused on backend optimization
    created: [[2026-04-12]] - 10:00:00
    - 08:00 - Deep Work: Database Refactoring
    - 15:00 - Open Source Contributions

    - 08:00 - (Hourly Summary)
        - 08:15:30 - [[TODO]] >> Fix the Nginx reverse proxy routing
    - 15:00 - (Hourly Summary)
        - 15:30:00 - [[Writing on Vim]] >> Drafting the README.md
```

## 📄 License
This project is licensed under the MIT License. Feel free to fork, modify, and improve!
