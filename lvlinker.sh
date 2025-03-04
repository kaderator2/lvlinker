#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help    Show this help message and exit"
    exit 1
}

# Function to fetch Steam game IDs from SteamDB
fetch_steam_game_ids() {
    echo "Fetching Steam game IDs from SteamDB..."
    curl -s https://steamdb.info/apps/ | grep -oP 'data-appid="\K[0-9]+' | sort -u > /tmp/steam_game_ids.txt
    echo "Steam game IDs fetched and saved to /tmp/steam_game_ids.txt"
}

# Function to scan compatdata folder and find game IDs
scan_compatdata() {
    echo "Scanning compatdata folder..."
    compatdata_dir="$HOME/.local/share/Steam/steamapps/compatdata"
    if [ ! -d "$compatdata_dir" ]; then
        echo "compatdata directory not found at $compatdata_dir"
        exit 1
    fi

    game_ids=($(ls "$compatdata_dir"))
    echo "Found the following game IDs in compatdata:"
    for id in "${game_ids[@]}"; do
        if grep -q "^$id$" /tmp/steam_game_ids.txt; then
            echo "$id"
        fi
    done
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
    echo "Please select the games you want to symlink into the Vortex drive:"
    select game_id in "${game_ids[@]}"; do
        if [ -n "$game_id" ]; then
            echo "Selected game ID: $game_id"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

# Function to symlink directories
symlink_directories() {
    vortex_compatdata_dir="$vortex_dir/compatdata"
    game_compatdata_dir="$HOME/.local/share/Steam/steamapps/compatdata/$game_id"

    echo "Symlinking AppData..."
    ln -sf "$vortex_compatdata_dir/pfx/drive_c/users/steamuser/AppData" "$game_compatdata_dir/pfx/drive_c/users/steamuser/AppData"

    echo "Symlinking Documents..."
    ln -sf "$game_compatdata_dir/pfx/drive_c/users/steamuser/Documents" "$vortex_compatdata_dir/pfx/drive_c/users/steamuser/Documents"

    echo "Symlinking completed."
}

# Main script execution
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

fetch_steam_game_ids
scan_compatdata
get_vortex_dir
select_games
symlink_directories

echo "All done! Vortex should now recognize the selected game as being on the same drive."
