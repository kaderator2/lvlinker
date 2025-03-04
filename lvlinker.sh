#!/bin/bash

# Configuration
STEAMCMD_APP_LIST="https://api.steampowered.com/ISteamApps/GetAppList/v2/"
DEFAULT_COMPATDATA=(
    "$HOME/.local/share/Steam/steamapps/compatdata"
)
BACKUP_DIR="$HOME/vortex_backups"
LOG_FILE="/tmp/lvlinker.log"

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help         Show this help message and exit"
    echo "  -d, --dry-run      Show what would be done without making changes"
    echo "  -b, --backup       Create backup before making changes"
    echo "  -v, --verbose      Show detailed output"
    echo "  -p, --path PATH    Add custom Steam compatdata path"
    echo
    echo "Example:"
    echo "  $0 -p /mnt/SlowGames/SteamLibrary/steamapps/compatdata"
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
    
    # Query Steam API
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

# Function to scan compatdata folder and find games
scan_compatdata() {
    echo -n "Scanning compatdata folders... "
    
    # Find all valid compatdata directories
    valid_compatdata=()
    for path in "${DEFAULT_COMPATDATA[@]}"; do
        if [ -d "$path" ]; then
            valid_compatdata+=("$path")
        fi
    done
    
    if [ ${#valid_compatdata[@]} -eq 0 ]; then
        echo "Error: No valid compatdata directories found"
        exit 1
    fi
    
    # Collect game IDs from all valid directories
    game_ids=()
    for compatdata in "${valid_compatdata[@]}"; do
        ids=($(ls "$compatdata"))
        game_ids+=("${ids[@]}")
    done
    valid_games=()
    
    echo "Done!"
    echo "Found the following games in compatdata:"
    
    for id in "${game_ids[@]}"; do
        game_name=$(get_game_name "$id")
        if [ $? -eq 0 ]; then
            valid_games+=("$id:$game_name")
            echo "  - $id: $game_name"
        else
            echo "  - $id: (Non-Steam game or unknown)"
        fi
    done
    
    if [ ${#valid_games[@]} -eq 0 ]; then
        echo "No Steam games found in compatdata"
        exit 1
    fi
}

# Function to detect Vortex folder automatically
auto_detect_vortex() {
    echo -n "Attempting to auto-detect Vortex installation... "
    for id in "${non_steam_folders[@]}"; do
        # Check all compatdata directories
        for compatdata in "${valid_compatdata[@]}"; do
            vortex_path="$compatdata/$id/pfx/drive_c/Program Files/Black Tree Gaming Ltd/Vortex"
            if [ -d "$vortex_path" ]; then
                echo "Found Vortex in folder $id"
                vortex_id="$id"
                vortex_dir="$compatdata/$vortex_id"
                return 0
            fi
        done
    done
    echo "Not found"
    return 1
}

# Function to ask user for Vortex compatdata ID
get_vortex_dir() {
    # Create array of non-Steam folders
    non_steam_folders=()
    for id in "${game_ids[@]}"; do
        # Check if this ID is not in valid_games
        is_steam_game=false
        for game in "${valid_games[@]}"; do
            if [[ "$game" == "$id:"* ]]; then
                is_steam_game=true
                break
            fi
        done
        
        if ! $is_steam_game; then
            non_steam_folders+=("$id")
        fi
    done
    
    if [ ${#non_steam_folders[@]} -eq 0 ]; then
        echo "Error: No non-Steam folders found. Vortex should be in a separate compatdata folder."
        exit 1
    fi
    
    # Try to auto-detect Vortex first
    if auto_detect_vortex; then
        return
    fi
    
    # If auto-detect fails, ask user to select
    echo "Please select the Vortex installation from the following non-Steam folders:"
    local i=1
    for id in "${non_steam_folders[@]}"; do
        printf "%d) %s\n" "$i" "$id"
        i=$((i+1))
    done
    
    read -p "Enter the number of the Vortex installation: " vortex_sel
    if [[ "$vortex_sel" =~ ^[0-9]+$ ]] && [ "$vortex_sel" -le "${#non_steam_folders[@]}" ]; then
        vortex_id="${non_steam_folders[$((vortex_sel-1))]}"
        vortex_dir="$STEAM_COMPATDATA/$vortex_id"
        echo "Vortex directory set to $vortex_dir"
    else
        echo "Invalid selection"
        exit 1
    fi
}

# Function to ask user which games to symlink
select_games() {
    echo "Please select the games you want to symlink into the Vortex drive (space separated numbers):"
    
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
    echo -n "Creating backup... "
    mkdir -p "$BACKUP_DIR"
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    for game_id in "${selected_games[@]}"; do
        game_compatdata_dir="$STEAM_COMPATDATA/$game_id"
        backup_file="$BACKUP_DIR/${game_id}_${timestamp}.tar.gz"
        
        if ! tar -czf "$backup_file" -C "$game_compatdata_dir" .; then
            echo "Failed to create backup for $game_id"
            exit 1
        fi
    done
    echo "Done! Backups saved to $BACKUP_DIR"
}

# Function to symlink directories
symlink_directories() {
    vortex_compatdata_dir="$vortex_dir/compatdata"
    
    for game_id in "${selected_games[@]}"; do
        # Find which compatdata directory contains this game
        game_compatdata_dir=""
        for compatdata in "${valid_compatdata[@]}"; do
            if [ -d "$compatdata/$game_id" ]; then
                game_compatdata_dir="$compatdata/$game_id"
                break
            fi
        done
        
        if [ -z "$game_compatdata_dir" ]; then
            echo "Error: Could not find game $game_id in any compatdata directory"
            continue
        fi
        
        echo "Processing game ID: $game_id"
        
        # Create necessary directory structure
        mkdir -p "$game_compatdata_dir/pfx/drive_c/users/steamuser"
        mkdir -p "$vortex_compatdata_dir/pfx/drive_c/users/steamuser"

        # AppData symlink
        echo -n "  Symlinking AppData... "
        if [ "$dry_run" = true ]; then
            echo "DRY RUN: ln -sf \"$vortex_compatdata_dir/pfx/drive_c/users/steamuser/AppData\" \"$game_compatdata_dir/pfx/drive_c/users/steamuser/AppData\""
        else
            ln -sf "$vortex_compatdata_dir/pfx/drive_c/users/steamuser/AppData" "$game_compatdata_dir/pfx/drive_c/users/steamuser/AppData" || {
                echo "Failed to symlink AppData for $game_id"
                exit 1
            }
            echo "Done!"
        fi

        # Documents symlink
        echo -n "  Symlinking Documents... "
        if [ "$dry_run" = true ]; then
            echo "DRY RUN: ln -sf \"$game_compatdata_dir/pfx/drive_c/users/steamuser/Documents\" \"$vortex_compatdata_dir/pfx/drive_c/users/steamuser/Documents\""
        else
            ln -sf "$game_compatdata_dir/pfx/drive_c/users/steamuser/Documents" "$vortex_compatdata_dir/pfx/drive_c/users/steamuser/Documents" || {
                echo "Failed to symlink Documents for $game_id"
                exit 1
            }
            echo "Done!"
        fi

        # Game files symlink
        echo -n "  Symlinking game files... "
        # Find the common directory (one level up from compatdata)
        common_dir=$(dirname "$(dirname "$game_compatdata_dir")")/common
        if [ -d "$common_dir" ]; then
            # Find the game directory (using the game name from valid_games)
            game_name=$(echo "${valid_games[@]}" | grep -oP "$game_id:\K[^:]+")
            if [ -n "$game_name" ] && [ -d "$common_dir/$game_name" ]; then
                if [ "$dry_run" = true ]; then
                    echo "DRY RUN: ln -sf \"$common_dir/$game_name\" \"$vortex_dir/common/$game_name\""
                else
                    mkdir -p "$vortex_dir/common"
                    ln -sf "$common_dir/$game_name" "$vortex_dir/common/$game_name" || {
                        echo "Failed to symlink game files for $game_id"
                        exit 1
                    }
                    echo "Done!"
                fi
            else
                echo "Skipped (game directory not found)"
            fi
        else
            echo "Skipped (common directory not found)"
        fi
    done
    
    echo "Symlinking completed for all selected games."
}

# Main script execution
dry_run=false
do_backup=false
verbose=false
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
        -p|--path)
            if [ -d "$2" ]; then
                custom_paths+=("$2")
                shift 2
            else
                echo "Invalid path: $2"
                exit 1
            fi
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Add custom paths to compatdata search
if [ ${#custom_paths[@]} -gt 0 ]; then
    for path in "${custom_paths[@]}"; do
        DEFAULT_COMPATDATA+=("$path")
    done
fi

echo "Starting Vortex Linker..."
echo "Log file: $LOG_FILE"

scan_compatdata
get_vortex_dir
select_games

if [ "$do_backup" = true ]; then
    create_backup
fi

symlink_directories

echo "All done! Vortex should now recognize the selected games as being on the same drive."
echo "You can review the complete log at $LOG_FILE"
