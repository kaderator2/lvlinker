#!/bin/bash

# Configuration
STEAMDB_URL="https://steamdb.info/apps/"
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

# Function to fetch Steam game IDs from SteamDB
fetch_steam_game_ids() {
    echo -n "Fetching Steam game IDs from SteamDB... "
    if ! curl -s "$STEAMDB_URL" | grep -oP 'data-appid="\K[0-9]+' | sort -u > /tmp/steam_game_ids.txt; then
        echo "Failed to fetch game IDs from SteamDB"
        exit 1
    fi
    echo "Done! ($(wc -l < /tmp/steam_game_ids.txt) IDs found)"
}

# Function to scan compatdata folder and find game IDs
scan_compatdata() {
    echo -n "Scanning compatdata folder... "
    if [ ! -d "$STEAM_COMPATDATA" ]; then
        echo "Error: compatdata directory not found at $STEAM_COMPATDATA"
        exit 1
    fi

    game_ids=($(ls "$STEAM_COMPATDATA"))
    valid_game_ids=()
    
    echo "Done!"
    echo "Found the following valid game IDs in compatdata:"
    for id in "${game_ids[@]}"; do
        if grep -q "^$id$" /tmp/steam_game_ids.txt; then
            valid_game_ids+=("$id")
            echo "  - $id"
        fi
    done
    
    if [ ${#valid_game_ids[@]} -eq 0 ]; then
        echo "No valid game IDs found in compatdata"
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
    select game_name in "${game_ids[@]}" "Done"; do
        if [ "$game_name" == "Done" ]; then
            break
        elif [ -n "$game_name" ]; then
            selected_games+=("$game_name")
            echo "Added $game_name to selection"
        else
            echo "Invalid selection. Please try again."
        fi
    done
    
    if [ ${#selected_games[@]} -eq 0 ]; then
        echo "No games selected. Exiting."
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

fetch_steam_game_ids
scan_compatdata
get_vortex_dir
select_games

if [ "$do_backup" = true ]; then
    create_backup
fi

symlink_directories

echo "All done! Vortex should now recognize the selected games as being on the same drive."
echo "You can review the complete log at $LOG_FILE"
