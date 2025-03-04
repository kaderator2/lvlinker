#!/bin/bash

# Configuration
VORTEX_INSTALLER_URL="https://github.com/Nexus-Mods/Vortex/releases/latest/download/vortex-setup.exe"
WINE_PREFIX="$HOME/.vortex_wine"
STEAM_COMPATDATA="$HOME/.local/share/Steam/steamapps/compatdata"
VORTEX_COMPATDATA_ID="1000000"  # Default ID for Vortex in compatdata
LOG_FILE="/tmp/vortex_install.log"

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                 Show this help message and exit"
    echo "  -i, --installer PATH       Path to Vortex installer (will download latest if not provided)"
    echo "  -p, --prefix PATH          Custom Wine prefix path (default: $WINE_PREFIX)"
    echo "  -c, --compatdata PATH      Custom Steam compatdata path (default: $STEAM_COMPATDATA)"
    echo "  -id, --compatdata-id ID    Custom ID for Vortex in compatdata (default: $VORTEX_COMPATDATA_ID)"
    echo "  -v, --verbose              Show detailed output"
    echo
    echo "Example:"
    echo "  $0 -i ~/Downloads/vortex-setup.exe -id 2000000"
    exit 1
}

# Function to check dependencies
check_dependencies() {
    echo "Checking dependencies..."
    
    # Check for Wine
    if ! command -v wine &> /dev/null; then
        echo "Error: Wine is not installed. Please install Wine first."
        echo "You can install it with: sudo pacman -S wine (Arch) or sudo apt install wine (Debian/Ubuntu)"
        exit 1
    fi
    
    # Check for winetricks
    if ! command -v winetricks &> /dev/null; then
        echo "Error: Winetricks is not installed. Please install Winetricks first."
        echo "You can install it with: sudo pacman -S winetricks (Arch) or sudo apt install winetricks (Debian/Ubuntu)"
        exit 1
    fi
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        echo "Error: curl is not installed. Please install curl first."
        echo "You can install it with: sudo pacman -S curl (Arch) or sudo apt install curl (Debian/Ubuntu)"
        exit 1
    fi
    
    echo "All dependencies are installed."
}

# Function to download Vortex installer
download_vortex() {
    if [ -n "$installer_path" ] && [ -f "$installer_path" ]; then
        echo "Using provided Vortex installer: $installer_path"
        return
    fi
    
    echo "Downloading latest Vortex installer..."
    installer_path="$HOME/Downloads/vortex-setup.exe"
    
    if curl -L -o "$installer_path" "$VORTEX_INSTALLER_URL"; then
        echo "Downloaded Vortex installer to $installer_path"
    else
        echo "Error: Failed to download Vortex installer"
        exit 1
    fi
}

# Function to setup Wine prefix
setup_wine_prefix() {
    echo "Setting up Wine prefix at $WINE_PREFIX..."
    
    # Create Wine prefix if it doesn't exist
    if [ ! -d "$WINE_PREFIX" ]; then
        mkdir -p "$WINE_PREFIX"
        
        # Initialize Wine prefix
        WINEPREFIX="$WINE_PREFIX" wineboot --init
        if [ $? -ne 0 ]; then
            echo "Error: Failed to initialize Wine prefix"
            exit 1
        fi
    fi
    
    echo "Installing required Windows components..."
    
    # Install required Windows components
    WINEPREFIX="$WINE_PREFIX" winetricks -q dotnet48 corefonts vcrun2019
    if [ $? -ne 0 ]; then
        echo "Warning: Some Windows components may have failed to install"
        echo "You may need to manually install them later"
    fi
    
    echo "Wine prefix setup completed."
}

# Function to install Vortex
install_vortex() {
    echo "Installing Vortex..."
    
    # Run Vortex installer
    WINEPREFIX="$WINE_PREFIX" wine "$installer_path"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to run Vortex installer"
        exit 1
    fi
    
    echo "Vortex installation completed."
}

