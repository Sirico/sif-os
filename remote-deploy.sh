#!/usr/bin/env bash
# remote-deploy.sh - Deploy SifOS from GitHub to remote thin clients
# This script pulls the latest configuration from GitHub and deploys it

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/Sirico/sif-os.git"
BRANCH="main"
REMOTE_USER="admin"
REMOTE_HOST=""
HOSTNAME=""
MACHINE_TYPE=""
APPLY_NOW=false
INTERACTIVE=true
CONTROL_PATH=""

usage() {
    echo "Usage: $0 -t <target-ip> [-h <hostname>] [-m <machine-type>] [-u <user>] [-a] [-y]"
    echo "  -t: Target IP address or hostname (required)"
    echo "  -h: Hostname (e.g., dispatch-01, office-pc-1) - prompts if not provided"
    echo "  -m: Machine type - prompts if not provided"
    echo "      Options: thin-client, office, workstation, shop-kiosk, custom"
    echo "  -u: Remote user (default: admin)"
    echo "  -a: Apply immediately (default: test only)"
    echo "  -y: Non-interactive mode (use with -h and -m)"
    echo ""
    echo "Examples:"
    echo "  $0 -t 192.168.0.49                           # Interactive prompts"
    echo "  $0 -t 192.168.0.49 -h dispatch-01 -m thin-client -a"
    echo "  $0 -t 192.168.0.49 -h office-pc-1 -m office"
    exit 1
}

# Parse arguments
while getopts "t:h:m:u:ay" opt; do
    case $opt in
        t) REMOTE_HOST="$OPTARG" ;;
        h) HOSTNAME="$OPTARG" ;;
        m) MACHINE_TYPE="$OPTARG" ;;
        u) REMOTE_USER="$OPTARG" ;;
        a) APPLY_NOW=true ;;
        y) INTERACTIVE=false ;;
        *) usage ;;
    esac
done

if [ -z "$REMOTE_HOST" ]; then
    usage
fi

# Interactive prompts if not provided
if [ "$INTERACTIVE" = true ]; then
    # Prompt for hostname if not provided
    if [ -z "$HOSTNAME" ]; then
        echo -e "${CYAN}Enter hostname for this machine:${NC}"
        echo -e "${YELLOW}Examples: dispatch-01, office-pc-1, warehouse-kiosk${NC}"
        read -p "Hostname: " HOSTNAME
        if [ -z "$HOSTNAME" ]; then
            echo -e "${RED}Hostname is required${NC}"
            exit 1
        fi
    fi
    
    # Prompt for machine type if not provided
    if [ -z "$MACHINE_TYPE" ]; then
        echo ""
        echo -e "${CYAN}Select machine type:${NC}"
        echo "  1) Thin Client (dispatch stations, minimal desktop)"
        echo "  2) Office (full desktop, productivity)"
        echo "  3) Workstation (development, power user)"
        echo "  4) Shop Kiosk (locked down, single purpose)"
        echo "  5) Custom (use default configuration)"
        echo ""
        read -p "Select [1-5]: " choice
        
        case $choice in
            1) MACHINE_TYPE="thin-client" ;;
            2) MACHINE_TYPE="office" ;;
            3) MACHINE_TYPE="workstation" ;;
            4) MACHINE_TYPE="shop-kiosk" ;;
            5) MACHINE_TYPE="custom" ;;
            *) 
                echo -e "${RED}Invalid choice${NC}"
                exit 1
                ;;
        esac
    fi
    
    # Confirm before proceeding
    echo ""
    echo -e "${YELLOW}Configuration:${NC}"
    echo "  Target: $REMOTE_HOST"
    echo "  Hostname: sifos-$HOSTNAME"
    echo "  Type: $MACHINE_TYPE"
    echo "  Mode: $([ "$APPLY_NOW" = true ] && echo "Apply immediately" || echo "Test only")"
    echo ""
    read -p "Continue? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
else
    # Non-interactive mode requires both hostname and machine type
    if [ -z "$HOSTNAME" ] || [ -z "$MACHINE_TYPE" ]; then
        echo -e "${RED}Non-interactive mode requires -h and -m options${NC}"
        usage
    fi
fi

echo -e "${GREEN}SifOS Remote Deployment from GitHub${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Repository: $REPO_URL"
echo "Branch: $BRANCH"
echo "Target: $REMOTE_USER@$REMOTE_HOST"
echo "Hostname: sifos-$HOSTNAME"
echo "Machine Type: $MACHINE_TYPE"
echo "Mode: $([ "$APPLY_NOW" = true ] && echo "Apply immediately" || echo "Test only")"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# SSH multiplexing to avoid repeated password prompts
CONTROL_PATH="/tmp/sifos-ssh-${REMOTE_HOST//[^A-Za-z0-9._-]/_}"
SSH_COMMON_OPTS=( -o ControlMaster=auto -o ControlPersist=600 -o ControlPath="$CONTROL_PATH" )
SSH_CMD=( ssh "${SSH_COMMON_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" )

