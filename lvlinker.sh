#!/bin/bash

# Configuration
STEAMCMD_APP_LIST="https://api.steampowered.com/ISteamApps/GetAppList/v2/"
DEFAULT_STEAM_DIRS=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
)
WINE_PREFIX="$HOME/.vortex_wine"
BACKUP_DIR="$HOME/vortex_backups"
LOG_FILE="/tmp/lvlinker.log"
VERSION="2.0.0"

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to display usage
usage() {
    echo "Linux Vortex Linker v$VERSION"
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help         Show this help message and exit"
    echo "  -d, --dry-run      Show what would be done without making changes"
    echo "  -b, --backup       Create backup before making changes"
    echo "  -v, --verbose      Show detailed output"
    echo "  -p, --path PATH    Add custom Steam library path"
    echo "  -w, --wine PATH    Set custom Wine prefix path (default: $WINE_PREFIX)"
    echo "  -i, --install      Run the Vortex installer script (if available)"
    echo
    echo "Example:"
    echo "  $0 -p /mnt/SlowGames/SteamLibrary -w ~/.wine_vortex"
    echo
    echo "Note: If you haven't installed Vortex yet, run './install_vortex.sh' first"
    echo "      or use the -i option to run the installer automatically."
    exit 1
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

# Function to verify Wine prefix
verify_wine_prefix() {
    echo -n "Verifying Wine prefix... "
    
    if [ ! -d "$WINE_PREFIX" ]; then
        echo "Error: Wine prefix not found at $WINE_PREFIX"
        echo "Please make sure Vortex is properly installed using install_vortex.sh"
        echo "or specify the correct Wine prefix path with -w option"
        exit 1
    fi
    
    # Check for Vortex installation
    vortex_exe=$(find "$WINE_PREFIX" -name "Vortex.exe" -print -quit)
    if [ -z "$vortex_exe" ]; then
        echo "Error: Vortex.exe not found in Wine prefix at $WINE_PREFIX"
        echo "Please make sure Vortex is properly installed using install_vortex.sh"
        exit 1
    fi
    
    echo "Found Vortex at $vortex_exe"
    
    # Create necessary directories if they don't exist
    mkdir -p "$WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common"
    mkdir -p "$WINE_PREFIX/drive_c/users/$USER/AppData/Roaming"
    mkdir -p "$WINE_PREFIX/drive_c/users/$USER/Documents"
    
    return 0
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
                }
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
            ln -sf "$game_dir" "$WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common/$(basename "$game_dir")" || {
                echo "Failed to symlink game files for $game_name"
                exit 1
            }
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
    done
    
    echo "Symlinking completed for all selected games."
}

# Function to run Vortex installer
run_installer() {
    if [ -f "./install_vortex.sh" ]; then
        echo "Running Vortex installer script..."
        chmod +x ./install_vortex.sh
        ./install_vortex.sh
        
        if [ $? -ne 0 ]; then
            echo "Vortex installation failed. Please check the logs."
            exit 1
        fi
        
        echo "Vortex installation completed. Continuing with linking..."
    else
        echo "Error: install_vortex.sh not found in the current directory."
        echo "Please download and run the installer script first."
        exit 1
    fi
}

# Main script execution
dry_run=false
do_backup=false
verbose=false
run_install=false
custom_paths=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
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
        -i|--install)
            run_install=true
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

# Run installer if requested
if [ "$run_install" = true ]; then
    run_installer
fi

# Add custom paths to Steam directories search
if [ ${#custom_paths[@]} -gt 0 ]; then
    for path in "${custom_paths[@]}"; then
        DEFAULT_STEAM_DIRS+=("$path")
    done
fi

echo "Starting Linux Vortex Linker v$VERSION..."
echo "Log file: $LOG_FILE"

verify_wine_prefix
scan_steam_libraries
select_games

if [ "$do_backup" = true ]; then
    create_backup
fi

symlink_directories

echo "All done! Vortex should now recognize the selected games as being on the same drive."
echo "You can review the complete log at $LOG_FILE"

# Final instructions
echo
echo "Next steps:"
echo "1. Launch Vortex using the desktop shortcut or with:"
echo "   env WINEPREFIX=\"$WINE_PREFIX\" wine \"$(find "$WINE_PREFIX" -name "Vortex.exe" -print -quit)\""
echo "2. In Vortex, go to Settings > Games"
echo "3. Add your games and set their paths to:"
echo "   C:\\Program Files (x86)\\Steam\\steamapps\\common\\<GameName>"
echo "4. Enjoy modding on Linux!"
