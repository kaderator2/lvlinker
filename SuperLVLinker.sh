#!/bin/bash

# SuperLVLinker - Combined Vortex installer and game linker for Linux
# Version 3.0.0

# Configuration
VORTEX_INSTALLER_URL="https://github.com/Nexus-Mods/Vortex/releases/download/v1.13.7/vortex-setup-1.13.7.exe"
WINE_PREFIX="$HOME/.vortex_wine"
STEAM_DIR="$HOME/.local/share/Steam"
DEFAULT_STEAM_DIRS=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
)
BACKUP_DIR="$HOME/vortex_backups"
LOG_FILE="/tmp/supervortex.log"
CONFIG_FILE="$HOME/.config/supervortex.conf"
VORTEX_DESKTOP_FILE="$HOME/.local/share/applications/vortex.desktop"

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to display usage
usage() {
    echo "SuperLVLinker - All-in-one Vortex setup and game linking for Linux"
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help         Show this help message and exit"
    echo "  -i, --install      Force reinstallation of Vortex"
    echo "  -a, --add-games    Add/link more games to Vortex"
    echo "  -d, --dry-run      Show what would be done without making changes"
    echo "  -b, --backup       Create backup before making changes"
    echo "  -v, --verbose      Show detailed output"
    echo "  -p, --path PATH    Add custom Steam library path"
    echo "  -w, --wine PATH    Set custom Wine prefix path (default: $WINE_PREFIX)"
    echo
    echo "Example:"
    echo "  $0 -a -p /mnt/SlowGames/SteamLibrary"
    echo
    echo "With no options, the script will:"
    echo "  - Install Vortex if not already installed"
    echo "  - Link games if this is the first run"
    echo "  - Otherwise, just launch Vortex"
    exit 1
}