# Check connectivity
echo -e "${YELLOW}Checking connectivity...${NC}"
if ! ping -c 1 -W 2 "$REMOTE_HOST" &>/dev/null; then
    echo -e "${RED}✗ Cannot reach $REMOTE_HOST${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Host reachable${NC}"

# Start control master to reuse auth
if ! ssh -o ControlPath="$CONTROL_PATH" -O check "$REMOTE_USER@$REMOTE_HOST" 2>/dev/null; then
    ssh "${SSH_COMMON_OPTS[@]}" -fnN "$REMOTE_USER@$REMOTE_HOST"
fi

# Deploy via SSH
echo -e "${YELLOW}Deploying configuration from GitHub...${NC}"

"${SSH_CMD[@]}" -o ServerAliveInterval=60 bash << EOF
    set -e
    
    echo "Cloning/updating repository..."
    
    # Clone or update the repository
    if [ -d /tmp/sifos-deploy/.git ]; then
        cd /tmp/sifos-deploy
        git fetch origin
        git reset --hard origin/$BRANCH
        echo "✓ Repository updated"
    else
        rm -rf /tmp/sifos-deploy
        git clone -b $BRANCH $REPO_URL /tmp/sifos-deploy
        echo "✓ Repository cloned"
    fi
    
    cd /tmp/sifos-deploy
    
    # Update hostname and machine type in machine-config.nix
    sed -i 's/networking.hostName = ".*"/networking.hostName = "sifos-$HOSTNAME"/' machine-config.nix
    sed -i "s|# Current: .* (set .*)|# Current: $MACHINE_TYPE (set $(date +%Y-%m-%d))|" machine-config.nix
    
    # Update machine-type import based on selection
    case "$MACHINE_TYPE" in
        thin-client)
            sed -i 's|./machine-types/.*\.nix|./machine-types/thin-client.nix|' machine-config.nix
            ;;
        office)
            sed -i 's|./machine-types/.*\.nix|./machine-types/office.nix|' machine-config.nix
            ;;
        workstation)
            sed -i 's|./machine-types/.*\.nix|./machine-types/workstation.nix|' machine-config.nix
            ;;
        shop-kiosk)
            sed -i 's|./machine-types/.*\.nix|./machine-types/shop-kiosk.nix|' machine-config.nix
            ;;
        custom)
            # For custom, comment out the import line
            sed -i 's|.*./machine-types/.*\.nix|    # ./machine-types/thin-client.nix|' machine-config.nix
            ;;
    esac
    
    # Backup existing configuration
    sudo cp -r /etc/nixos /etc/nixos.backup.\$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
    
    # Copy new configuration (preserve existing hardware-configuration.nix)
    echo "Copying configuration to /etc/nixos..."
    sudo mkdir -p /etc/nixos/modules /etc/nixos/machines /etc/nixos/machine-types /etc/nixos/branding /etc/nixos/remmina-profiles /etc/sifos/remmina-profiles /etc/sifos/branding
    sudo cp configuration.nix machine-config.nix self-update.sh /etc/nixos/
    sudo cp -r modules/* /etc/nixos/modules/
    sudo cp -r machines/* /etc/nixos/machines/ 2>/dev/null || true
    sudo cp -r machine-types/* /etc/nixos/machine-types/ 2>/dev/null || true
    sudo cp -r branding/* /etc/nixos/branding/ 2>/dev/null || true
    sudo cp -r branding/* /etc/sifos/branding/ 2>/dev/null || true
    sudo cp -r remmina-profiles/* /etc/nixos/remmina-profiles/ 2>/dev/null || true
    sudo cp -r remmina-profiles/* /etc/sifos/remmina-profiles/ 2>/dev/null || true
    if [ -d nixos ]; then
        sudo cp -r nixos /etc/nixos/
    fi
    
    # Keep the existing hardware configuration
    echo "Refreshing hardware configuration..."
    sudo nixos-generate-config --dir /tmp/hw-config
    sudo mkdir -p /etc/nixos/nixos
    sudo cp /tmp/hw-config/hardware-configuration.nix /etc/nixos/nixos/
    sudo cp /tmp/hw-config/hardware-configuration.nix /etc/nixos/
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Configuration deployed successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "$APPLY_NOW" = "true" ]; then
        echo "Applying configuration..."
        sudo nixos-rebuild switch --no-flake
        echo ""
        echo "✓ Configuration applied!"
        echo ""
        echo "Next steps:"
        echo "  - Connect to Tailscale: sudo tailscale up"
        echo "  - Reboot if needed: sudo reboot"
    else
        echo "Testing configuration..."
        sudo nixos-rebuild test --no-flake
        echo ""
        echo "✓ Configuration test successful!"
        echo ""
        echo "To apply permanently, run:"
        echo "  sudo nixos-rebuild switch --no-flake"
        echo ""
        echo "Or re-run this script with -a flag"
    fi
EOF

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Close control master
ssh -o ControlPath="$CONTROL_PATH" -O exit "$REMOTE_USER@$REMOTE_HOST" 2>/dev/null || true
