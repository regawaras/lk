# LogKlerk (LK)

> *"Just Open Terminal, Type, Enter, Forget Brutal"*

**LogKlerk** is a lightning-fast, highly structured terminal journaling system. It acts as your chronological brain dump: every line you type is timestamped and filed into a plain Markdown vault, organized by year, month and day. No database, no GUI, no lock-in.

## 📸 Screenshots & Examples
### Full Desktop Setup View
![LogKlerk Other Example](assets/other-example.jpg)

### Minimalistic Setup View
![LogKlerk Terminal Screenshot](assets/20261128T091701-ss.png)

### Example Comparison
| Minimalistic Setup View | Full Desktop Setup View |
| :---: | :---: |
| ![LogKlerk Terminal Screenshot](assets/20261128T091701-ss.png) | ![LogKlerk Other Example](assets/other-example.jpg) |

## Multiple Programming Language
LogKlerk comes in three flavors:

| | **Rust version** (main) | **Shell version** (alternative) | **Assembly version** (experimental) |
|---|---|---|---|
| Status | `experimental` · `v0.0.3` | Original implementation | `v0.0.1` · CSV format |
| Form | Single binary, `std` only, no crates | POSIX `sh` functions, sourced into your shell | Standalone x86-64 Linux binary, no libc, pure syscalls |
| Best for | Speed, interactive mode, analytics, everyday use | Minimal systems, strict POSIX shells, zero compilation | Ultra-lightweight binary, zero dependencies, CSV logging |
| Jump to | [Rust version](#-rust-version-main) | [Shell version](#-shell-version-alternative) | [Assembly version](#-assembly-version-v001) |

---

## ✨ Key Features

- **Chronological logging**: everything is stamped `HH:MM:SS` and inserted into the right hour block automatically.
- **Hybrid interactive mode**: a mini shell + journal. Type a note and it is logged; type a real command (`ls`, `git status`, `cd ...`) and it runs *and* is logged.
- **Everything is a log**: every `lk` command (`lkc`, `lkcd`, `lksum`, ...) and every input typed in interactive mode is recorded with a timestamp.
- **Dynamic taxonomy**: create your own quick-logging tags (`todo`, `ideas`, ...) on the fly.
- **Summaries & plans**: add hourly, daily, monthly and yearly summaries that build a table of contents over time.
- **Search & analytics** *(Rust)*: ranking, stats, charts, word frequency, lexical diversity, snapshots and more.
- **Plain vault**: Markdown (`YYYY/YYYY-MM/YYYY-MM-DD.md`) in Rust/Shell, or RFC 4180 CSV (`<timestamp>.csv`) in Assembly. Open it with any editor.
- **Concurrency safe**: simultaneous terminals don't corrupt your logs.

---

# 🦀 Rust Version (Main)

A port of the original shell modules into one binary with **no external dependencies** (standard library only). Targets Linux, macOS and BSD (it uses `localtime_r` from libc; Windows is not supported).

## 🚀 Installation

**1. Build**

```bash
git clone https://github.com/regawaras/lk.git
cd lk/rust
cargo build --release
```

The Rust source lives in `lk/rust/`:

```text
lk/rust/
├── Cargo.toml
└── src/
    ├── main.rs            # LogKlerk core (v0.0.3)
    └── default_tags.rs    # built-in tags, loaded via `mod default_tags;`
```

The binary is built as `target/release/lk` (make sure `name = "lk"` is set in `Cargo.toml`).

**2. Put the binary on your `PATH`**

```bash
install -m 755 target/release/lk ~/.local/bin/lk
```

**3. Create the command shortcuts** (optional, recommended)

```bash
lk -install ~/.local/bin
```

This creates symlinks (`lkc`, `lkcd`, `lks`, `lksum`, `todo`, `ideas`, ...) that all point to the one binary, so you can type `lkc` instead of `lk lkc`. Make sure the directory is on your `PATH`.

**4. Enable `cd` persistence** (optional, recommended)

A program can't change its parent shell's directory, so LogKlerk ships a tiny wrapper. Add this to `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(lk --init)"
```

For fish:

```fish
lk --init fish | source
```

With the wrapper installed, if you `cd` somewhere inside interactive mode, your shell lands in that same directory when you exit. Without it, LogKlerk prints a short hint on exit if the directory changed.

## ⚙️ Configuration

On first run, LogKlerk creates its config at:

```text
~/.config/lk/experimental/v0.0.3/lk.conf
```

> Config folders are versioned. When upgrading, copy your settings from the previous version's folder.

Default `lk.conf`:

```bash
LK_DIR="$HOME/lk"
LK_TAIL_LINES="10"
LK_DEFAULT_FORMAT=".md"
LK_COLOR_HOURLY_SUMMARY="yellow"
```

| Key | Meaning | Default |
| --- | --- | --- |
| `LK_DIR` | Where your vault lives (can also be set as an environment variable) | `~/lk` |
| `LK_TAIL_LINES` | Lines of context shown after logging | `10` |
| `LK_COMMAND_TAIL_LINES` | Same, after a shell command in interactive mode | `3` |
| `LKSET_TAIL_LINES` | Context lines shown after `lkset` / `lkconf` | `5` |
| `LK_DEFAULT_FORMAT` | Log file extension | `.md` |
| `LK_SNAP_DIR` | Where `lksnap` stores snapshots | `~/snapshots/lk` |
| `LK_COLOR_HOURLY_SUMMARY` | Color of the `(Hourly Summary)` placeholder | `yellow` |

Change any value from inside LogKlerk:

```bash
lkconf LK_TAIL_LINES="5"
lkconf LK_COLOR_HOURLY_SUMMARY="#FF8800"
```

**Color formats** for `LK_COLOR_HOURLY_SUMMARY`: a name (`yellow`, `amber`, `gold`, `orange`, `red`, `green`, `lime`, `cyan`, `blue`, `purple`, `magenta`, `pink`, `white`, `grey`), hex (`#RRGGBB`), decimal `R,G,B` (e.g. `255,221,0`), or a 0-255 terminal color index.

Run `lk -c` to view your current configuration. Edit the banner with `lkv banner`.

## 📖 Core Usage

LogKlerk's core loop is **Write (`lk`)**, **Read (`lkc`)** and **Search (`lks`)**.

### 1. Writing

```bash
# Quick one-liner
lk "Successfully migrated my server to NixOS"

# Log with a version tag
lk -v "Tested the new release"

# Log with a taxonomy alias
lk @todo "Fix the Nginx reverse proxy routing"
todo "Fix the Nginx reverse proxy routing"      # same thing, via symlink

# Open interactive mode
lk
```

### 2. Interactive Mode

Run `lk` (or `lki`) with no arguments:

```text
Log to ~/lk/2026/2026-04/2026-04-12.md
>> 
```

| You type | What happens |
| --- | --- |
| Plain text | Logged with a timestamp |
| `todo` | Switches the active category to `todo` (following lines are logged as todos) |
| `todo Fix nginx` | Logs that single line as a todo |
| `ls`, `git status`, `cd ~/proj` | Runs in your shell **and** is logged |
| `lkc`, `lkcd`, `lksum ...` | Runs the LK module **and** is logged |
| `clear` | Redraws the header (logged) |
| `-q` / `exit` / `quit` | Leaves interactive mode (logged) |

Every non-empty input is written to the log, including exits and category switches. Only a bare Enter is ignored.

### 3. Reading

```bash
lkc                 # Everything logged today
lkc 20260412        # A specific date (also 2026-04-12)
lkc 14              # Today's 14:00 block
lkc 08-12           # Today between 08:00 and 12:00
lkc -m              # Daily summaries for the current month
lkc -y              # Daily summaries for the current year
lkc -a              # Every daily summary, ever
lkch                # Current hour block
lkcd [YYYYMMDD]     # Daily + hourly summary recap
lkcm [YYYYMM]       # All daily summaries in a month
lkcy [YYYY]         # Historical timeline (min|mid|max|fit|full)
```

### 4. Searching

```bash
lks "Nginx"            # Search the whole vault
lks -t "Nginx"         # Today only
lks -08 "server"       # Any day, but only entries from the 08:xx hour
lks 2026-04 "Linux"    # A specific month
```

### 5. Summaries & Plans

```bash
lksum 2026 "Year of the terminal"           # Yearly
lksum 202604 "Backend month"                # Monthly
lksum 20260422 "Focused on optimization"    # Daily
lksum 14 "Deep work: database refactor"     # Hour 14 today
lksum 08-10 "Morning block"                 # Batch of hours

lkplan 20260423 "Ship v0.0.3"               # Same targets, tagged ![PLAN]!
```

## 🏷️ Dynamic Tags (Taxonomy)

```bash
lkset wbl="[[Web]]"            # New alias: wbl -> [[Web]] >>
lkfiles ideas="[[Ideas]]"      # Exclusive alias: logs into its own folder
lknote groceries="groceries.md"  # Alias pointing to a static note
lk tags                        # List every registered alias
```

Use them directly or from interactive mode:

```bash
wbl "Read the htmx docs"
# - 15:30:00 - [[Web]] >> Read the htmx docs
```

## 🧰 Full Command Reference

Type `lkh` (or `lk -h`) for the built-in manual. Overview:

| Group | Commands |
| --- | --- |
| **Core** | `lk`, `lki`, `lk -v`, `lk @alias`, `lk -e`, `lk -pwd`, `lk -c`, `lk --init` |
| **Taxonomy** | `lkset`, `lkfiles`, `lknote`, `lk tags`, `lk -install` |
| **Summaries** | `lksum`, `lkplan` |
| **Reader** | `lkc`, `lkcd`, `lkch`, `lkcm`, `lkcy` |
| **Search & analytics** | `lks`, `lksort`, `lkstat`, `lkrank`, `lkchart`, `lkword`, `lkwords`, `lkdiversity`, `lkyaml`, `lkweight`, `lkdistraction`, `lkvoid`, `lkhour`, `lkminute`, `lksecond` |
| **Maintenance** | `lkv`, `lkconf`, `lkspace`, `lksnap` |

## 🏗️ Data Structure

```text
~/lk/
└── 2026/
    └── 2026-04/
        └── 2026-04-12.md
```

Example daily file:

```markdown
- # [[2026-04-12]] - Focused on backend optimization
    created: [[2026-04-12]] - 08:05:12
- ## 08:00 - (Hourly Summary)
  - 08:15:30 - [[TODO]] >> Fix the Nginx reverse proxy routing
  - 08:40:02 - [[zsh]] >> git status
  - 08:41:10 - [[lk]] >> lkc
- ## 15:00 - (Hourly Summary)
  - 15:30:00 - [[Writing on Vim]] >> Drafting the README.md
```

Entries are inserted in chronological order into their hour block. Commands run inside interactive mode are tagged with your shell (e.g. `[[zsh]] >>`), and LK's own commands with `[[lk]] >>`.

---

# 🐚 Shell Version (Alternative)

The original **100% POSIX-compliant** implementation, written in pure `sh`. Choose it when you can't (or don't want to) compile anything, or you're on a minimal system such as Alpine, NixOS or a strict `dash` environment.

