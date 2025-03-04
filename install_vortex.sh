#!/bin/bash

# Configuration
VORTEX_INSTALLER_URL="https://github.com/Nexus-Mods/Vortex/releases/download/v1.13.7/vortex-setup-1.13.7.exe"
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

    # Check for Steam
    if [ ! -d "$STEAM_DIR" ]; then
        echo "Error: Steam installation not found at $STEAM_DIR"
        echo "Please specify the correct Steam path with -s option"
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
    installer_path="$HOME/Downloads/vortex-setup-1.13.7.exe"
    
    if curl -L -o "$installer_path" "$VORTEX_INSTALLER_URL"; then
        echo "Downloaded Vortex installer to $installer_path"
    else
        echo "Error: Failed to download Vortex installer"
        exit 1
    fi
}

# Function to find the latest Proton version
find_proton_version() {
    echo "Finding Proton version..."

    if [ -n "$PROTON_VERSION" ]; then
        echo "Using specified Proton version: $PROTON_VERSION"
        return
    fi

    # Look for Proton installations
    proton_dir="$STEAM_DIR/steamapps/common"

    # First try to find Proton Experimental
    if [ -d "$proton_dir/Proton Experimental" ]; then
        PROTON_VERSION="Proton Experimental"
        echo "Found $PROTON_VERSION"
        return
    fi

    # Otherwise find the latest numbered version
    latest_version=""
    latest_version_num=0

    for dir in "$proton_dir"/Proton*; do
        if [ -d "$dir" ]; then
            version=$(basename "$dir")
            # Extract version number
            if [[ "$version" =~ Proton\ ([0-9]+)\.([0-9]+) ]]; then
                major="${BASH_REMATCH[1]}"
                minor="${BASH_REMATCH[2]}"
                version_num=$((major * 100 + minor))

                if [ "$version_num" -gt "$latest_version_num" ]; then
                    latest_version_num=$version_num
                    latest_version=$version
                fi
            fi
        fi
    done

    if [ -n "$latest_version" ]; then
        PROTON_VERSION="$latest_version"
        echo "Found $PROTON_VERSION"
    else
        echo "Error: No Proton installation found in $proton_dir"
        echo "Please install Proton through Steam or specify a version with -p option"
        exit 1
    fi
}

# Function to setup Proton prefix
setup_proton_prefix() {
    echo "Setting up Proton prefix for Vortex..."

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
    mkdir -p "$vortex_compatdata/pfx/drive_c/Program Files (x86)/Steam/steamapps/common"
    mkdir -p "$vortex_compatdata/pfx/drive_c/users/steamuser/AppData/Roaming"
    mkdir -p "$vortex_compatdata/pfx/drive_c/users/steamuser/Documents"

          # Create a basic Proton configuration
    cat > "$vortex_compatdata/config.vdf" <<EOF
"InstallConfigStore"
{
    "Software"
    {
        "Valve"
        {
            "Steam"
            {
                "CompatToolMapping"
                {
                    "$VORTEX_COMPATDATA_ID"
                    {
                        "name"        "$PROTON_VERSION"
                        "config"      ""
                        "priority"    "250"
                    }
                }
            }
        }
    }
}
EOF
    echo "Proton prefix setup completed."
}

# Function to install Vortex using Proton
install_vortex() {
    echo "Installing Vortex using Proton..."

    # Find Proton executable
    proton_dir="$STEAM_DIR/steamapps/common/$PROTON_VERSION"
    proton_exe="$proton_dir/proton"

    if [ ! -f "$proton_exe" ]; then
        echo "Error: Proton executable not found at $proton_exe"
        exit 1
    fi

    # Set up environment variables for Proton
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_DIR"
    export STEAM_COMPAT_DATA_PATH="$STEAM_COMPATDATA/$VORTEX_COMPATDATA_ID"

    # Run Vortex installer with Proton
    echo "Running installer with Proton (this may take a while)..."
    "$proton_exe" run "$installer_path"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to run Vortex installer with Proton"
        exit 1
    fi

    echo "Vortex installation completed."
}

# Function to configure Vortex in Steam
configure_steam() {
    echo "Configuring Vortex in Steam..."

    # Find Vortex executable
    vortex_exe=$(find "$STEAM_COMPATDATA/$VORTEX_COMPATDATA_ID/pfx" -name "Vortex.exe" -print -quit)

    if [ -z "$vortex_exe" ]; then
        echo "Warning: Could not find Vortex.exe in Proton prefix"
        echo "Installation may have failed or used a non-standard location"
        return 1
    fi

    echo "Vortex executable found at: $vortex_exe"
    echo "Vortex compatdata ID: $VORTEX_COMPATDATA_ID"
    echo "Vortex compatdata path: $STEAM_COMPATDATA/$VORTEX_COMPATDATA_ID"

    return 0
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
STEAM_DIR="$HOME/.local/share/Steam"

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
        -s|--steam)
            STEAM_DIR="$2"
            STEAM_COMPATDATA="$STEAM_DIR/steamapps/compatdata"
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
        -p|--proton)
            PROTON_VERSION="$2"
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

echo "Starting Vortex Installer (Proton Edition)..."
echo "Log file: $LOG_FILE"

check_dependencies
download_vortex
find_proton_version
setup_proton_prefix
install_vortex
configure_steam
create_steam_shortcut
setup_lvlinker

echo "Vortex installation completed successfully!"
echo "You can now add Vortex to Steam and run it through Proton."
echo "After that, use lvlinker.sh to link your games to Vortex."
echo "You can review the complete log at $LOG_FILE"
