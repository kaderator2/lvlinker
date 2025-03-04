#!/bin/bash

# Configuration
VORTEX_INSTALLER_URL="https://github.com/Nexus-Mods/Vortex/releases/download/v1.13.7/vortex-setup-1.13.7.exe"
WINE_PREFIX="$HOME/.vortex_wine"
STEAM_DIR="$HOME/.local/share/Steam"
LOG_FILE="/tmp/vortex_install.log"
VORTEX_DESKTOP_FILE="$HOME/.local/share/applications/vortex.desktop"

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                 Show this help message and exit"
    echo "  -i, --installer PATH       Path to Vortex installer (will download latest if not provided)"
    echo "  -p, --prefix PATH          Custom Wine prefix path (default: $WINE_PREFIX)"
    echo "  -s, --steam PATH           Custom Steam installation path (default: $STEAM_DIR)"
    echo "  -v, --verbose              Show detailed output"
    echo
    echo "Example:"
    echo "  $0 -i ~/Downloads/vortex-setup.exe -p ~/.wine_vortex"
    exit 1
}

# Function to check dependencies
check_dependencies() {
    echo "Checking dependencies..."

    # Check for Steam
    if [ ! -d "$STEAM_DIR" ]; then
        echo "Warning: Steam installation not found at $STEAM_DIR"
        echo "This is not critical but may affect game detection"
    fi

    # Check for Wine
    if ! command -v wine &> /dev/null; then
        echo "Error: Wine is not installed. Please install Wine first."
        echo "You can install it with: sudo pacman -S wine (Arch) or sudo apt install wine (Debian/Ubuntu)"
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

    echo "All critical dependencies are installed."
}

# Function to download Vortex installer
download_vortex() {
    if [ -n "$installer_path" ] && [ -f "$installer_path" ]; then
        echo "Using provided Vortex installer: $installer_path"
        return
    fi
    
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

    # Check if directory already exists
    if [ -d "$WINE_PREFIX" ]; then
        echo "Warning: Wine prefix directory already exists at $WINE_PREFIX"
        read -p "Do you want to overwrite it? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            echo "Aborted. Please specify a different prefix path with -p option"
            exit 1
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
    
    # Initialize the prefix
    wine wineboot --init
    
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
        -s|--steam)
            STEAM_DIR="$2"
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

echo "Starting Vortex Installer (Wine Edition)..."
echo "Log file: $LOG_FILE"

check_dependencies
download_vortex
setup_wine_prefix
install_vortex
create_desktop_shortcut
setup_lvlinker

echo "Vortex installation completed successfully!"
echo "You can now run Vortex using the desktop shortcut or with:"
echo "env WINEPREFIX=\"$WINE_PREFIX\" wine \"$(find "$WINE_PREFIX" -name "Vortex.exe" -print -quit)\""
echo "After that, use lvlinker.sh to link your games to Vortex."
echo "You can review the complete log at $LOG_FILE"