## Features

- **POSIX core**: runs on `dash`, `bash`, `zsh`, Alpine Linux, NixOS and macOS.
- **Hybrid interactive mode**: detects `bash` to enable GNU Readline (arrow-key navigation) and falls back to plain `read` on strict POSIX shells.
- **XDG Base Directory standard**: data in `~/.local/share/logklerk`, config in `~/.config/logklerk`.
- **Concurrency safe**: file-descriptor locking (`flock -x 9`).
- **Location manager**: move your data directory to a synced folder (Dropbox, Nextcloud, ...) with one command.

## Installation

LogKlerk (shell) is a collection of functions and aliases, so it must be **sourced** into your shell, not executed.

**1. Download the script**

```bash
mkdir -p ~/.config/logklerk
curl -o ~/.config/logklerk/lk.sh https://raw.githubusercontent.com/regawaras/lk/main/lk.sh
```

**2. Source it from your shell profile**

Bash / Zsh (`~/.bashrc` or `~/.zshrc`):

```bash
echo '. "$HOME/.config/logklerk/lk.sh"' >> ~/.bashrc
source ~/.bashrc
```

Strict POSIX / Dash (`~/.profile` and `~/.shinit`):

```bash
echo 'export ENV="$HOME/.shinit"' >> ~/.profile
echo '. "$HOME/.config/logklerk/lk.sh"' >> ~/.shinit
```

