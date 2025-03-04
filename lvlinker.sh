#!/bin/bash

# Configuration
STEAMCMD_APP_LIST="https://api.steampowered.com/ISteamApps/GetAppList/v2/"
DEFAULT_COMPATDATA=(
    "$HOME/.local/share/Steam/steamapps/compatdata"
)
BACKUP_DIR="$HOME/vortex_backups"
LOG_FILE="/tmp/lvlinker.log"
VERSION="1.0.0"

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
    echo "  -p, --path PATH    Add custom Steam compatdata path"
    echo "  -i, --install      Run the Vortex installer script (if available)"
    echo
    echo "Example:"
    echo "  $0 -p /mnt/SlowGames/SteamLibrary/steamapps/compatdata"
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
    for compatdata in "${DEFAULT_COMPATDATA[@]}"; do
        local steamapps_dir=$(dirname "$(dirname "$compatdata")")
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
    # Create array of non-Steam folders, explicitly excluding 1000000 from game detection
    non_steam_folders=()
    for id in "${game_ids[@]}"; do
        # Skip the Vortex installation ID
        if [ "$id" == "1000000" ]; then
            continue
        fi
        
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
    
    # Always include 1000000 as a potential Vortex folder
    non_steam_folders+=("1000000")
    
    if [ ${#non_steam_folders[@]} -eq 0 ]; then
        echo "Error: No non-Steam folders found. Vortex should be in a separate compatdata folder."
        exit 1
    fi
    
    # Try to auto-detect Vortex first
    if auto_detect_vortex; then
        return
    fi
    
    echo "Please select your Vortex installation method:"
    echo "1) Choose from detected non-Steam folders"
    echo "2) Enter a custom compatdata ID"
    echo
    echo "Note: If you used the install_vortex.sh script, the ID should be 1000000"
    
    read -p "Enter your choice (1 or 2): " choice
    
    if [ "$choice" == "1" ]; then
        # List detected non-Steam folders
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
    elif [ "$choice" == "2" ]; then
        # Allow custom ID input
        read -p "Enter the full compatdata ID for Vortex: " custom_id
        if [[ "$custom_id" =~ ^[0-9]+$ ]]; then
            vortex_id="$custom_id"
            vortex_dir="$STEAM_COMPATDATA/$vortex_id"
            
            # Verify the directory exists, but don't prompt to create if it's 1000000
            if [ ! -d "$vortex_dir" ]; then
                if [ "$custom_id" == "1000000" ]; then
                    echo "Error: Vortex directory not found at $vortex_dir"
                    echo "Please make sure Vortex is properly installed using install_vortex.sh"
                    exit 1
                else
                    echo "Warning: Directory $vortex_dir does not exist"
                    read -p "Do you want to create it? (y/n): " create_choice
                    if [ "$create_choice" == "y" ]; then
                        mkdir -p "$vortex_dir"
                        echo "Created Vortex directory at $vortex_dir"
                    else
                        echo "Aborting..."
                        exit 1
                    fi
                fi
            fi
            
            echo "Vortex directory set to $vortex_dir"
        else
            echo "Invalid ID. Please enter a numeric ID."
            exit 1
        fi
    else
        echo "Invalid choice"
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
        mkdir -p "$game_compatdata_dir/pfx/drive_c/users/steamuser/Documents"
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
        # Find the steamapps directory (two levels up from compatdata)
        steamapps_dir=$(dirname "$(dirname "$game_compatdata_dir")")
        common_dir="$steamapps_dir/common"
        
        if [ -d "$common_dir" ]; then
            # Extract game name from valid_games array
            game_name=""
            for game in "${valid_games[@]}"; do
                if [[ "$game" == "$game_id:"* ]]; then
                    game_name=$(echo "$game" | cut -d: -f2-)
                    break
                fi
            done
            
            # Debug output for paths
            if [ "$verbose" = true ]; then
                echo -e "\nDEBUG:"
                echo "  Game ID: $game_id"
                echo "  Game Name: $game_name"
                echo "  Common Dir: $common_dir"
                echo "  Looking for game directory in:"
                ls -l "$common_dir"
                echo "  Steamapps Dir: $steamapps_dir"
                echo "  Game Compatdata Dir: $game_compatdata_dir"
            fi
            
            # Try multiple methods to find the game directory
            game_dir=""
            
            # Method 1: Try the exact path
            if [ -n "$game_name" ] && [ -d "$common_dir/$game_name" ]; then
                game_dir="$common_dir/$game_name"
                if [ "$verbose" = true ]; then
                    echo "  Found game directory at exact path: $game_dir"
                fi
            # Method 2: Try using the Steam manifest file
            elif [ -f "$steamapps_dir/appmanifest_$game_id.acf" ]; then
                install_dir=$(grep -oP '"installdir"\s+"\K[^"]+' "$steamapps_dir/appmanifest_$game_id.acf")
                if [ -n "$install_dir" ] && [ -d "$common_dir/$install_dir" ]; then
                    game_dir="$common_dir/$install_dir"
                    if [ "$verbose" = true ]; then
                        echo "  Found game directory from manifest: $game_dir"
                    fi
                fi
            fi
            
            # Method 3: If still not found, try case-insensitive search
            if [ -z "$game_dir" ] && [ -n "$game_name" ]; then
                if [ "$verbose" = true ]; then
                    echo "  Trying case-insensitive search for: $game_name"
                fi
                found_dir=$(find "$common_dir" -maxdepth 1 -type d -iname "$game_name" -print -quit)
                if [ -n "$found_dir" ] && [ -d "$found_dir" ]; then
                    game_dir="$found_dir"
                fi
            fi
            
            # Method 4: Try alternative naming patterns
            if [ -z "$game_dir" ] && [ -n "$game_name" ]; then
                if [ "$verbose" = true ]; then
                    echo "  Trying alternative naming patterns"
                fi
                # Try removing spaces and special characters
                alt_name=$(echo "$game_name" | tr -d '[:space:]-' | tr '[:upper:]' '[:lower:]')
                found_dir=$(find "$common_dir" -maxdepth 1 -type d -iname "*$alt_name*" -print -quit)
                if [ -n "$found_dir" ] && [ -d "$found_dir" ]; then
                    game_dir="$found_dir"
                fi
            fi
            
            # Method 5: Try looking for the game ID in the directory name
            if [ -z "$game_dir" ]; then
                if [ "$verbose" = true ]; then
                    echo "  Trying to find directory containing game ID: $game_id"
                fi
                found_dir=$(find "$common_dir" -maxdepth 1 -type d -name "*$game_id*" -print -quit)
                if [ -n "$found_dir" ] && [ -d "$found_dir" ]; then
                    game_dir="$found_dir"
                fi
            fi
            
            # Method 6: Last resort - ask the user to select from available directories
            if [ -z "$game_dir" ]; then
                echo -e "\nCould not automatically find game directory for ID $game_id ($game_name)"
                echo "Available directories in $common_dir:"
                
                # List all directories in common_dir
                available_dirs=()
                i=1
                while IFS= read -r dir; do
                    available_dirs+=("$dir")
                    echo "$i) $(basename "$dir")"
                    i=$((i+1))
                done < <(find "$common_dir" -maxdepth 1 -type d -not -path "$common_dir" | sort)
                
                if [ ${#available_dirs[@]} -gt 0 ]; then
                    read -p "Enter the number of the correct game directory (or 0 to skip): " dir_sel
                    if [[ "$dir_sel" =~ ^[0-9]+$ ]] && [ "$dir_sel" -gt 0 ] && [ "$dir_sel" -le "${#available_dirs[@]}" ]; then
                        game_dir="${available_dirs[$((dir_sel-1))]}"
                        echo "Selected: $game_dir"
                    else
                        echo "Skipping game directory symlink for $game_id"
                    fi
                else
                    echo "No directories found in $common_dir"
                fi
            fi
            
            if [ -n "$game_dir" ] && [ -d "$game_dir" ]; then
                if [ "$verbose" = true ]; then
                    echo "  Found game directory at: $game_dir"
                fi
                if [ "$dry_run" = true ]; then
                    echo "DRY RUN: ln -sf \"$game_dir\" \"$vortex_dir/pfx/drive_c/Program Files (x86)/Steam/steamapps/common/$(basename "$game_dir")\""
                else
                    # Create Windows-style Steam directory structure in Vortex prefix
                    mkdir -p "$vortex_dir/pfx/drive_c/Program Files (x86)/Steam/steamapps/common"
                    ln -sf "$game_dir" "$vortex_dir/pfx/drive_c/Program Files (x86)/Steam/steamapps/common/$(basename "$game_dir")" || {
                        echo "Failed to symlink game files for $game_id"
                        exit 1
                    }
                    echo "Done!"
                fi
            else
                echo "Skipped (game directory not found in $common_dir)"
                if [ "$verbose" = true ]; then
                    echo "  Tried patterns:"
                    echo "    - Exact: $game_name"
                    echo "    - Case-insensitive: $game_name"
                    echo "    - Alternative: $alt_name"
                    echo "    - Game ID: $game_id"
                    echo "  Common directory contents:"
                    ls -l "$common_dir"
                fi
            fi
        else
            echo "Skipped (common directory not found at $common_dir)"
            if [ "$verbose" = true ]; then
                echo "  Expected path: $common_dir"
            fi
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

# Add custom paths to compatdata search
if [ ${#custom_paths[@]} -gt 0 ]; then
    for path in "${custom_paths[@]}"; do
        DEFAULT_COMPATDATA+=("$path")
    done
fi

echo "Starting Linux Vortex Linker v$VERSION..."
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

# Final instructions
echo
echo "Next steps:"
echo "1. Launch Vortex through Steam"
echo "2. In Vortex, go to Settings > Games"
echo "3. Add your games and set their paths to:"
echo "   C:\\Program Files (x86)\\Steam\\steamapps\\common\\<GameName>"
echo "4. Enjoy modding on Linux!"