# Function to move Wine prefix to Steam compatdata
move_to_compatdata() {
    echo "Moving Wine prefix to Steam compatdata..."
    
    # Create compatdata directory if it doesn't exist
    if [ ! -d "$STEAM_COMPATDATA" ]; then
        echo "Error: Steam compatdata directory not found at $STEAM_COMPATDATA"
        echo "Please specify the correct path with -c option"
        exit 1
    fi
    
    # Create Vortex compatdata directory
    vortex_compatdata="$STEAM_COMPATDATA/$VORTEX_COMPATDATA_ID"
    
    # Check if directory already exists
    if [ -d "$vortex_compatdata" ]; then
        echo "Warning: Compatdata directory $VORTEX_COMPATDATA_ID already exists"
        read -p "Do you want to overwrite it? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            echo "Aborted. Please specify a different ID with -id option"
            exit 1
        fi
        
        # Backup existing directory
        backup_dir="$vortex_compatdata.bak.$(date +%Y%m%d%H%M%S)"
        echo "Creating backup of existing directory to $backup_dir"
        mv "$vortex_compatdata" "$backup_dir"
    fi
    
    # Create directory structure
    mkdir -p "$vortex_compatdata/pfx"
    
    # Copy Wine prefix to compatdata
    echo "Copying Wine prefix to compatdata (this may take a while)..."
    cp -r "$WINE_PREFIX/"* "$vortex_compatdata/pfx/"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy Wine prefix to compatdata"
        exit 1
    fi
    
    echo "Wine prefix successfully moved to Steam compatdata."
    echo "Vortex compatdata ID: $VORTEX_COMPATDATA_ID"
    echo "Vortex compatdata path: $vortex_compatdata"
}

# Function to create Steam shortcut
create_steam_shortcut() {
    echo "Creating Steam shortcut for Vortex..."
    
    # Find Vortex executable in Wine prefix
    vortex_exe=$(find "$STEAM_COMPATDATA/$VORTEX_COMPATDATA_ID/pfx" -name "Vortex.exe" -print -quit)
    
    if [ -z "$vortex_exe" ]; then
        echo "Warning: Could not find Vortex.exe in Wine prefix"
        echo "You may need to create the Steam shortcut manually"
        return
    fi
    
    # Create VDF file for Steam shortcut
    shortcut_vdf="$HOME/.steam/steam/userdata/*/config/shortcuts.vdf"
    
    echo "Vortex executable found at: $vortex_exe"
    echo "To add Vortex to Steam:"
    echo "1. Open Steam"
    echo "2. Click on 'Add a Game' in the bottom left corner"
    echo "3. Select 'Add a Non-Steam Game'"
    echo "4. Click 'Browse' and navigate to: $vortex_exe"
    echo "5. Click 'Add Selected Programs'"
    echo "6. Right-click on Vortex in your Steam library"
    echo "7. Select Properties"
    echo "8. In the 'Compatibility' tab, check 'Force the use of a specific Steam Play compatibility tool'"
    echo "9. Select a Proton version (Proton Experimental recommended)"
    
    echo "Steam shortcut instructions provided."
}

# Function to setup lvlinker
setup_lvlinker() {
    echo "Setting up lvlinker for Vortex..."
    
    # Check if lvlinker.sh exists in the current directory
    if [ ! -f "./lvlinker.sh" ]; then
        echo "Warning: lvlinker.sh not found in the current directory"
        echo "Please run lvlinker.sh manually after installation to link your games to Vortex"
        return
    fi
    
    # Make lvlinker.sh executable
    chmod +x ./lvlinker.sh
    
    echo "To link your games to Vortex, run:"
    echo "./lvlinker.sh -v"
    
    echo "lvlinker setup completed."
}

# Main script execution
verbose=false
installer_path=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -i|--installer)
            installer_path="$2"
            shift 2
            ;;
        -p|--prefix)
            WINE_PREFIX="$2"
            shift 2
            ;;
        -c|--compatdata)
            STEAM_COMPATDATA="$2"
            shift 2
            ;;
        -id|--compatdata-id)
            VORTEX_COMPATDATA_ID="$2"
            shift 2
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

echo "Starting Vortex Installer..."
echo "Log file: $LOG_FILE"

check_dependencies
download_vortex
setup_wine_prefix
install_vortex
move_to_compatdata
create_steam_shortcut
setup_lvlinker

echo "Vortex installation completed successfully!"
echo "You can now add Vortex to Steam and run it through Proton."
echo "After that, use lvlinker.sh to link your games to Vortex."
echo "You can review the complete log at $LOG_FILE"