## Usage

> The shell version uses its own flag-style commands (`lk -set`, `lk -add`), which differ from the Rust version's `lksum` / `lkset`. Don't mix the two command sets.

**Writing**

```bash
lk "Successfully migrated my server to NixOS"
lk                                   # interactive mode

todo "Fix the Nginx reverse proxy routing"
ideas "Build an automated backup script using rsync"
sog "How to configure dash as default shell"
problems "Kernel panic after updating NVIDIA drivers"
```

**Reading**

```bash
lkc                 # All notes for today
lkcs                # Today's main summaries (daily & hourly)
lkc 2026-04-12      # A specific date
lkc -m              # Daily summaries for the current month
lkc 08-12           # Today between 08:00 and 12:00
```

**Searching**

```bash
lks "Nginx"            # Global search
lks -t "Nginx"         # Today only
lks -08 "server"       # Only at 08:xx
lks 2026-04 "Linux"    # A specific month
```

**Custom tags** (stored in `~/.config/logklerk/lk_tags`)

```bash
lk -add wrv "Writing on Vim"
wrv "Drafting the README.md documentation"
# - 15:30:00 - [[Writing on Vim]] >> Drafting the README.md documentation
```

**Location manager**

```bash
lk -set -dir ~/Dropbox/LogKlerk     # custom path
lk -set -dir -default               # XDG default (~/.local/share/logklerk)
lk -set -dir -home                  # ~/LogKlerk
```

