#!/usr/bin/env bash
# enroll-machine.sh - Enroll a new machine into the SifOS fleet
# This script sets up a fresh NixOS installation with the proper configuration

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/Sirico/sif-os.git"
BRANCH="main"
REMOTE_USER="root"  # Use root for initial setup
TARGET_IP=""
HOSTNAME=""
MACHINE_TYPE=""
TAILSCALE_IP=""
CONTROL_PATH=""

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

usage() {
    cat << EOF
Usage: $0 -t <target-ip> -h <hostname> -m <machine-type> [-s <tailscale-ip>]

Enroll a fresh NixOS machine into the SifOS fleet.

OPTIONS:
    -t IP/HOST      Target IP address of the new machine (required)
    -h HOSTNAME     Hostname for the machine (e.g., thin-client-7) (required)
    -m TYPE         Machine type (required)
                    Options: thin-client, office, workstation, shop-kiosk, server, custom
    -s IP           Tailscale IP address (optional, can be set later)
    -u USER         SSH user for connection (default: root)
    --help          Show this help

EXAMPLES:
    # Basic enrollment
    $0 -t 192.168.0.50 -h thin-client-7 -m thin-client
    
    # With Tailscale IP
    $0 -t 192.168.0.50 -h thin-client-7 -m thin-client -s 100.78.103.62
    
    # Server enrollment
    $0 -t 192.168.0.100 -h sifos-server-1 -m server

PREREQUISITES:
    1. Fresh NixOS installation on target machine
    2. SSH access to the machine (as root)
    3. Network connectivity between this machine and target
    
WHAT THIS SCRIPT DOES:
    1. Validates the target machine is running NixOS
    2. Backs up existing hardware-configuration.nix
    3. Clones SifOS repository to /etc/nixos
    4. Creates machine-config.nix with specified settings
    5. Sets up admin user with sudo access
    6. Installs and configures Tailscale
    7. Applies the configuration
    8. Provides next steps for Tailscale setup

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t) TARGET_IP="$2"; shift 2 ;;
        -h) HOSTNAME="$2"; shift 2 ;;
        -m) MACHINE_TYPE="$2"; shift 2 ;;
        -s) TAILSCALE_IP="$2"; shift 2 ;;
        -u) REMOTE_USER="$2"; shift 2 ;;
        --help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

# Validate required parameters
if [ -z "$TARGET_IP" ] || [ -z "$HOSTNAME" ] || [ -z "$MACHINE_TYPE" ]; then
    log_error "Missing required parameters"
    usage
fi

# SSH multiplexing to avoid repeated password prompts
CONTROL_PATH="/tmp/sifos-ssh-${TARGET_IP//[^A-Za-z0-9._-]/_}"
SSH_COMMON_OPTS=( -o ControlMaster=auto -o ControlPersist=600 -o ControlPath="$CONTROL_PATH" )
SSH_CMD=( ssh "${SSH_COMMON_OPTS[@]}" "$REMOTE_USER@$TARGET_IP" )

# Validate machine type
case "$MACHINE_TYPE" in
    thin-client|office|workstation|shop-kiosk|server|custom)
        ;;
    *)
        log_error "Invalid machine type: $MACHINE_TYPE"
        log_info "Valid types: thin-client, office, workstation, shop-kiosk, server, custom"
        exit 1
        ;;
esac

log_header "SifOS Machine Enrollment"
echo "Target: $REMOTE_USER@$TARGET_IP"
echo "Hostname: sifos-$HOSTNAME"
echo "Type: $MACHINE_TYPE"
if [ -n "$TAILSCALE_IP" ]; then
    echo "Tailscale IP: $TAILSCALE_IP"
fi
echo ""

read -p "Continue with enrollment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log_info "Enrollment cancelled"
    exit 0
fi

# Start control master to reuse auth for subsequent SSH calls
if ! ssh -o ControlPath="$CONTROL_PATH" -O check "$REMOTE_USER@$TARGET_IP" 2>/dev/null; then
    ssh "${SSH_COMMON_OPTS[@]}" -fnN "$REMOTE_USER@$TARGET_IP"
fi

# Step 1: Verify NixOS
log_header "Step 1: Verifying NixOS Installation"
if ! "${SSH_CMD[@]}" "test -f /etc/NIXOS"; then
    log_error "Target machine is not running NixOS"
    ssh -o ControlPath="$CONTROL_PATH" -O exit "$REMOTE_USER@$TARGET_IP" 2>/dev/null || true
    exit 1
fi
log_success "Confirmed NixOS installation"

# Step 2: Check connectivity and get system info
log_header "Step 2: Gathering System Information"
NIXOS_VERSION=$("${SSH_CMD[@]}" "nixos-version" 2>/dev/null || echo "unknown")
log_info "NixOS version: $NIXOS_VERSION"

# Step 3: Backup existing hardware config
log_header "Step 3: Backing Up Hardware Configuration"
"${SSH_CMD[@]}" "
    if [ -f /etc/nixos/hardware-configuration.nix ]; then
        cp /etc/nixos/hardware-configuration.nix /etc/nixos/hardware-configuration.nix.backup
        echo 'Backed up existing hardware-configuration.nix'
    fi
"
log_success "Hardware configuration backed up"

