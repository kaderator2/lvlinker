#!/bin/bash

# Configuration
STEAMCMD_APP_LIST="https://api.steampowered.com/ISteamApps/GetAppList/v2/"
STEAM_COMPATDATA="$HOME/.local/share/Steam/steamapps/compatdata"
BACKUP_DIR="$HOME/vortex_backups"
LOG_FILE="/tmp/lvlinker.log"

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -d, --dry-run    Show what would be done without making changes"
    echo "  -b, --backup     Create backup before making changes"
    echo "  -v, --verbose    Show detailed output"
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
    local name=$(curl -s "$url" | jq -r ".\"$appid\".data.name")
    
    if [ "$name" != "null" ] && [ -n "$name" ]; then
        echo "$name" > "$cache_file"
        echo "$name"
        return 0
    fi
    
    return 1
}

# Function to scan compatdata folder and find games
scan_compatdata() {
    echo -n "Scanning compatdata folder... "
    if [ ! -d "$STEAM_COMPATDATA" ]; then
        echo "Error: compatdata directory not found at $STEAM_COMPATDATA"
        exit 1
    fi

    game_ids=($(ls "$STEAM_COMPATDATA"))
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

# Function to ask user for Vortex install directory
get_vortex_dir() {
    read -p "Enter the directory where Vortex is installed: " vortex_dir
    if [ ! -d "$vortex_dir" ]; then
        echo "Directory $vortex_dir does not exist."
        exit 1
    fi
    echo "Vortex directory set to $vortex_dir"
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
        game_compatdata_dir="$STEAM_COMPATDATA/$game_id"
        
        echo "Processing game ID: $game_id"
        
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
    done
    
    echo "Symlinking completed for all selected games."
}

# Main script execution
dry_run=false
do_backup=false
verbose=false

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
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

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
