#!/bin/bash
SCRIPT_NAME="purgecli"
VERSION="2.5.1"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
CONFIG_FILE="$HOME/.config/purgecli/trash_path"
MANPAGE_PATH="/usr/local/share/man/man1/purgecli.1.gz"
LOG_DIR="$HOME/.local/share/purgecli"
LOG_FILE="$LOG_DIR/purgecli.log"
RESCUE_DIR="$HOME/.local/purgecli/rescue"
FORCE_LOG=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check Braille Unicode support
check_braille_support() {
    if locale charmap 2>/dev/null | grep -qi "UTF-8"; then
        if echo "⠋" 2>/dev/null | grep -q "⠋"; then
            echo "braille"
            return
        fi
    fi
    echo "classic"
}

# Simple spinner without background process
show_simple_spinner() {
    local message=$1
    local duration=${2:-2}
    local spinner_type=$(check_braille_support)
    
    if [ "$spinner_type" == "braille" ]; then
        local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    else
        local frames=("-" "\\" "|" "/")
    fi
    
    local iterations=$((duration * 10))
    for ((i=0; i<iterations; i++)); do
        local frame_index=$((i % ${#frames[@]}))
        printf "\r${YELLOW}[${frames[$frame_index]}]${NC} ${message}"
        sleep 0.1
    done
    printf "\r%-100s\r" ""
}

# Function to check a dependency
check_dependency() {
    local cmd=$1
    local package=$2
    
    show_simple_spinner "Checking $package..." 1
    
    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}[✓]${NC} $package"
        return 0
    else
        echo -e "${RED}[✗]${NC} $package (missing)"
        return 1
    fi
}

# Function to list items with numbers (including hidden files)
list_items_numbered() {
    local base_dir=$1
    local -n items_array=$2
    
    items_array=()
    local index=0
    
    # Use find with -print0 to handle all files including hidden ones
    while IFS= read -r -d '' item; do
        items_array+=("$item")
        local basename_item=$(basename "$item")
        local size=$(du -sh "$item" 2>/dev/null | cut -f1)
        printf "${BLUE}[%d]${NC} %-50s %s\n" "$index" "$basename_item" "$size"
        index=$((index + 1))
    done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z)
}

# Function to manage rescue directory
manage_rescue() {
    if [ ! -d "$RESCUE_DIR" ]; then
        echo "No rescue directory found."
        echo "Items are moved to rescue when you use the (R)escue option during purge."
        exit 0
    fi
    
    if [ -z "$(ls -A "$RESCUE_DIR" 2>/dev/null)" ]; then
        echo "Rescue directory is empty."
        exit 0
    fi
    
    echo "=== Rescue Directory Management ==="
    echo ""
    echo "Rescue location: $RESCUE_DIR"
    echo ""
    
    while true; do
        echo "Contents of rescue directory:"
        du -h "$RESCUE_DIR"
        echo ""
        
        declare -a rescue_items
        list_items_numbered "$RESCUE_DIR" rescue_items
        
        if [ ${#rescue_items[@]} -eq 0 ]; then
            echo ""
            echo "Rescue directory is now empty."
            break
        fi
        
        echo ""
        echo "Options:"
        echo "  (A)ll    - Move all items to a single location"
        echo "  (S)elect - Select specific items by number"
        echo "  (D)elete - Delete all rescued items"
        echo "  (Q)uit   - Exit rescue management"
        echo ""
        read -r -p "Choose an option: " rescue_choice
        
        case "$rescue_choice" in
            [Aa]|[Aa]ll)
                echo ""
                read -r -p "Enter destination path (use ~ for home): " dest_path
                dest_path="${dest_path/#\~/$HOME}"
                
                if [ -z "$dest_path" ]; then
                    echo "No destination specified. Cancelled."
                    continue
                fi
                
                mkdir -p "$dest_path" 2>/dev/null
                
                if [ ! -d "$dest_path" ]; then
                    echo -e "${RED}[✗]${NC} Cannot create or access destination: $dest_path"
                    continue
                fi
                
                echo "Moving all items to $dest_path..."
                local moved=0
                local failed=0
                
                for item in "${rescue_items[@]}"; do
                    if mv "$item" "$dest_path/" 2>/dev/null; then
                        moved=$((moved + 1))
                        echo -e "${GREEN}[✓]${NC} Moved $(basename "$item")"
                    else
                        failed=$((failed + 1))
                        echo -e "${RED}[✗]${NC} Failed to move $(basename "$item")"
                    fi
                done
                
                echo ""
                echo "Moved $moved items, $failed failed."
                ;;
                
            [Ss]|[Ss]elect)
                echo ""
                echo "Enter item numbers (space-separated, e.g., 0 2 5):"
                read -r selections
                
                if [ -z "$selections" ]; then
                    echo "No selections made."
                    continue
                fi
                
                echo ""
                read -r -p "Enter destination path (use ~ for home): " dest_path
                dest_path="${dest_path/#\~/$HOME}"
                
                if [ -z "$dest_path" ]; then
                    echo "No destination specified. Cancelled."
                    continue
                fi
                
                mkdir -p "$dest_path" 2>/dev/null
                
                if [ ! -d "$dest_path" ]; then
                    echo -e "${RED}[✗]${NC} Cannot create or access destination: $dest_path"
                    continue
                fi
                
                echo "Moving selected items to $dest_path..."
                local moved=0
                local failed=0
                
                for num in $selections; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -lt ${#rescue_items[@]} ]; then
                        local item="${rescue_items[$num]}"
                        if mv "$item" "$dest_path/" 2>/dev/null; then
                            moved=$((moved + 1))
                            echo -e "${GREEN}[✓]${NC} Moved $(basename "$item")"
                        else
                            failed=$((failed + 1))
                            echo -e "${RED}[✗]${NC} Failed to move $(basename "$item")"
                        fi
                    else
                        echo -e "${YELLOW}[!]${NC} Invalid selection: $num"
                    fi
                done
                
                echo ""
                echo "Moved $moved items, $failed failed."
                ;;
                
            [Dd]|[Dd]elete)
                echo ""
                echo -e "${YELLOW}WARNING:${NC} This will permanently delete all rescued items!"
                read -r -p "Are you sure? (yes/no): " confirm
                
                if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    # Use find to delete all files including hidden ones
                    find "$RESCUE_DIR" -mindepth 1 -depth -delete 2>/dev/null
                    echo -e "${GREEN}[✓]${NC} All rescued items deleted."
                    break
                else
                    echo "Deletion cancelled."
                fi
                ;;
                
            [Qq]|[Qq]uit)
                echo "Exiting rescue management."
                break
                ;;
                
            *)
                echo "Invalid option. Please choose A, S, D, or Q."
                continue
                ;;
        esac
    done
}