# Step 4: Clone repository
log_header "Step 4: Installing SifOS Configuration"
"${SSH_CMD[@]}" "
    # Remove old configs (keeping hardware config)
    cd /etc/nixos
    find . -maxdepth 1 -type f ! -name 'hardware-configuration.nix*' -delete
    find . -maxdepth 1 -type d ! -name '.' ! -name '..' -exec rm -rf {} + 2>/dev/null || true
    
    # Clone SifOS repository
    git clone $REPO_URL /tmp/sifos-temp
    cd /tmp/sifos-temp
    git checkout $BRANCH
    
    # Copy everything except .git to /etc/nixos
    cp -r * /etc/nixos/
    cp -r .gitignore /etc/nixos/ 2>/dev/null || true
    # Ensure nixos/ directory is present (for hardware-configuration import)
    if [ -d nixos ]; then
        cp -r nixos /etc/nixos/
    fi
    
    # Refresh hardware config from this machine so root FS is defined
    nixos-generate-config --dir /tmp/sifos-hw
    mkdir -p /etc/nixos/nixos
    cp /tmp/sifos-hw/hardware-configuration.nix /etc/nixos/hardware-configuration.nix
    cp /tmp/sifos-hw/hardware-configuration.nix /etc/nixos/nixos/hardware-configuration.nix

    # Cleanup
    rm -rf /tmp/sifos-temp
    
    echo 'SifOS configuration installed'
"
log_success "Repository cloned and installed"

# Step 5: Create machine-config.nix
log_header "Step 5: Creating Machine Configuration"

MACHINE_CONFIG="# Machine-Specific Configuration
# Generated by enroll-machine.sh on $(date +%Y-%m-%d)

{ config, pkgs, lib, ... }:

{
  # Machine hostname
  networking.hostName = \"sifos-$HOSTNAME\";
  
"

if [ -n "$TAILSCALE_IP" ]; then
    MACHINE_CONFIG+="  # Tailscale IP for this machine
  # Update this after running 'tailscale up' if it changes
  sifos.tailscale.advertiseAddress = \"$TAILSCALE_IP\";
  
"
fi

MACHINE_CONFIG+="  # Machine type - determines which features are enabled
  # Type: $MACHINE_TYPE (set $(date +%Y-%m-%d))
  
  # Import machine type configuration
  imports = [
    ./machine-types/$MACHINE_TYPE.nix
  ];
  
  # Optional: Static IP configuration
  # Uncomment and configure if needed
  # networking.interfaces.enp1s0.ipv4.addresses = [{
  #   address = \"192.168.0.100\";
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = \"192.168.0.1\";
  # networking.nameservers = [ \"8.8.8.8\" \"1.1.1.1\" ];
}
"

echo "$MACHINE_CONFIG" | "${SSH_CMD[@]}" "cat > /etc/nixos/machine-config.nix"
log_success "Machine configuration created"

# Step 6: Apply configuration
log_header "Step 6: Applying Configuration"
log_warning "This will rebuild the system. This may take several minutes..."

if "${SSH_CMD[@]}" "nixos-rebuild switch --no-flake"; then
    log_success "Configuration applied successfully"
else
    log_error "Failed to apply configuration"
    log_warning "You can try manually: ssh $REMOTE_USER@$TARGET_IP 'nixos-rebuild switch --no-flake'"
    ssh -o ControlPath="$CONTROL_PATH" -O exit "$REMOTE_USER@$TARGET_IP" 2>/dev/null || true
    exit 1
fi

# Step 7: Set up admin user password
log_header "Step 7: Setting Admin Password"
log_info "The admin user has been created. You should set a password:"
echo ""
echo "  ssh root@$TARGET_IP 'passwd admin'"
echo ""

# Step 8: Tailscale setup
log_header "Step 8: Tailscale Setup"
log_info "To complete Tailscale setup, run on the target machine:"
echo ""
echo "  ssh admin@$TARGET_IP 'sudo tailscale up'"
echo ""
if [ -z "$TAILSCALE_IP" ]; then
    log_info "After Tailscale is connected, update machine-config.nix with the Tailscale IP:"
    echo ""
    echo "  ssh admin@$TARGET_IP 'tailscale status | grep $(hostname)'"
    echo ""
    echo "Then update /etc/nixos/machine-config.nix and add:"
    echo "  sifos.tailscale.advertiseAddress = \"100.x.x.x\";"
fi

# Final summary
log_header "Enrollment Complete!"
log_success "Machine: sifos-$HOSTNAME"
log_success "Type: $MACHINE_TYPE"
log_success "Local IP: $TARGET_IP"

echo ""
log_info "Next Steps:"
echo "  1. Set admin password: ssh root@$TARGET_IP 'passwd admin'"
echo "  2. Connect Tailscale: ssh admin@$TARGET_IP 'sudo tailscale up'"
if [ -z "$TAILSCALE_IP" ]; then
    echo "  3. Update Tailscale IP in /etc/nixos/machine-config.nix"
    echo "  4. Test SSH via Tailscale: ssh admin@sifos-$HOSTNAME"
else
    echo "  3. Test SSH via Tailscale: ssh admin@$TAILSCALE_IP"
fi
echo "  5. Future deployments: ./remote-deploy.sh -t sifos-$HOSTNAME -h $HOSTNAME -m $MACHINE_TYPE -y -a"

echo ""
log_success "Machine enrolled successfully! 🎉"

# Close control master
ssh -o ControlPath="$CONTROL_PATH" -O exit "$REMOTE_USER@$TARGET_IP" 2>/dev/null || true
