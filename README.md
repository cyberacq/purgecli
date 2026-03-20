# PurgeCLI
A secure, interactive command-line utility that creates a trash environment for Linux server (and is compatible with Desktop variants), which permanently deletes all files and directories from your configured trash directory, including hidden files and nested structures.

- Complete deletion — Purges all trash contents including hidden files and directories (`.dotfiles`, nested dirs, etc.)
- Rescue system — Save specific items before purging; manage rescued files later with `--rescue`
- Real-time progress — Live progress bar with estimated time remaining and percentage completion
- Unicode support — Automatically uses Braille Unicode characters for enhanced visuals when your terminal supports it
- Error handling — Tracks permission errors and offers a `sudo` retry path for root-owned files
- Manual page — Installs a proper `man` page for offline reference
- Self-contained — Single-file installer; no external package manager required

To get started, "chmod +x purgecli-[version]-installer.sh && sudo ./purgecli-[version]-installer.sh"

If you want to check for dependencies first, after chmod +x, run "sudo ./purgecli-[version]-installer.sh -d"

Before first time use, it's recommended that you run "purgecli -h" or "man purgecli" for extended information.