# Function to check for required libraries
check_required_libs() {
    echo "Checking for required libraries..."
    
    # Required libraries for 64-bit Wine
    required_64bit_libs=(
        "glibc"
        "gcc-libs"
    )
    
    # Required 32-bit libraries for compatibility
    required_32bit_libs=(
        "lib32-glibc"
        "lib32-gcc-libs"
    )
    
    # Check 64-bit libraries
    missing_64bit=()
    for lib in "${required_64bit_libs[@]}"; do
        if ! pacman -Q "$lib" >/dev/null 2>&1; then
            missing_64bit+=("$lib")
        fi
    done
    
    # Check 32-bit libraries
    missing_32bit=()
    for lib in "${required_32bit_libs[@]}"; do
        if ! pacman -Q "$lib" >/dev/null 2>&1; then
            missing_32bit+=("$lib")
        fi
    done
    
    # Report missing libraries
    if [ ${#missing_64bit[@]} -gt 0 ]; then
        echo "Missing required 64-bit libraries:"
        for lib in "${missing_64bit[@]}"; do
            echo "  - $lib"
        done
    fi
    
    if [ ${#missing_32bit[@]} -gt 0 ]; then
        echo "Missing required 32-bit compatibility libraries:"
        for lib in "${missing_32bit[@]}"; do
            echo "  - $lib"
        done
        echo "Note: Even in 64-bit mode, Wine requires 32-bit libraries for compatibility"
    fi
    
    if [ ${#missing_64bit[@]} -gt 0 ] || [ ${#missing_32bit[@]} -gt 0 ]; then
        echo "You can install them with:"
        if command -v pacman &> /dev/null; then
            echo "  sudo pacman -S ${missing_64bit[*]} ${missing_32bit[*]} wine-staging winetricks"
        else
            echo "  sudo dpkg --add-architecture i386 && sudo apt update && \\"
            echo "  sudo apt install ${missing_64bit[*]} ${missing_32bit[*]}"
        fi
        exit 1
    fi
    
    echo "All required libraries are installed."
}

# Function to check dependencies
check_dependencies() {
    echo "Checking dependencies..."
    check_required_libs

    # Check for Wine and validate version
    if ! command -v wine &> /dev/null; then
        echo "Error: Wine is not installed. Please install Wine first."
        echo "You can install it with: sudo pacman -S wine (Arch) or sudo apt install wine (Debian/Ubuntu)"
        exit 1
    fi
    
    # Verify Wine version
    wine_version=$(wine --version 2>/dev/null | grep -oP 'wine-\K[0-9.]+')
    if [ -z "$wine_version" ]; then
        echo "Error: Could not determine Wine version"
        exit 1
    fi
    
    # Check if Wine version is >= 7.0 or is a development version (like 10.2)
    if ! printf '%s\n7.0\n' "$wine_version" | sort -V -C && [[ ! "$wine_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Wine version $wine_version is too old or unrecognized. Please upgrade to Wine 7.0 or newer."
        exit 1
    fi
    
    echo "Using Wine version $wine_version"

    # Check for winbind (needed for NTLM authentication)
    if ! command -v ntlm_auth &> /dev/null; then
        echo "Error: winbind is not installed. Required for NTLM authentication."
        echo "You can install it with: sudo pacman -S winbind (Arch) or sudo apt install winbind (Debian/Ubuntu)"
        exit 1
    fi

    # Check for winetricks
    if ! command -v winetricks &> /dev/null; then
        echo "Warning: winetricks is not installed. Some features may not work correctly."
        echo "You can install it with: sudo pacman -S winetricks (Arch) or sudo apt install winetricks (Debian/Ubuntu)"
    fi

    # Check for curl
    if ! command -v curl &> /dev/null; then
        echo "Error: curl is not installed. Please install curl first."
        echo "You can install it with: sudo pacman -S curl (Arch) or sudo apt install curl (Debian/Ubuntu)"
        exit 1
    fi

    # Check for jq (needed for Steam API queries)
    if ! command -v jq &> /dev/null; then
        echo "Warning: jq is not installed. Steam API game name lookup may not work."
        echo "You can install it with: sudo pacman -S jq (Arch) or sudo apt install jq (Debian/Ubuntu)"
    fi

    echo "All critical dependencies are installed."
}

# Function to download Vortex installer
download_vortex() {
    echo "Downloading latest Vortex installer..."
    installer_path="$HOME/Downloads/vortex-setup-1.13.7.exe"
    
    if curl -L -o "$installer_path" "$VORTEX_INSTALLER_URL"; then
        echo "Downloaded Vortex installer to $installer_path"
    else
        echo "Error: Failed to download Vortex installer"
        exit 1
    fi
}

# Function to setup Wine prefix
setup_wine_prefix() {
    echo "Setting up Wine prefix for Vortex at $WINE_PREFIX..."

    # Check if directory already exists and is a valid Wine prefix
    if [ -d "$WINE_PREFIX" ]; then
        echo "Warning: Wine prefix directory already exists at $WINE_PREFIX"
        
        # Check if it's a valid Wine prefix
        if [ -f "$WINE_PREFIX/system.reg" ]; then
            echo "Existing Wine prefix appears valid"
            read -p "Do you want to overwrite it? (y/n): " confirm
            if [ "$confirm" != "y" ]; then
                echo "Using existing Wine prefix."
                return 0
            fi
        else
            echo "Warning: Directory exists but doesn't appear to be a valid Wine prefix"
            read -p "Do you want to remove it and create a new prefix? (y/n): " confirm
            if [ "$confirm" != "y" ]; then
                echo "Aborting."
                exit 1
            fi
        fi

        # Backup existing directory
        backup_dir="${WINE_PREFIX}.bak.$(date +%Y%m%d%H%M%S)"
        echo "Creating backup of existing directory to $backup_dir"
        mv "$WINE_PREFIX" "$backup_dir"
    fi

    # Create Wine prefix
    echo "Creating new Wine prefix..."
    export WINEPREFIX="$WINE_PREFIX"
    export WINEARCH="win64"
    
    # Initialize the prefix with error handling
    echo "Initializing Wine prefix..."
    if ! wine wineboot --init >/dev/null 2>&1; then
        echo "Error: Failed to initialize Wine prefix"
        echo "This could be due to:"
        echo "1. Missing 32-bit libraries (try: sudo dpkg --add-architecture i386 && sudo apt update)"
        echo "2. Missing Wine dependencies (try: sudo apt install wine32 wine64)"
        echo "3. Corrupted Wine installation"
        exit 1
    fi

    # Enable and configure symlink support in Wine
    echo "Configuring Wine for better symlink support..."
    wine reg add "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\FileSystem" /v "NtfsDisable8dot3NameCreation" /t REG_DWORD /d 0 /f >/dev/null 2>&1
    wine reg add "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\FileSystem" /v "NtfsAllowExtendedCharacterIn8dot3Name" /t REG_DWORD /d 1 /f >/dev/null 2>&1
    wine reg add "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\FileSystem" /v "SymlinkLocalToLocalEvaluation" /t REG_DWORD /d 1 /f >/dev/null 2>&1
    
    # Enable additional symlink settings
    wine reg add "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\FileSystem" /v "SymlinkEvaluation" /t REG_DWORD /d 1 /f >/dev/null 2>&1
    wine reg add "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\FileSystem" /v "LongPathsEnabled" /t REG_DWORD /d 1 /f >/dev/null 2>&1
    
    # Enable developer mode for better symlink handling
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v "Developer" /t REG_SZ /d "1" /f >/dev/null 2>&1
    
    # Set Windows version to Windows 10 for better compatibility
    winecfg -v win10 >/dev/null 2>&1
    
    # Create a custom wineprefix.ini with improved symlink settings
    cat > "$WINE_PREFIX/wineprefix.ini" <<EOF
[Version]
Signature = "\$Windows NT\$"
Class = "Wine"
[System]
SymlinkEvaluation = "LocalToLocal"
CaseSensitive = 0
EnableSymlinks = 1
EOF
    
    # Install required dependencies with winetricks if available
    if command -v winetricks &> /dev/null; then
        echo "Installing required dependencies with winetricks..."
        winetricks -q dotnet48 vcrun2019 win10
    else
        echo "Winetricks not found, skipping dependency installation"
        echo "You may need to manually install .NET Framework and Visual C++ Redistributable"
    fi
    
    # Create directory structure for Steam games
    mkdir -p "$WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common"
    mkdir -p "$WINE_PREFIX/drive_c/users/$USER/AppData/Roaming"
    mkdir -p "$WINE_PREFIX/drive_c/users/$USER/Documents"
    
    echo "Wine prefix setup completed."
}

# Function to install Vortex using Wine
install_vortex() {
    echo "Installing Vortex using Wine..."

    # Set Wine prefix
    export WINEPREFIX="$WINE_PREFIX"
    export WINEARCH="win64"

    # Download installer if needed
    if [ ! -f "$HOME/Downloads/vortex-setup-1.13.7.exe" ]; then
        download_vortex
    fi
    
    installer_path="$HOME/Downloads/vortex-setup-1.13.7.exe"

    # Run Vortex installer with Wine
    echo "Running installer with Wine (this may take a while)..."
    wine "$installer_path"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to run Vortex installer with Wine"
        exit 1
    fi

    echo "Vortex installation completed."
}

# Function to create desktop shortcut
create_desktop_shortcut() {
    echo "Creating desktop shortcut for Vortex..."
    
    # Find Vortex executable in Wine prefix
    vortex_exe=$(find "$WINE_PREFIX" -name "Vortex.exe" -print -quit)
    
    if [ -z "$vortex_exe" ]; then
        echo "Warning: Could not find Vortex.exe in Wine prefix"
        echo "Installation may have failed or used a non-standard location"
        return 1
    fi
    
    # Create desktop file
    cat > "$VORTEX_DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Vortex
Comment=Vortex Mod Manager
Exec=env WINEPREFIX="$WINE_PREFIX" wine "$vortex_exe"
Type=Application
StartupNotify=true
Icon=vortex
Categories=Game;
EOF
    
    # Try to find and set an icon
    icon_path=$(find "$WINE_PREFIX" -name "vortex.ico" -o -name "vortex.png" -print -quit)
    if [ -n "$icon_path" ]; then
        sed -i "s|Icon=vortex|Icon=$icon_path|" "$VORTEX_DESKTOP_FILE"
    fi
    
    chmod +x "$VORTEX_DESKTOP_FILE"
    
    echo "Desktop shortcut created at: $VORTEX_DESKTOP_FILE"
    return 0
}

# Function to verify Wine prefix and Vortex installation
verify_vortex_installation() {
    echo -n "Verifying Vortex installation... "
    
    if [ ! -d "$WINE_PREFIX" ]; then
        echo "Not found"
        return 1
    fi
    
    # Check for Vortex installation
    vortex_exe=$(find "$WINE_PREFIX" -name "Vortex.exe" -print -quit)
    if [ -z "$vortex_exe" ]; then
        echo "Not found"
        return 1
    fi
    
    echo "Found at $vortex_exe"
    return 0
}

# Function to get game name from Steam API
get_game_name() {
    local appid=$1
    local cache_file="/tmp/steam_game_$appid.cache"
    
    # Check cache first
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return 0
    fi
    
    # First try to get name from local manifest file
    for steam_dir in "${valid_steam_dirs[@]}"; do
        local steamapps_dir="$steam_dir/steamapps"
        local manifest_file="$steamapps_dir/appmanifest_$appid.acf"
        
        if [ -f "$manifest_file" ]; then
            local name=$(grep -oP '"name"\s+"\K[^"]+' "$manifest_file")
            if [ -n "$name" ]; then
                echo "$name" > "$cache_file"
                echo "$name"
                return 0
            fi
        fi
    done
    
    # If local manifest not found, query Steam API
    local url="https://store.steampowered.com/api/appdetails?appids=$appid"
    local response=$(curl -s "$url" | tr -d '\0')
    
    # Check if response is valid JSON
    if ! echo "$response" | jq empty >/dev/null 2>&1; then
        return 1
    fi
    
    local name=$(echo "$response" | jq -r ".\"$appid\".data.name // empty")
    
    if [ -n "$name" ] && [ "$name" != "null" ]; then
        echo "$name" > "$cache_file"
        echo "$name"
        return 0
    fi
    
    return 1
}

# Function to scan Steam libraries and find games
scan_steam_libraries() {
    echo -n "Scanning Steam libraries... "
    
    # Find all valid Steam directories
    valid_steam_dirs=()
    for path in "${DEFAULT_STEAM_DIRS[@]}"; do
        if [ -d "$path" ]; then
            valid_steam_dirs+=("$path")
        fi
    done
    
    # Add custom Steam library folders
    for steam_dir in "${valid_steam_dirs[@]}"; do
        if [ -f "$steam_dir/steamapps/libraryfolders.vdf" ]; then
            # Extract library paths from libraryfolders.vdf
            while read -r line; do
                # Skip empty lines and lines without path
                [[ -z "$line" || "$line" != *"path"* ]] && continue
                
                # Extract the path
                lib_path=$(echo "$line" | grep -oP '"path"\s+"\K[^"]+')
                if [ -n "$lib_path" ] && [ -d "$lib_path" ]; then
                    valid_steam_dirs+=("$lib_path")
                fi
            done < <(grep "path" "$steam_dir/steamapps/libraryfolders.vdf")
        fi
    done
    
    if [ ${#valid_steam_dirs[@]} -eq 0 ]; then
        echo "Error: No valid Steam directories found"
        exit 1
    fi
    
    # Collect game IDs from all valid directories
    game_ids=()
    valid_games=()
    
    for steam_dir in "${valid_steam_dirs[@]}"; do
        local steamapps_dir="$steam_dir/steamapps"
        if [ -d "$steamapps_dir" ]; then
            # Find all appmanifest files
            for manifest in "$steamapps_dir"/appmanifest_*.acf; do
                if [ -f "$manifest" ]; then
                    # Extract app ID from filename
                    local appid=$(basename "$manifest" | sed -n 's/appmanifest_\(.*\)\.acf/\1/p')
                    if [[ "$appid" =~ ^[0-9]+$ ]]; then
                        game_ids+=("$appid")
                    fi
                fi
            done
        fi
    done
    
    # Remove duplicates
    game_ids=($(echo "${game_ids[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    echo "Done!"
    echo "Found the following games in Steam libraries:"
    
    for id in "${game_ids[@]}"; do
        game_name=$(get_game_name "$id")
        if [ $? -eq 0 ]; then
            valid_games+=("$id:$game_name")
            echo "  - $id: $game_name"
        else
            echo "  - $id: (Unknown game)"
        fi
    done
    
    if [ ${#valid_games[@]} -eq 0 ]; then
        echo "No Steam games found"
        exit 1
    fi
}

# Function to ask user which games to symlink
select_games() {
    echo "Please select the games you want to symlink into the Vortex Wine prefix (space separated numbers):"
    
    # Create array of formatted game names for selection
    local i=1
    for game in "${valid_games[@]}"; do
        id=$(echo "$game" | cut -d: -f1)
        name=$(echo "$game" | cut -d: -f2-)
        printf "%d) %s (ID: %s)\n" "$i" "$name" "$id"
        i=$((i+1))
    done
    
    read -p "Enter selection (space separated numbers): " selections
    
    selected_games=()
    for sel in $selections; do
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -le "${#valid_games[@]}" ]; then
            selected_id=$(echo "${valid_games[$((sel-1))]}" | cut -d: -f1)
            selected_games+=("$selected_id")
            echo "Added ${valid_games[$((sel-1))]} to selection"
        else
            echo "Invalid selection: $sel"
        fi
    done
    
    if [ ${#selected_games[@]} -eq 0 ]; then
        echo "No valid games selected. Exiting."
        exit 0
    fi
    
    # Save selected games to config file
    for game_id in "${selected_games[@]}"; do
        # Check if game is already in config
        if ! grep -q "^GAME_ID=$game_id$" "$CONFIG_FILE" 2>/dev/null; then
            echo "GAME_ID=$game_id" >> "$CONFIG_FILE"
        fi
    done
}

# Function to create backups
create_backup() {
    echo -n "Creating backup of Wine prefix... "
    mkdir -p "$BACKUP_DIR"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="$BACKUP_DIR/vortex_wine_${timestamp}.tar.gz"
    
    if ! tar -czf "$backup_file" -C "$WINE_PREFIX" .; then
        echo "Failed to create backup of Wine prefix"
        exit 1
    fi
    echo "Done! Backup saved to $backup_file"
}

# Function to symlink directories
symlink_directories() {
    for game_id in "${selected_games[@]}"; do
        # Find game directory
        game_dir=""
        game_name=""
        
        # Extract game name from valid_games array
        for game in "${valid_games[@]}"; do
            if [[ "$game" == "$game_id:"* ]]; then
                game_name=$(echo "$game" | cut -d: -f2-)
                break
            fi
        done
        
        echo "Processing game: $game_name (ID: $game_id)"
        
        # Find the game installation directory
        for steam_dir in "${valid_steam_dirs[@]}"; do
            local steamapps_dir="$steam_dir/steamapps"
            local common_dir="$steamapps_dir/common"
            local manifest_file="$steamapps_dir/appmanifest_$game_id.acf"
            
            if [ -f "$manifest_file" ]; then
                # Try to get installdir from manifest
                install_dir=$(grep -oP '"installdir"\s+"\K[^"]+' "$manifest_file")
                if [ -n "$install_dir" ] && [ -d "$common_dir/$install_dir" ]; then
                    game_dir="$common_dir/$install_dir"
                    break
                fi
                
                # If installdir doesn't work, try other methods
                if [ -z "$game_dir" ] && [ -n "$game_name" ]; then
                    # Try exact name match
                    if [ -d "$common_dir/$game_name" ]; then
                        game_dir="$common_dir/$game_name"
                        break
                    fi
                    
                    # Try case-insensitive search
                    found_dir=$(find "$common_dir" -maxdepth 1 -type d -iname "$game_name" -print -quit)
                    if [ -n "$found_dir" ] && [ -d "$found_dir" ]; then
                        game_dir="$found_dir"
                        break
                    fi
                    
                    # Try alternative naming patterns
                    alt_name=$(echo "$game_name" | tr -d '[:space:]-' | tr '[:upper:]' '[:lower:]')
                    found_dir=$(find "$common_dir" -maxdepth 1 -type d -iname "*$alt_name*" -print -quit)
                    if [ -n "$found_dir" ] && [ -d "$found_dir" ]; then
                        game_dir="$found_dir"
                        break
                    fi
                    
                    # Try looking for the game ID in the directory name
                    found_dir=$(find "$common_dir" -maxdepth 1 -type d -name "*$game_id*" -print -quit)
                    if [ -n "$found_dir" ] && [ -d "$found_dir" ]; then
                        game_dir="$found_dir"
                        break
                    fi
                fi
            fi
        done
        
        # If game directory still not found, ask user
        if [ -z "$game_dir" ]; then
            echo "Could not automatically find game directory for $game_name (ID: $game_id)"
            echo "Please enter the full path to the game directory:"
            read -p "> " user_game_dir
            
            if [ -d "$user_game_dir" ]; then
                game_dir="$user_game_dir"
            else
                echo "Directory not found. Skipping this game."
                continue
            fi
        fi
        
        # Create symlink to game directory in Wine prefix
        echo -n "  Symlinking game files... "
        if [ "$dry_run" = true ]; then
            echo "DRY RUN: ln -sf \"$game_dir\" \"$WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common/$(basename "$game_dir")\""
        else
            # Create Windows-style Steam directory structure in Wine prefix
            mkdir -p "$WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common"
            
            # Convert Linux path to Windows-style path for better compatibility
            windows_game_dir=$(winepath -w "$game_dir")
            
            # First, ensure target directory doesn't exist or is empty
            target_dir="$WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common/$(basename "$game_dir")"
            if [ -e "$target_dir" ]; then
                echo "Target directory exists, removing it first..."
                rm -rf "$target_dir"
            fi
            
            # Create parent directory structure
            mkdir -p "$WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common"
            
            # Get absolute path to game directory
            abs_game_dir=$(realpath "$game_dir")
            game_basename=$(basename "$abs_game_dir")
            
            # Create a direct Z: drive mapping for the game directory
            echo "Creating direct Z: drive mapping for better compatibility..."
            mkdir -p "$WINE_PREFIX/dosdevices"
            rm -f "$WINE_PREFIX/dosdevices/z:"
            ln -sf / "$WINE_PREFIX/dosdevices/z:"
            
            # Create a Windows-style path for the Z: drive mapping
            z_drive_path="Z:$(echo "$abs_game_dir" | sed 's|/|\\\\|g')"
            
            # Create a junction point using the Z: drive path
            echo -n "Creating junction point using Z: drive... "
            wine cmd /c "mklink /J \"C:\\Program Files (x86)\\Steam\\steamapps\\common\\$game_basename\" \"$z_drive_path\"" >/dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                echo "Success!"
                
                # Verify the junction point
                echo -n "Verifying junction point... "
                if wine cmd /c "dir \"C:\\Program Files (x86)\\Steam\\steamapps\\common\\$game_basename\"" >/dev/null 2>&1; then
                    echo "Verified!"
                    
                    # Count files to verify content
                    file_count=$(find "$abs_game_dir" -type f | wc -l)
                    echo "  Found $file_count files in source directory"
                    
                    # Try to count files through Wine
                    wine_file_count=$(wine cmd /c "dir /s /b \"C:\\Program Files (x86)\\Steam\\steamapps\\common\\$game_basename\" | find /c /v \"\"" 2>/dev/null)
                    echo "  Files visible to Wine: $wine_file_count"
                    
                    # Create a test file to verify Wine can see and write to it
                    echo "Testing Wine visibility and write access..."
                    wine cmd /c "echo Test > \"C:\\Program Files (x86)\\Steam\\steamapps\\common\\$game_basename\\vortex_test.txt\"" >/dev/null 2>&1
                    
                    if [ -f "$abs_game_dir/vortex_test.txt" ]; then
                        echo "  Test file created successfully through Wine"
                        rm -f "$abs_game_dir/vortex_test.txt"
                    else
                        echo "  Warning: Could not create test file through Wine"
                    fi
                else
                    echo "Failed to verify junction point"
                fi
            else
                echo "Junction point failed. Trying direct copy..."
                
                # Create the directory first
                mkdir -p "$target_dir"
                
                # Use rsync for copying if available
                if command -v rsync &> /dev/null; then
                    echo "Copying game files with rsync (this may take a while)..."
                    rsync -a --info=progress2 "$abs_game_dir/" "$target_dir/"
                    if [ $? -eq 0 ]; then
                        echo "Game files copied successfully with rsync"
                    else
                        echo "Error: Failed to copy game files with rsync"
                        exit 1
                    fi
                else
                    # Fall back to cp
                    echo "Copying game files (this may take a while)..."
                    cp -r "$abs_game_dir/"* "$target_dir/"
                    if [ $? -eq 0 ]; then
                        echo "Game files copied successfully"
                    else
                        echo "Error: Failed to copy game files"
                        exit 1
                    fi
                fi
            fi
            echo "Done!"
        fi
        
        # Check for game-specific documents folder
        echo -n "  Checking for game documents... "
        game_docs_dir=""
        
        # Common patterns for game document folders
        doc_patterns=(
            "My Games/$game_name"
            "My Games/$(basename "$game_dir")"
            "$game_name"
            "$(basename "$game_dir")"
        )
        
        for pattern in "${doc_patterns[@]}"; do
            if [ -d "$HOME/Documents/$pattern" ]; then
                game_docs_dir="$HOME/Documents/$pattern"
                break
            fi
        done
        
        if [ -n "$game_docs_dir" ]; then
            echo "Found at $game_docs_dir"
            echo -n "  Symlinking game documents... "
            
            if [ "$dry_run" = true ]; then
                echo "DRY RUN: mkdir -p \"$WINE_PREFIX/drive_c/users/$USER/Documents/$(dirname "$pattern")\""
                echo "DRY RUN: ln -sf \"$game_docs_dir\" \"$WINE_PREFIX/drive_c/users/$USER/Documents/$pattern\""
            else
                # Create parent directory if needed
                parent_dir=$(dirname "$pattern")
                if [ "$parent_dir" != "." ]; then
                    mkdir -p "$WINE_PREFIX/drive_c/users/$USER/Documents/$parent_dir"
                fi
                
                # Create symlink
                ln -sf "$game_docs_dir" "$WINE_PREFIX/drive_c/users/$USER/Documents/$pattern" || \
                    echo "Failed to symlink game documents for $game_name"
                echo "Done!"
            fi
        else
            echo "Not found (this is normal for some games)"
        fi
        
        # Check for game-specific AppData folder
        echo -n "  Checking for game AppData... "
        game_appdata_dir=""
        
        # Common patterns for game AppData folders
        appdata_patterns=(
            "Local/$game_name"
            "Local/$(basename "$game_dir")"
            "Roaming/$game_name"
            "Roaming/$(basename "$game_dir")"
        )
        
        for pattern in "${appdata_patterns[@]}"; do
            if [ -d "$HOME/.local/share/Steam/steamapps/compatdata/$game_id/pfx/drive_c/users/steamuser/AppData/$pattern" ]; then
                game_appdata_dir="$HOME/.local/share/Steam/steamapps/compatdata/$game_id/pfx/drive_c/users/steamuser/AppData/$pattern"
                break
            fi
        done
        
        if [ -n "$game_appdata_dir" ]; then
            echo "Found at $game_appdata_dir"
            echo -n "  Symlinking game AppData... "
            
            if [ "$dry_run" = true ]; then
                echo "DRY RUN: mkdir -p \"$WINE_PREFIX/drive_c/users/$USER/AppData/$(dirname "$pattern")\""
                echo "DRY RUN: ln -sf \"$game_appdata_dir\" \"$WINE_PREFIX/drive_c/users/$USER/AppData/$pattern\""
            else
                # Create parent directory if needed
                parent_dir=$(dirname "$pattern")
                mkdir -p "$WINE_PREFIX/drive_c/users/$USER/AppData/$parent_dir"
                
                # Create symlink
                ln -sf "$game_appdata_dir" "$WINE_PREFIX/drive_c/users/$USER/AppData/$pattern" || \
                    echo "Failed to symlink game AppData for $game_name"
                echo "Done!"
            fi
        else
            echo "Not found (this is normal for most games)"
        fi
    done
    
    echo "Symlinking completed for all selected games."
    
    # Create registry entries for Vortex to find games
    create_vortex_registry_entries
    
    # Verify symlinks
    verify_symlinks
}

# Function to create registry entries for Vortex
create_vortex_registry_entries() {
    echo "Creating registry entries for Vortex to find games..."
    
    # Create the base registry key for Vortex
    wine reg add "HKEY_CURRENT_USER\\Software\\Vortex" /f >/dev/null 2>&1
    wine reg add "HKEY_CURRENT_USER\\Software\\Vortex\\gameRegistry" /f >/dev/null 2>&1
    
    for game_id in "${selected_games[@]}"; do
        game_name=$(get_game_name "$game_id")
        
        # Find game directory
        game_dir=""
        for steam_dir in "${valid_steam_dirs[@]}"; do
            local steamapps_dir="$steam_dir/steamapps"
            local common_dir="$steamapps_dir/common"
            local manifest_file="$steamapps_dir/appmanifest_$game_id.acf"
            
            if [ -f "$manifest_file" ]; then
                install_dir=$(grep -oP '"installdir"\s+"\K[^"]+' "$manifest_file")
                if [ -n "$install_dir" ] && [ -d "$common_dir/$install_dir" ]; then
                    game_dir="$common_dir/$install_dir"
                    break
                fi
                
                # Try with game name
                if [ -d "$common_dir/$game_name" ]; then
                    game_dir="$common_dir/$game_name"
                    break
                fi
            fi
        done
        
        if [ -z "$game_dir" ]; then
            echo "Could not find source directory for $game_name, skipping registry entry"
            continue
        fi
        
        game_basename=$(basename "$game_dir")
        windows_path="C:\\Program Files (x86)\\Steam\\steamapps\\common\\$game_basename"
        
        # Create registry entries for this game
        echo "Creating registry entry for $game_name..."
        
        # Main game registry entry
        wine reg add "HKEY_CURRENT_USER\\Software\\Vortex\\gameRegistry\\$game_id" /v "gamePath" /t REG_SZ /d "$windows_path" /f >/dev/null 2>&1
        wine reg add "HKEY_CURRENT_USER\\Software\\Vortex\\gameRegistry\\$game_id" /v "gameName" /t REG_SZ /d "$game_name" /f >/dev/null 2>&1
        wine reg add "HKEY_CURRENT_USER\\Software\\Vortex\\gameRegistry\\$game_id" /v "discovered" /t REG_DWORD /d 1 /f >/dev/null 2>&1
    done
}

# Function to verify symlinks
verify_symlinks() {
    echo "Verifying symlinks..."
    
    for game_id in "${selected_games[@]}"; do
        game_name=$(get_game_name "$game_id")
        
        # Find game directory
        game_dir=""
        for steam_dir in "${valid_steam_dirs[@]}"; do
            local steamapps_dir="$steam_dir/steamapps"
            local common_dir="$steamapps_dir/common"
            local manifest_file="$steamapps_dir/appmanifest_$game_id.acf"
            
            if [ -f "$manifest_file" ]; then
                install_dir=$(grep -oP '"installdir"\s+"\K[^"]+' "$manifest_file")
                if [ -n "$install_dir" ] && [ -d "$common_dir/$install_dir" ]; then
                    game_dir="$common_dir/$install_dir"
                    break
                fi
                
                # Try with game name
                if [ -d "$common_dir/$game_name" ]; then
                    game_dir="$common_dir/$game_name"
                    break
                fi
            fi
        done
        
        if [ -z "$game_dir" ]; then
            echo "Could not find source directory for $game_name, skipping verification"
            continue
        fi
        
        target_dir="$WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common/$(basename "$game_dir")"
        
        echo -n "Verifying $game_name... "
        
        if [ -d "$target_dir" ]; then
            # Check if it's a symlink
            if [ -L "$target_dir" ]; then
                echo "Native symlink OK"
                # Check if the symlink target exists
                if [ -e "$(readlink -f "$target_dir")" ]; then
                    echo "  Symlink target exists and is accessible"
                else
                    echo "  Warning: Symlink target doesn't exist or isn't accessible"
                fi
            # Check if it's a junction point or regular directory
            elif wine cmd /c "dir \"C:\\Program Files (x86)\\Steam\\steamapps\\common\\$(basename "$game_dir")\"" >/dev/null 2>&1; then
                echo "Windows junction point or directory OK"
                
                # Count files to verify content
                wine_file_count=$(wine cmd /c "dir /s /b \"C:\\Program Files (x86)\\Steam\\steamapps\\common\\$(basename "$game_dir")\" | find /c /v \"\"" 2>/dev/null)
                echo "  Files visible to Wine: $wine_file_count"
                
                # Create and verify test file
                test_file="$target_dir/.vortex_test"
                echo "Test file for verification" > "$test_file"
                if wine cmd /c "type \"C:\\Program Files (x86)\\Steam\\steamapps\\common\\$(basename "$game_dir")\\.vortex_test\"" >/dev/null 2>&1; then
                    echo "  Test file readable by Wine: Yes"
                    rm -f "$test_file"
                else
                    echo "  Test file readable by Wine: No"
                fi
            else
                echo "Directory exists but may not be accessible by Wine"
            fi
            
            # Check permissions
            if [ -r "$target_dir" ]; then
                echo "  Read permission: Yes"
            else
                echo "  Read permission: No"
            fi
            
            if [ -w "$target_dir" ]; then
                echo "  Write permission: Yes"
            else
                echo "  Write permission: No"
            fi
            
            if [ -x "$target_dir" ]; then
                echo "  Execute permission: Yes"
            else
                echo "  Execute permission: No"
            fi
        else
            echo "Missing or inaccessible"
        fi
    done
    
    echo "Verification complete."
}

# Function to clean up Wine processes
cleanup_wine() {
    echo "Cleaning up Wine processes..."
    wineserver -k || true
    pkill -f "wineserver" || true
    pkill -f "wine" || true
    pkill -f "Vortex.exe" || true
    echo "Wine processes cleaned up."
}

# Function to launch Vortex
launch_vortex() {
    echo "Launching Vortex..."
    
    # Clean up any existing Wine processes first
    cleanup_wine
    
    # Find Vortex executable
    vortex_exe=$(find "$WINE_PREFIX" -name "Vortex.exe" -print -quit)
    
    if [ -z "$vortex_exe" ]; then
        echo "Error: Could not find Vortex.exe in Wine prefix"
        exit 1
    fi
    
    # Ensure X server is accessible
    if ! xhost >/dev/null 2>&1; then
        echo "X server access not available, attempting to fix..."
        xhost +local: >/dev/null 2>&1
    fi
    
    # Ensure XDG_RUNTIME_DIR is set
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        if [ ! -d "$XDG_RUNTIME_DIR" ]; then
            export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
            mkdir -p "$XDG_RUNTIME_DIR"
            chmod 0700 "$XDG_RUNTIME_DIR"
        fi
    fi
    
    # Set up Wine environment
    export WINEPREFIX="$WINE_PREFIX"
    export WINEARCH="win64"
    export WINEDEBUG="-all,err+all,fixme+all"
    export WINEDLLOVERRIDES="winemenubuilder.exe=d"
    export DISPLAY=":0"
    export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
    
    # Enable file system redirection for better compatibility
    export WINEDLLOVERRIDES="$WINEDLLOVERRIDES;fusion=n;mscoree=n"
    
    # Enable better symlink handling
    export WINE_ENABLE_SYMLINKS=1
    
    # Create a clean environment with necessary variables
    env -i \
        HOME="$HOME" \
        USER="$USER" \
        LOGNAME="$LOGNAME" \
        PATH="/usr/bin:/bin:/usr/local/bin" \
        WINEPREFIX="$WINE_PREFIX" \
        WINEARCH="win64" \
        WINEDEBUG="-all,err+all,fixme+all" \
        WINEDLLOVERRIDES="winemenubuilder.exe=d;fusion=n;mscoree=n" \
        WINE_ENABLE_SYMLINKS=1 \
        DISPLAY="$DISPLAY" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        PULSE_SERVER="$PULSE_SERVER" \
        LANG="en_US.UTF-8" \
        LC_ALL="en_US.UTF-8" \
        wine "$vortex_exe" > "$LOG_FILE" 2>&1
    
    # Check if Vortex exited successfully
    if [ $? -eq 0 ]; then
        echo "Vortex exited successfully"
    else
        echo "Vortex exited with an error"
        echo "Check the log file at $LOG_FILE for more details"
    fi
    
    # Clean up after Vortex exits
    cleanup_wine
}

# Function to load previously selected games
load_selected_games() {
    if [ -f "$CONFIG_FILE" ]; then
        selected_games=()
        while IFS= read -r line; do
            if [[ "$line" == GAME_ID=* ]]; then
                game_id="${line#GAME_ID=}"
                selected_games+=("$game_id")
            fi
        done < "$CONFIG_FILE"
    fi
}

# Main script execution
dry_run=false
do_backup=false
verbose=false
force_install=false
add_games=false
custom_paths=()

# Create config directory if it doesn't exist
mkdir -p "$(dirname "$CONFIG_FILE")"
touch "$CONFIG_FILE"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -i|--install)
            force_install=true
            shift
            ;;
        -a|--add-games)
            add_games=true
            shift
            ;;
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        -b|--backup)
            do_backup=true
            shift
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -p|--path)
            if [ -d "$2" ]; then
                custom_paths+=("$2")
                shift 2
            else
                echo "Invalid path: $2"
                exit 1
            fi
            ;;
        -w|--wine)
            WINE_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "Starting SuperLVLinker..."
echo "Log file: $LOG_FILE"

# Add custom paths to Steam directories search
if [ ${#custom_paths[@]} -gt 0 ]; then
    for path in "${custom_paths[@]}"; do
        DEFAULT_STEAM_DIRS+=("$path")
    done
fi

# Check if Vortex is already installed
if ! verify_vortex_installation || [ "$force_install" = true ]; then
    echo "Vortex installation not found or reinstall requested."
    check_dependencies
    setup_wine_prefix
    install_vortex
    create_desktop_shortcut
    
    # First run, so we need to select games
    scan_steam_libraries
    select_games
    
    if [ "$do_backup" = true ]; then
        create_backup
    fi
    
    symlink_directories
    
    # Mark as first run complete
    echo "FIRST_RUN_COMPLETE=true" >> "$CONFIG_FILE"
    
    # Launch Vortex
    launch_vortex
elif [ "$add_games" = true ]; then
    # User wants to add more games
    echo "Adding more games to Vortex..."
    scan_steam_libraries
    select_games
    
    if [ "$do_backup" = true ]; then
        create_backup
    fi
    
    symlink_directories
    
    # Launch Vortex
    launch_vortex
else
    # Check if this is the first run after installation
    if ! grep -q "FIRST_RUN_COMPLETE=true" "$CONFIG_FILE"; then
        echo "First run after installation, setting up games..."
        scan_steam_libraries
        select_games
        
        if [ "$do_backup" = true ]; then
            create_backup
        fi
        
        symlink_directories
        
        # Mark as first run complete
        echo "FIRST_RUN_COMPLETE=true" >> "$CONFIG_FILE"
    else
        # Load previously selected games for reference
        load_selected_games
        echo "Found ${#selected_games[@]} previously linked games."
    fi
    
    # Just launch Vortex
    launch_vortex
fi

echo "All done! You can review the complete log at $LOG_FILE"