# Function to rescue items from trash
rescue_from_trash() {
    local trash_path=$1
    
    echo ""
    echo "=== Rescue Items from Trash ==="
    echo ""
    
    if [ -z "$(ls -A "$trash_path" 2>/dev/null)" ]; then
        echo "Trash is empty. Nothing to rescue."
        return
    fi
    
    echo "Items in trash (including hidden files):"
    echo ""
    
    declare -a trash_items
    list_items_numbered "$trash_path" trash_items
    
    if [ ${#trash_items[@]} -eq 0 ]; then
        echo "No items found in trash."
        return
    fi
    
    echo ""
    echo "Enter item numbers to rescue (space-separated, e.g., 0 2 5)"
    echo "Or press Enter to skip rescue:"
    read -r selections
    
    if [ -z "$selections" ]; then
        echo "No items selected for rescue."
        return
    fi
    
    mkdir -p "$RESCUE_DIR"
    
    echo ""
    echo "Rescuing selected items..."
    local rescued=0
    local failed=0
    
    for num in $selections; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -lt ${#trash_items[@]} ]; then
            local item="${trash_items[$num]}"
            local basename_item=$(basename "$item")
            
            if mv "$item" "$RESCUE_DIR/" 2>/dev/null; then
                rescued=$((rescued + 1))
                echo -e "${GREEN}[✓]${NC} Rescued: $basename_item"
            else
                failed=$((failed + 1))
                echo -e "${RED}[✗]${NC} Failed to rescue: $basename_item"
            fi
        else
            echo -e "${YELLOW}[!]${NC} Invalid selection: $num"
        fi
    done
    
    echo ""
    echo "Rescued $rescued items, $failed failed."
    echo "Rescued items saved to: $RESCUE_DIR"
}

# Check if script is being run for the first time (not installed)
if [ "$0" != "$INSTALL_PATH" ]; then
    echo "=== PurgeCLI v$VERSION Installer ==="
    echo ""
    echo "This installer will:"
    echo "  1. Check system dependencies"
    echo "  2. Configure your trash directory"
    echo "  3. Install PurgeCLI to $INSTALL_PATH"
    echo "  4. Install the manual page"
    echo ""
    
    # Check dependencies
    echo "Checking dependencies..."
    echo ""
    
    all_deps_met=true
    
    check_dependency "find" "find" || all_deps_met=false
    check_dependency "rm" "rm (coreutils)" || all_deps_met=false
    check_dependency "du" "du (coreutils)" || all_deps_met=false
    check_dependency "bc" "bc (calculator)" || all_deps_met=false
    check_dependency "date" "date (coreutils)" || all_deps_met=false
    
    echo ""
    
    if [ "$all_deps_met" = false ]; then
        echo -e "${RED}[✗]${NC} Missing required dependencies."
        echo "Please install the missing packages and run this installer again."
        exit 1
    fi
    
    echo -e "${GREEN}[✓]${NC} All dependencies met!"
    echo ""
    
    # Configure trash directory
    echo "Configuring trash directory..."
    echo ""
    
    # Detect the actual user (not root if running with sudo)
    if [ -n "$SUDO_USER" ]; then
        ACTUAL_USER="$SUDO_USER"
        ACTUAL_HOME=$(eval echo ~$SUDO_USER)
    else
        ACTUAL_USER="$USER"
        ACTUAL_HOME="$HOME"
    fi
    
    # Default trash directory for the actual user
    DEFAULT_TRASH="$ACTUAL_HOME/.local/share/Trash"
    
    echo "Detected user: $ACTUAL_USER"
    echo "Home directory: $ACTUAL_HOME"
    echo ""
    echo "Default trash directory: $DEFAULT_TRASH"
    echo ""
    echo "Options:"
    echo "  (D)efault - Use $DEFAULT_TRASH"
    echo "  (C)ustom  - Specify a custom trash directory path"
    echo ""
    read -r -p "Choose an option: " trash_choice
    
    case "$trash_choice" in
        [Dd]|[Dd]efault)
            TRASH_DIR="$DEFAULT_TRASH"
            
            # Create the directory if it doesn't exist
            if [ ! -d "$TRASH_DIR" ]; then
                echo ""
                echo "Creating trash directory: $TRASH_DIR"
                if [ -n "$SUDO_USER" ]; then
                    sudo -u "$SUDO_USER" mkdir -p "$TRASH_DIR" 2>/dev/null
                else
                    mkdir -p "$TRASH_DIR" 2>/dev/null
                fi
                
                if [ -d "$TRASH_DIR" ]; then
                    echo -e "${GREEN}[✓]${NC} Trash directory created"
                else
                    echo -e "${RED}[✗]${NC} Failed to create trash directory"
                    exit 1
                fi
            fi
            ;;
            
        [Cc]|[Cc]ustom)
            echo ""
            read -r -p "Enter custom trash directory path: " custom_trash
            custom_trash="${custom_trash/#\~/$ACTUAL_HOME}"
            
            if [ -z "$custom_trash" ]; then
                echo "No trash directory specified. Installation cancelled."
                exit 1
            fi
            
            if [ ! -d "$custom_trash" ]; then
                echo "Directory does not exist: $custom_trash"
                echo ""
                read -r -p "Create this directory? (yes/no): " create_dir
                
                if [[ "$create_dir" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    if [ -n "$SUDO_USER" ]; then
                        sudo -u "$SUDO_USER" mkdir -p "$custom_trash" 2>/dev/null
                    else
                        mkdir -p "$custom_trash" 2>/dev/null
                    fi
                    
                    if [ ! -d "$custom_trash" ]; then
                        echo "Failed to create directory. Installation cancelled."
                        exit 1
                    fi
                else
                    echo "Installation cancelled."
                    exit 1
                fi
            fi
            
            TRASH_DIR="$custom_trash"
            ;;
            
        *)
            echo "Invalid option. Installation cancelled."
            exit 1
            ;;
    esac
    
    # Save configuration to the actual user's home directory
    USER_CONFIG_FILE="$ACTUAL_HOME/.config/purgecli/trash_path"
    
    if [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" mkdir -p "$(dirname "$USER_CONFIG_FILE")" 2>/dev/null
        echo "$TRASH_DIR" | sudo -u "$SUDO_USER" tee "$USER_CONFIG_FILE" > /dev/null
    else
        mkdir -p "$(dirname "$USER_CONFIG_FILE")"
        echo "$TRASH_DIR" > "$USER_CONFIG_FILE"
    fi
    
    echo ""
    echo -e "${GREEN}[✓]${NC} Trash directory configured: $TRASH_DIR"
    echo ""
    
    # Create manual page
    echo "Creating manual page..."
    
    MANPAGE_CONTENT='.TH PURGECLI 1 "2024" "PurgeCLI 2.5.1" "User Commands"
.SH NAME
purgecli \- permanently delete all files from your trash directory
.SH SYNOPSIS
.B purgecli
[\fIOPTION\fR]
.SH DESCRIPTION
.B purgecli
is a command-line utility that permanently deletes all files and directories from your configured trash directory, including hidden files and directories. The deletion is irreversible and includes visual progress tracking.
.PP
Files deleted with purgecli cannot be recovered. Use with caution.
.SH OPTIONS
.TP
.B \-\-help, \-h
Display help information and exit
.TP
.B \-\-version, \-v
Display version information and exit
.TP
.B \-\-reset, \-r
Reconfigure the trash directory path
.TP
.B \-\-rescue
Manage previously rescued items
.TP
.B \-\-force\-log
Enable detailed logging of deletion errors
.TP
.B \-\-remove
Uninstall purgecli from the system
.SH FEATURES
.TP
.B Security
Ensures complete deletion of all trash contents including hidden files and directories (files and directories starting with .)
.TP
.B Visual Progress
Real-time progress bar with estimated time remaining and percentage completion
.TP
.B Rescue System
Option to rescue specific items before purging, with ability to manage rescued items later
.TP
.B Unicode Support
Automatically detects and uses Braille Unicode characters for enhanced visual feedback when supported
.TP
.B Error Handling
Tracks and reports deletion errors with optional detailed logging and sudo retry capability
.SH USAGE
When run without options, purgecli will:
.IP 1. 4
Display the contents and size of your trash directory
.IP 2. 4
Prompt you to choose between:
.RS 8
.IP \(bu 2
(P)urge - Permanently delete all trash
.IP \(bu 2
(R)escue - Save specific items before purging
.IP \(bu 2
(Q)uit - Exit without purging
.RE
.IP 3. 4
If purging, request confirmation before proceeding
.IP 4. 4
Show real-time progress with time estimation
.IP 5. 4
Report completion status and statistics
.IP 6. 4
Offer sudo retry if permission errors occur
.SH RESCUE SYSTEM
The rescue system allows you to save specific items before purging:
.IP 1. 4
Select (R)escue option before purging
.IP 2. 4
Choose items by number to save to the rescue directory
.IP 3. 4
Access rescued items later with \fBpurgecli \-\-rescue\fR
.IP 4. 4
Move rescued items to any location or delete them permanently
.SH CONFIGURATION
The trash directory path is stored in:
.IP
.B ~/.config/purgecli/trash_path
.PP
To change the trash directory, run:
.IP
.B purgecli \-\-reset
.SH FILES
.TP
.B ~/.config/purgecli/trash_path
Configuration file containing the trash directory path
.TP
.B ~/.local/share/purgecli/purgecli.log
Log file for purge operations and errors (when force-log is enabled)
.TP
.B ~/.local/purgecli/rescue
Directory where rescued items are stored
.SH EXAMPLES
.TP
.B purgecli
Run purgecli interactively with rescue option
.TP
.B purgecli \-\-reset
Reconfigure the trash directory
.TP
.B purgecli \-\-rescue
Manage rescued items
.TP
.B purgecli \-\-force\-log
Run with detailed error logging enabled
.TP
.B purgecli \-\-remove
Uninstall purgecli from the system
.SH SECURITY CONSIDERATIONS
.B purgecli v2.5.1
ensures that ALL files and directories in trash are permanently deleted, including:
.IP \(bu 2
Hidden files (files starting with .)
.IP \(bu 2
Hidden directories (directories starting with .)
.IP \(bu 2
Files within hidden directories
.IP \(bu 2
Nested directory structures
.PP
This is critical for security as hidden files may contain sensitive information such as:
.IP \(bu 2
Configuration files with credentials
.IP \(bu 2
SSH keys and certificates
.IP \(bu 2
Browser data and cookies
.IP \(bu 2
Application caches with personal data
.PP
The rescue system provides a safety mechanism to recover items before permanent deletion.
.PP
If files are owned by root or have special permissions, purgecli will offer to retry with sudo.
.SH EXIT STATUS
.TP
.B 0
Successful completion
.TP
.B 1
Error occurred (missing dependencies, configuration error, or user cancellation)
.SH AUTHOR
Written for secure and complete trash management.
.SH REPORTING BUGS
Report bugs to your system administrator or the tool maintainer.
.SH SEE ALSO
.BR rm (1),
.BR find (1),
.BR trash-cli (1)
'
    
    mkdir -p "$(dirname "$MANPAGE_PATH")"
    echo "$MANPAGE_CONTENT" | gzip > "$MANPAGE_PATH"
    
    if [ -f "$MANPAGE_PATH" ]; then
        echo -e "${GREEN}[✓]${NC} Manual page installed"
    else
        echo -e "${YELLOW}[!]${NC} Failed to install manual page (non-critical)"
    fi
    
    echo ""
    
    # Install script
    echo "Installing PurgeCLI..."
    echo ""
    
    read -r -p "Install to $INSTALL_PATH? (yes/no): " confirm_install
    
    if [[ "$confirm_install" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        if sudo cp "$0" "$INSTALL_PATH" 2>/dev/null; then
            echo -e "${GREEN}[✓]${NC} Script copied to $INSTALL_PATH"
        else
            echo -e "${RED}[✗]${NC} Failed to copy script. Do you have sudo privileges?"
            exit 1
        fi
        
        if sudo chmod +x "$INSTALL_PATH" 2>/dev/null; then
            echo -e "${GREEN}[✓]${NC} Permissions set"
            echo ""
            echo -e "${GREEN}[✓]${NC} Installation successful!"
            echo ""
            echo "You can now run this script from anywhere using: $SCRIPT_NAME"
            echo "To reconfigure, run: $SCRIPT_NAME --reset"
            echo "For help, run: $SCRIPT_NAME --help or man $SCRIPT_NAME"
        else
            echo -e "${RED}[✗]${NC} Failed to set proper permissions."
            echo "Installation failed. Exiting."
            exit 1
        fi
    else
        echo ""
        echo "Installation declined."
        echo "Run this script again to complete installation."
        exit 1
    fi
    
    exit 0
fi

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "PurgeCLI v$VERSION - Secure Trash Purge Utility"
        echo ""
        echo "Usage: $SCRIPT_NAME [OPTION]"
        echo ""
        echo "Options:"
        echo "  --help, -h       Show this help message"
        echo "  --version, -v    Show version information"
        echo "  --reset, -r      Reconfigure trash directory"
        echo "  --rescue         Manage rescued items"
        echo "  --force-log      Enable detailed error logging"
        echo "  --remove         Uninstall purgecli from system"
        echo ""
        echo "When run without options, purgecli will interactively purge your trash"
        echo "with the option to rescue specific items before deletion."
        echo ""
        echo "Security Note: v2.5.1 ensures ALL files including hidden files and"
        echo "directories are completely deleted from trash."
        echo ""
        echo "For more information, see: man $SCRIPT_NAME"
        exit 0
        ;;
        
    --version|-v)
        echo "PurgeCLI version $VERSION"
        echo "Secure trash purge utility with hidden file deletion"
        exit 0
        ;;
        
    --reset|-r)
        echo "=== Reconfigure Trash Directory ==="
        echo ""
        
        # Detect the actual user (not root if running with sudo)
        if [ -n "$SUDO_USER" ]; then
            ACTUAL_USER="$SUDO_USER"
            ACTUAL_HOME=$(eval echo ~$SUDO_USER)
        else
            ACTUAL_USER="$USER"
            ACTUAL_HOME="$HOME"
        fi
        
        # Show current configuration
        if [ -f "$CONFIG_FILE" ]; then
            current_trash=$(cat "$CONFIG_FILE")
            echo "Current trash directory: $current_trash"
            echo ""
        fi
        
        # Default trash directory for the actual user
        DEFAULT_TRASH="$ACTUAL_HOME/.local/share/Trash"
        
        echo "Detected user: $ACTUAL_USER"
        echo "Home directory: $ACTUAL_HOME"
        echo ""
        echo "Default trash directory: $DEFAULT_TRASH"
        echo ""
        echo "Options:"
        echo "  (D)efault - Use $DEFAULT_TRASH"
        echo "  (C)ustom  - Specify a custom trash directory path"
        echo ""
        read -r -p "Choose an option: " trash_choice
        
        case "$trash_choice" in
            [Dd]|[Dd]efault)
                new_trash="$DEFAULT_TRASH"
                
                # Create the directory if it doesn't exist
                if [ ! -d "$new_trash" ]; then
                    echo ""
                    echo "Creating trash directory: $new_trash"
                    if [ -n "$SUDO_USER" ]; then
                        sudo -u "$SUDO_USER" mkdir -p "$new_trash" 2>/dev/null
                    else
                        mkdir -p "$new_trash" 2>/dev/null
                    fi
                    
                    if [ -d "$new_trash" ]; then
                        echo -e "${GREEN}[✓]${NC} Trash directory created"
                    else
                        echo -e "${RED}[✗]${NC} Failed to create trash directory"
                        exit 1
                    fi
                fi
                ;;
                
            [Cc]|[Cc]ustom)
                echo ""
                read -r -p "Enter custom trash directory path: " new_trash
                new_trash="${new_trash/#\~/$ACTUAL_HOME}"
                
                if [ -z "$new_trash" ]; then
                    echo "No directory specified. Configuration unchanged."
                    exit 1
                fi
                
                if [ ! -d "$new_trash" ]; then
                    echo "Directory does not exist: $new_trash"
                    echo ""
                    read -r -p "Create this directory? (yes/no): " create_dir
                    
                    if [[ "$create_dir" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                        if [ -n "$SUDO_USER" ]; then
                            sudo -u "$SUDO_USER" mkdir -p "$new_trash" 2>/dev/null
                        else
                            mkdir -p "$new_trash" 2>/dev/null
                        fi
                        
                        if [ ! -d "$new_trash" ]; then
                            echo "Failed to create directory. Configuration unchanged."
                            exit 1
                        fi
                    else
                        echo "Configuration unchanged."
                        exit 1
                    fi
                fi
                ;;
                
            *)
                echo "Invalid option. Configuration unchanged."
                exit 1
                ;;
        esac
        
        # Save configuration to the actual user's config directory
        USER_CONFIG_FILE="$ACTUAL_HOME/.config/purgecli/trash_path"
        
        if [ -n "$SUDO_USER" ]; then
            sudo -u "$SUDO_USER" mkdir -p "$(dirname "$USER_CONFIG_FILE")" 2>/dev/null
            echo "$new_trash" | sudo -u "$SUDO_USER" tee "$USER_CONFIG_FILE" > /dev/null
        else
            mkdir -p "$(dirname "$USER_CONFIG_FILE")"
            echo "$new_trash" > "$USER_CONFIG_FILE"
        fi
        
        echo ""
        echo -e "${GREEN}[✓]${NC} Trash directory updated: $new_trash"
        exit 0
        ;;
        
    --rescue)
        manage_rescue
        exit 0
        ;;
        
    --remove)
        echo "=== Uninstall PurgeCLI ==="
        echo ""
        echo "This will remove:"
        echo "  - Script from $INSTALL_PATH"
        echo "  - Manual page from $MANPAGE_PATH"
        echo ""
        echo "This will NOT remove:"
        echo "  - Configuration file (~/.config/purgecli/trash_path)"
        echo "  - Log files (~/.local/share/purgecli/)"
        echo "  - Rescued items (~/.local/purgecli/rescue/)"
        echo ""
        read -r -p "Are you sure you want to uninstall? (yes/no): " confirm_remove
        
        if [[ ! "$confirm_remove" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            echo "Uninstall cancelled."
            exit 0
        fi
        
        echo ""
        echo "Uninstalling PurgeCLI..."
        
        removed_count=0
        failed_count=0
        
        # Remove the script
        if [ -f "$INSTALL_PATH" ]; then
            if sudo rm -f "$INSTALL_PATH" 2>/dev/null; then
                echo -e "${GREEN}[✓]${NC} Removed script from $INSTALL_PATH"
                removed_count=$((removed_count + 1))
            else
                echo -e "${RED}[✗]${NC} Failed to remove script (need sudo?)"
                failed_count=$((failed_count + 1))
            fi
        else
            echo -e "${YELLOW}[!]${NC} Script not found at $INSTALL_PATH"
        fi
        
        # Remove the manual page
        if [ -f "$MANPAGE_PATH" ]; then
            if sudo rm -f "$MANPAGE_PATH" 2>/dev/null; then
                echo -e "${GREEN}[✓]${NC} Removed manual page from $MANPAGE_PATH"
                removed_count=$((removed_count + 1))
            else
                echo -e "${RED}[✗]${NC} Failed to remove manual page"
                failed_count=$((failed_count + 1))
            fi
        else
            echo -e "${YELLOW}[!]${NC} Manual page not found at $MANPAGE_PATH"
        fi
        
        echo ""
        
        if [ $removed_count -gt 0 ]; then
            echo -e "${GREEN}[✓]${NC} Uninstall complete - removed $removed_count item(s)"
            
            if [ $failed_count -eq 0 ]; then
                echo ""
                echo "To remove configuration and data files, manually delete:"
                echo "  ~/.config/purgecli/"
                echo "  ~/.local/share/purgecli/"
                echo "  ~/.local/purgecli/"
            fi
        else
            echo -e "${YELLOW}[!]${NC} PurgeCLI does not appear to be installed"
        fi
        
        if [ $failed_count -gt 0 ]; then
            echo ""
            echo -e "${RED}[✗]${NC} $failed_count item(s) failed to remove"
        fi
        
        exit 0
        ;;
        
    --force-log)
        FORCE_LOG=true
        echo "Force logging enabled"
        echo ""
        ;;
        
    --*)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Normal operation (script is already installed)
if [ -f "$CONFIG_FILE" ]; then
    TRASH_DIR=$(cat "$CONFIG_FILE")
else
    TRASH_DIR="$HOME/.local/share/Trash"
fi

if [ ! -d "$TRASH_DIR" ]; then
    echo "Trash directory not found at $TRASH_DIR"
    echo "Your trash configuration is missing or the directory was deleted."
    echo ""
    echo "To reconfigure your trash directory, run: $SCRIPT_NAME --reset"
    exit 1
fi

# Main purge loop with rescue option
while true; do
    echo ""
    echo "Contents of your trash bin:"
    du -h "$TRASH_DIR"
    echo ""
    echo -e "${YELLOW}All files including hidden files and directories will be purged.${NC}"
    echo ""
    echo "Options:"
    echo "  (P)urge  - Permanently delete all trash"
    echo "  (R)escue - Save specific items before purging"
    echo "  (Q)uit   - Exit without purging"
    echo ""
    read -r -p "Choose an option: " main_choice
    
    case "$main_choice" in
        [Pp]|[Pp]urge)
            echo ""
            echo "PURGED FILES WILL BE UNRECOVERABLE."
            read -r -p "Are you sure you want to purge? (yes/no): " confirm
            
            if [[ ! "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                echo "Purge cancelled."
                continue
            fi
            
            echo ""
            echo "Counting items in trash (including hidden files)..."
            
            mkdir -p "$LOG_DIR"
            
            # Build array of all items to delete - this avoids subshell issues
            declare -a items_to_delete
            while IFS= read -r -d '' item; do
                items_to_delete+=("$item")
            done < <(find "$TRASH_DIR" -mindepth 1 -depth -print0 2>/dev/null)
            
            total_items=${#items_to_delete[@]}
            
            if [ "$total_items" -eq 0 ]; then
                echo "Trash is already empty!"
                break
            fi
            
            echo "Found $total_items items to delete (including all hidden files and directories)"
            echo ""
            echo "Purging trash..."
            echo ""
            printf "%-10s  %-10s\n" "Est. Time" "Progress"
            
            spinner_type=$(check_braille_support)
            if [ "$spinner_type" == "braille" ]; then
                progress_frames=("⠀" "⠁" "⠃" "⠇" "⠏" "⠟" "⠿" "⡿" "⣿")
                bar_length=18
            else
                progress_frames=(" " "." ":" "=" "#")
                bar_length=18
            fi
            
            start_time=$(date +%s)
            current_item=0
            error_count=0
            
            # Delete items one by one - now we're NOT in a subshell
            for item in "${items_to_delete[@]}"; do
                current_item=$((current_item + 1))
                
                current_time=$(date +%s)
                elapsed=$((current_time - start_time))
                
                if [ $current_item -gt 0 ] && [ $elapsed -gt 0 ]; then
                    avg_time_per_item=$(echo "scale=2; $elapsed / $current_item" | bc 2>/dev/null || echo "0")
                    remaining_items=$((total_items - current_item))
                    if [ "$avg_time_per_item" != "0" ]; then
                        eta=$(echo "scale=0; $avg_time_per_item * $remaining_items / 1" | bc 2>/dev/null || echo "0")
                        eta=${eta%.*}
                    else
                        eta=0
                    fi
                else
                    eta=0
                fi
                
                eta_minutes=$((eta / 60))
                eta_seconds=$((eta % 60))
                eta_str=$(printf "%02d:%02d" $eta_minutes $eta_seconds)
                
                percentage=$((current_item * 100 / total_items))
                percentage_str=$(printf "%d%%" $percentage)
                
                filled_blocks=$((current_item * bar_length / total_items))
                progress_bar=""
                
                if [ "$spinner_type" == "braille" ]; then
                    for ((i=0; i<bar_length; i++)); do
                        if [ $i -lt $filled_blocks ]; then
                            progress_bar+="${progress_frames[8]}"
                        elif [ $i -eq $filled_blocks ]; then
                            partial_progress=$((current_item * bar_length * 100 / total_items % 100))
                            frame_idx=$((partial_progress * 8 / 100))
                            if [ $frame_idx -ge ${#progress_frames[@]} ]; then
                                frame_idx=$((${#progress_frames[@]} - 1))
                            fi
                            progress_bar+="${progress_frames[$frame_idx]}"
                        else
                            progress_bar+="${progress_frames[0]}"
                        fi
                    done
                else
                    for ((i=0; i<bar_length; i++)); do
                        if [ $i -lt $filled_blocks ]; then
                            progress_bar+="${progress_frames[4]}"
                        else
                            progress_bar+="${progress_frames[0]}"
                        fi
                    done
                fi
                
                printf "\r  %-5s        ${GREEN}%s${NC}\n[${YELLOW}%s${NC}]" \
                    "$eta_str" \
                    "$percentage_str" \
                    "$progress_bar"
                
                printf "\033[1A"
                
                # Try to delete the item and capture errors
                if ! rm -rf "$item" 2>/dev/null; then
                    if [ "$FORCE_LOG" = true ]; then
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to delete: $item" >> "$LOG_FILE" 2>/dev/null
                    fi
                    error_count=$((error_count + 1))
                fi
            done
            
            printf "\r%-100s\r" ""
            printf "\n%-100s\n" ""
            printf "\033[2A"
            
            end_time=$(date +%s)
            total_time=$((end_time - start_time))
            
            if [ "$spinner_type" == "braille" ]; then
                full_bar=""
                for ((i=0; i<bar_length; i++)); do
                    full_bar+="${progress_frames[8]}"
                done
            else
                full_bar=""
                for ((i=0; i<bar_length; i++)); do
                    full_bar+="${progress_frames[4]}"
                done
            fi
            
            printf "\r%-100s\r" ""
            printf "  %-5s      ${GREEN}100%%${NC}\n" "00:00"
            printf "%-100s\r" ""
            printf "${GREEN}[%s]${NC}\n" "$full_bar"
            
            if [ $error_count -gt 0 ]; then
                echo ""
                echo -e "${YELLOW}[!]${NC} Trash purge completed with $error_count errors"
                echo "    $((total_items - error_count)) items deleted successfully in $total_time seconds"
                echo ""
                echo -e "${YELLOW}Permission denied errors detected.${NC}"
                echo "Some files may be owned by root or another user."
                echo ""
                read -r -p "Would you like to try again with sudo? (yes/no): " use_sudo
                
                if [[ "$use_sudo" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    echo ""
                    echo "Attempting to delete remaining items with sudo..."
                    
                    # Count remaining items
                    declare -a remaining_items
                    while IFS= read -r -d '' item; do
                        remaining_items+=("$item")
                    done < <(find "$TRASH_DIR" -mindepth 1 -depth -print0 2>/dev/null)
                    
                    if [ ${#remaining_items[@]} -gt 0 ]; then
                        # Use sudo with find -delete for maximum compatibility
                        sudo find "$TRASH_DIR" -mindepth 1 -depth -delete 2>/dev/null
                        
                        # Check if successful
                        declare -a check_items
                        while IFS= read -r -d '' item; do
                            check_items+=("$item")
                        done < <(find "$TRASH_DIR" -mindepth 1 -depth -print0 2>/dev/null)
                        
                        if [ ${#check_items[@]} -eq 0 ]; then
                            echo -e "${GREEN}[✓]${NC} All remaining items deleted successfully with sudo"
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Purged all items (required sudo)" >> "$LOG_FILE" 2>/dev/null
                        else
                            echo -e "${RED}[✗]${NC} ${#check_items[@]} items still remain"
                            echo "These items may have special attributes or be in use."
                            echo ""
                            echo "Remaining items:"
                            find "$TRASH_DIR" -mindepth 1 -maxdepth 1 -ls 2>/dev/null | head -10
                        fi
                    else
                        echo -e "${GREEN}[✓]${NC} All items have been deleted"
                    fi
                else
                    if [ "$FORCE_LOG" = true ]; then
                        echo "Check $LOG_FILE for error details"
                    else
                        echo "Use '$SCRIPT_NAME --force-log' to log error details"
                    fi
                fi
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Purged $total_items items in $total_time seconds" >> "$LOG_FILE" 2>/dev/null
                echo -e "${GREEN}[✓]${NC} Trash purged successfully - $total_items items deleted in $total_time seconds"
            fi
            
            if [ -d "$RESCUE_DIR" ] && [ -n "$(ls -A "$RESCUE_DIR" 2>/dev/null)" ]; then
                echo ""
                read -r -p "You have rescued items. Would you like to manage them now? (yes/no): " manage_now
                
                if [[ "$manage_now" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    manage_rescue
                else
                    echo "You can manage rescued items later with: $SCRIPT_NAME --rescue"
                fi
            fi
            
            break
            ;;
            
        [Rr]|[Rr]escue)
            rescue_from_trash "$TRASH_DIR"
            continue
            ;;
            
        [Qq]|[Qq]uit)
            echo "Exiting without purging trash."
            exit 0
            ;;
            
        *)
            echo "Invalid option. Please choose P, R, or Q."
            continue
            ;;
    esac
done