**Summaries**

```bash
lk -set -today "Focused on backend optimization"
lk -set 2026-04-10 "Vacation day"
lk -set 08-10 "Deep Work: Database Refactoring"
```

**Manual editing** (uses `$EDITOR`, defaults to `vim`)

```bash
lkv                 # today's file
lkv 2026-04-10      # a specific date
```

**Data layout**

```text
~/.local/share/logklerk/2026/2026-04/2026-04-12.md
```

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

---

# ⚙️ Assembly Version (v0.0.1)

A standalone **x86-64 Linux** implementation written in GNU Assembler (`as`, Intel syntax) with **no `libc`** and pure Linux system calls (`clock_gettime`, `open`, `write`, `mkdir`, `ioctl`, `exit`). Instead of Markdown files, it writes RFC 4180 CSV entries (`date,context,activity`).

## Features

- **Zero dependencies**: no `libc`, no runtime, fixed `.bss` buffers with explicit bounds checks, and no recursion or stack arrays.
- **CSV output with escaping**: quotes fields containing `,` or `"`, doubles internal `"`, and replaces CR/LF with spaces so each entry stays on a single line.
- **Race-free & concurrency safe**: creates log files with `O_CREAT|O_EXCL` (mode `0600`), rejects symlinks with `O_NOFOLLOW`, and writes each complete row with `O_APPEND`.
- **Configurable timezone & taxonomy**: supports `DIR`, `TZ_OFFSET` (in seconds), and up to 32 `[taxonomy]` entries in `lk.conf`.

## 🚀 Build & Installation

**1. Assemble and link**

```bash
as --64 -g lk.s -o lk.o
ld -z noexecstack -z relro -z now -o lk lk.o
```

**2. Put the binary on your `PATH`**

```bash
install -m 755 lk ~/.local/bin/lk
```

## ⚙️ Configuration

Configuration is read from `~/.config/logklerk/lk.conf` (falling back to built-in defaults if missing or empty):

```ini
[settings]
DIR="$HOME/.local/share/logklerk/"
TZ_OFFSET=0
[taxonomy]
gg="Googling"
gam="Google AI Mode"
claude="Claude"
soy="Search on Youtube"
diary="Diary"
com="Commentary"
```

- `DIR`: log directory (`$HOME` or leading `~` is expanded; trailing `/` is added automatically; created with `mkdir -p` mode `0700`).
- `TZ_OFFSET`: timezone offset in seconds added to UTC time (clamped at `0` if negative).
- `[taxonomy]`: maps shortcut keys to context names (up to 32 entries).

## 📖 Usage

```bash
lk -h | --help              # Show usage help
lk                          # Interactive mode (exit, quit, or Ctrl-D to quit; shows `lk> ` on a TTY)
lk <key> <text...>          # Log with context from [taxonomy]
lk <command...>             # Unknown first token falls back to context "bash"
```

### Data Layout & Format

Log files are named `<timestamp>.csv` (derived from the first entry's timestamp) inside `DIR`:

```text
~/.local/share/logklerk/
└── 20261128T162600.csv
```

Example CSV content:

```csv
date,context,activity
20261128T162600.123,Googling,x86-64 linux syscall clock_gettime
20261128T162615.450,bash,ls -la
```

---

# 🔄 Migrating Between Versions

The Rust and Shell versions both write plain Markdown files in the same `YYYY/YYYY-MM/YYYY-MM-DD.md` layout, so the Rust version is designed to read an existing shell vault.

1. **Back up first**: copy your vault directory somewhere safe.
2. Point the Rust version at your existing data in `lk.conf`:

   ```bash
   lkconf LK_DIR="$HOME/.local/share/logklerk"
   ```

3. Open a few days with `lkc <date>` and confirm they look right before relying on it.

Config files, tags and commands are **not** shared across versions: re-create your aliases with `lkset` / `lkfiles` in the Rust version, or in `lk.conf` for the Assembly version.

---

## 📄 License

This project is licensed under the MIT License. Feel free to fork, modify and improve!
