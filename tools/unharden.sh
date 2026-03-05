#!/bin/bash
# Unhardening script for OpenClaw-based agents
# Reverts changes made by the hardening script
# Must be run as root.

set -e  # Exit on any error

# ---------------------------
# Configuration variables (must match hardening script)
# ---------------------------
SSH_PORT="22"
OPENCLAW_CONFIG_PATHS=(
    "/etc/openclaw/openclaw.json"
    "/opt/openclaw/config.json"
    "/usr/local/openclaw/config.json"
    "$HOME/.openclaw/config.json"
)
OPENCLAW_SERVICE_NAME="openclaw"
GATEWAY_PORT="18789"

# Note: Whitelist ports and private network settings don't need to be 
# specified here as we're resetting everything to default

# ---------------------------
# Helper functions
# ---------------------------
die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
info() { echo "INFO: $*"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root."
fi

# Function to find and restore from backups
find_and_restore_backup() {
    local file="$1"
    local backup_pattern="$2"
    
    # Look for backups with various patterns
    local backup_file=""
    
    # Try explicit pattern first
    if [[ -n "$backup_pattern" ]]; then
        backup_file=$(ls -t "$file.$backup_pattern"* 2>/dev/null | head -1)
    fi
    
    # Try common backup patterns
    if [[ -z "$backup_file" ]]; then
        for pattern in "bak" "backup" "old" "orig"; do
            backup_file=$(ls -t "$file.$pattern."* 2>/dev/null | head -1)
            [[ -n "$backup_file" ]] && break
        done
    fi
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$file"
        info "Restored $file from $backup_file"
        return 0
    else
        return 1
    fi
}

# Function to check if we're in a cloud environment
detect_cloud_environment() {
    # Check for AWS
    if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        echo "AWS"
        return 0
    fi
    
    # Check for GCP
    if curl -s --max-time 2 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/ &>/dev/null; then
        echo "GCP"
        return 0
    fi
    
    # Check for Azure
    if curl -s --max-time 2 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2017-08-01 &>/dev/null; then
        echo "Azure"
        return 0
    fi
    
    echo "unknown"
    return 1
}

# ---------------------------
# Warning
# ---------------------------
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    AIP Unhardening Warning                                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ This script will REVERT all security hardening changes:                      ║
║   • Restore original SSH configuration                                       ║
║   • Reset firewall to allow ALL connections (WIDE OPEN)                      ║
║   • Remove ALL firewall rules including:                                     ║
║       - SSH port $SSH_PORT (will be open anyway after reset)                     ║
║       - OpenClaw gateway port $GATEWAY_PORT (if it was opened)                   ║
║       - ANY whitelisted ports that were opened                                ║
║       - Private network rules (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)    ║
║       - Cloud metadata access rules (169.254.169.254)                        ║
║   • Remove kernel hardening settings                                          ║
║   • Restore OpenClaw configuration from backup (if available)                ║
║   • Reset file permissions to default                                        ║
║                                                                              ║
║ ⚠️  WARNING: This will make your system LESS SECURE!                         ║
║   • All firewall protection will be REMOVED                                  ║
║   • Password SSH authentication may be re-enabled                            ║
║   • Root login via SSH may be re-enabled                                     ║
║   • Private networks will no longer have special protection                  ║
║   • Cloud metadata access rules will be removed                              ║
║   • Your system will return to its original insecure state                   ║
║                                                                              ║
║   Only run this if you're experiencing issues and need to revert.            ║
║   Consider fixing the specific issue instead of full unhardening.            ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

# Detect cloud environment for additional warning
CLOUD_ENV=$(detect_cloud_environment)
if [[ "$CLOUD_ENV" != "unknown" ]]; then
    echo ""
    echo "⚠️  DETECTED CLOUD ENVIRONMENT: $CLOUD_ENV"
    echo "   Unhardening will remove metadata access rules (169.254.169.254)"
    echo "   This may affect cloud-init, instance metadata, and other cloud services."
    echo "   Consider if you really need to run this in a cloud environment."
fi

echo ""
read -p "Are you SURE you want to unhardening? (yes/no): " -r CONTINUE
if [[ ! "$CONTINUE" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Exiting as requested."
    exit 0
fi
echo ""

# ---------------------------
# 1. Restore SSH configuration
# ---------------------------
info "=== Restoring SSH Configuration ==="
SSHD_CONFIG="/etc/ssh/sshd_config"

if [[ -f "$SSHD_CONFIG" ]]; then
    if find_and_restore_backup "$SSHD_CONFIG" "bak"; then
        info "SSH configuration restored from backup."
    else
        warn "No SSH backup found. Attempting to restore to distribution defaults..."
        
        # Create backup of current state first
        cp "$SSHD_CONFIG" "$SSHD_CONFIG.unhardened.$(date +%Y%m%d-%H%M%S)"
        
        # Distribution-specific restoration
        if command -v dpkg >/dev/null; then
            # Debian/Ubuntu
            if [[ -f "/etc/ssh/sshd_config.dpkg-dist" ]]; then
                cp "/etc/ssh/sshd_config.dpkg-dist" "$SSHD_CONFIG"
                info "Restored from dpkg-dist default."
            else
                dpkg-reconfigure openssh-server 2>/dev/null || warn "Could not reconfigure SSH"
            fi
        elif command -v rpm >/dev/null; then
            # RHEL/CentOS
            if [[ -f "/etc/ssh/sshd_config.rpmnew" ]]; then
                cp "/etc/ssh/sshd_config.rpmnew" "$SSHD_CONFIG"
                info "Restored from rpmnew default."
            elif command -v yum >/dev/null; then
                yum reinstall -y openssh-server 2>/dev/null || warn "Could not reinstall SSH"
            fi
        else
            # Manual restoration - comment out our hardening changes
            sed -i 's/^PermitRootLogin no/#PermitRootLogin no/' "$SSHD_CONFIG"
            sed -i 's/^PasswordAuthentication no/#PasswordAuthentication no/' "$SSHD_CONFIG"
            sed -i 's/^PubkeyAuthentication yes/#PubkeyAuthentication yes/' "$SSHD_CONFIG"
            sed -i 's/^X11Forwarding no/#X11Forwarding no/' "$SSHD_CONFIG"
            info "Commented out hardening changes in SSH config."
        fi
    fi

    # Restart SSH
    info "Restarting SSH service..."
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service sshd restart 2>/dev/null || service ssh restart 2>/dev/null; then
        info "SSH service restarted."
    else
        warn "Could not restart SSH – please do so manually."
    fi
else
    warn "SSH configuration file not found."
fi

# ---------------------------
# 2. Reset firewall (allow everything)
# ---------------------------
info "=== Resetting Firewall ==="
if command -v iptables >/dev/null; then
    info "Current firewall rules before reset:"
    iptables -L -n | while read line; do
        info "  $line"
    done
    
    echo ""
    info "Resetting firewall to ACCEPT all traffic..."
    
    # Save a backup of current rules just in case
    iptables-save > /root/iptables.rules.before_unharden.$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
    info "Backed up current rules to /root/iptables.rules.before_unharden.*"
    
    # Set default policies to ACCEPT
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # Flush all rules and delete all chains
    iptables -F
    iptables -X
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -t mangle -X 2>/dev/null || true
    
    # Also reset ip6tables if available
    if command -v ip6tables >/dev/null; then
        ip6tables -P INPUT ACCEPT 2>/dev/null || true
        ip6tables -P FORWARD ACCEPT 2>/dev/null || true
        ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
        ip6tables -F 2>/dev/null || true
        ip6tables -X 2>/dev/null || true
    fi
    
    info "Firewall reset to ACCEPT all (INSECURE!)."
    
    # Show new rules
    info "New firewall rules (should be empty/default):"
    iptables -L -n | while read line; do
        info "  $line"
    done
    
    # Try to remove saved rules
    info "Removing persistent firewall rules..."
    rm -f /etc/iptables/rules.v4 2>/dev/null
    rm -f /etc/iptables/rules.v6 2>/dev/null
    rm -f /etc/sysconfig/iptables 2>/dev/null
    rm -f /etc/sysconfig/ip6tables 2>/dev/null
    rm -f /root/iptables.rules.backup 2>/dev/null
    
    # Check for and disable firewall services that might restore rules
    if systemctl list-units --full -all 2>/dev/null | grep -q "iptables.service"; then
        systemctl stop iptables 2>/dev/null || true
        systemctl disable iptables 2>/dev/null || true
        info "Disabled iptables service."
    fi
    
    if systemctl list-units --full -all 2>/dev/null | grep -q "netfilter-persistent.service"; then
        systemctl stop netfilter-persistent 2>/dev/null || true
        systemctl disable netfilter-persistent 2>/dev/null || true
        info "Disabled netfilter-persistent service."
    fi
    
    info "Firewall reset complete."
else
    warn "iptables not found – skipping firewall reset."
fi

# ---------------------------
# 3. Remove kernel hardening
# ---------------------------
info "=== Removing Kernel Hardening ==="
if [[ -f "/etc/sysctl.d/99-hardening.conf" ]]; then
    # Show what settings were applied
    info "Kernel settings that were applied:"
    grep -v "^#" /etc/sysctl.d/99-hardening.conf | grep -v "^$" | while read line; do
        info "  $line"
    done
    
    # Backup the file before removing
    mv "/etc/sysctl.d/99-hardening.conf" "/etc/sysctl.d/99-hardening.conf.unhardened.$(date +%Y%m%d-%H%M%S)"
    info "Removed kernel hardening config (backup created at /etc/sysctl.d/99-hardening.conf.unhardened.*)."
    
    # Reload sysctl defaults (skip errors)
    info "Reloading sysctl settings to defaults..."
    if command -v systemctl >/dev/null && systemctl list-units --full -all 2>/dev/null | grep -q "systemd-sysctl.service"; then
        systemctl restart systemd-sysctl 2>/dev/null || true
    else
        sysctl --system 2>/dev/null || sysctl -p 2>/dev/null || true
    fi
    info "Reloaded sysctl settings."
else
    info "No kernel hardening file found."
fi

# ---------------------------
# 4. Restore OpenClaw configuration
# ---------------------------
info "=== Restoring OpenClaw Configuration ==="

# Find OpenClaw config
CONFIG_FILE=""
for path in "${OPENCLAW_CONFIG_PATHS[@]}"; do
    if [[ -f "$path" ]]; then
        CONFIG_FILE="$path"
        break
    fi
done

if [[ -n "$CONFIG_FILE" ]]; then
    info "Found OpenClaw config at: $CONFIG_FILE"
    
    # Try to restore from backup
    if find_and_restore_backup "$CONFIG_FILE" "bak"; then
        info "OpenClaw configuration restored from backup."
    else
        warn "No OpenClaw backup found. Reverting specific changes..."
        
        # Create a backup of current state
        cp "$CONFIG_FILE" "$CONFIG_FILE.unhardened.$(date +%Y%m%d-%H%M%S)"
        
        # Revert specific OpenClaw settings if they exist
        # (These are the opposite of what the hardening script sets)
        
        # Gateway binding - set back to default (usually 0.0.0.0 or remove)
        if grep -q '"gateway.bind".*"loopback"' "$CONFIG_FILE" 2>/dev/null; then
            sed -i 's/"gateway.bind"[[:space:]]*:[[:space:]]*"loopback"/"gateway.bind": "0.0.0.0"/' "$CONFIG_FILE" 2>/dev/null
            info "Reverted gateway.bind to 0.0.0.0"
        fi
        
        # DM policy - set back to default (often "open" or remove)
        if grep -q '"dmPolicy".*"pairing"' "$CONFIG_FILE" 2>/dev/null; then
            sed -i 's/"dmPolicy"[[:space:]]*:[[:space:]]*"pairing"/"dmPolicy": "open"/' "$CONFIG_FILE" 2>/dev/null
            info "Reverted dmPolicy to open"
        fi
        
        # Log level - set back to default (often "debug" or remove)
        if grep -q '"logLevel".*"info"' "$CONFIG_FILE" 2>/dev/null; then
            sed -i 's/"logLevel"[[:space:]]*:[[:space:]]*"info"/"logLevel": "debug"/' "$CONFIG_FILE" 2>/dev/null
            info "Reverted logLevel to debug"
        fi
        
        # HTTP admin - set back to true if it was disabled
        if grep -q '"enable_http_admin".*false' "$CONFIG_FILE" 2>/dev/null; then
            sed -i 's/"enable_http_admin"[[:space:]]*:[[:space:]]*false/"enable_http_admin": true/' "$CONFIG_FILE" 2>/dev/null
            info "Reverted enable_http_admin to true"
        fi
    fi
    
    # Reset permissions to something more permissive (but still reasonable)
    info "Resetting file permissions..."
    CONFIG_DIR="$(dirname "$CONFIG_FILE")"
    if [[ -d "$CONFIG_DIR" ]]; then
        # Set directory to 755 (rwxr-xr-x)
        chmod 755 "$CONFIG_DIR" 2>/dev/null || warn "Could not reset directory permissions"
        
        # Set files to 644 (rw-r--r--)
        find "$CONFIG_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || warn "Could not reset file permissions"
        
        # If there's a dedicated user, keep ownership but make sure it's accessible
        if [[ -n "$OPENCLAW_USER" ]] && id "$OPENCLAW_USER" &>/dev/null; then
            chown -R "$OPENCLAW_USER":"$OPENCLAW_USER" "$CONFIG_DIR" 2>/dev/null || warn "Could not update ownership"
        fi
        
        info "Reset permissions on $CONFIG_DIR"
    fi
else
    warn "OpenClaw configuration not found in searched paths:"
    for path in "${OPENCLAW_CONFIG_PATHS[@]}"; do
        warn "  - $path"
    done
fi

# ---------------------------
# 5. Restart OpenClaw
# ---------------------------
info "=== Restarting OpenClaw Service ==="

# Function to check if OpenClaw is running
check_openclaw_running() {
    pgrep -f "openclaw" >/dev/null && return 0 || return 1
}

# Stop OpenClaw first
info "Stopping OpenClaw service..."
if systemctl list-units --full -all 2>/dev/null | grep -q "$OPENCLAW_SERVICE_NAME.service"; then
    systemctl stop "$OPENCLAW_SERVICE_NAME" 2>/dev/null && info "Service stopped (systemd)." || warn "Failed to stop via systemd"
elif command -v service >/dev/null && service --status-all 2>/dev/null | grep -q "$OPENCLAW_SERVICE_NAME"; then
    service "$OPENCLAW_SERVICE_NAME" stop 2>/dev/null && info "Service stopped (init.d)." || warn "Failed to stop via service"
else
    pkill -f "openclaw" 2>/dev/null && info "Killed OpenClaw processes." || true
fi

# Wait a moment
sleep 2

# Start OpenClaw
info "Starting OpenClaw service..."
if systemctl list-units --full -all 2>/dev/null | grep -q "$OPENCLAW_SERVICE_NAME.service"; then
    systemctl start "$OPENCLAW_SERVICE_NAME" 2>/dev/null && info "Service started (systemd)." || warn "Failed to start via systemd"
elif command -v service >/dev/null && service --status-all 2>/dev/null | grep -q "$OPENCLAW_SERVICE_NAME"; then
    service "$OPENCLAW_SERVICE_NAME" start 2>/dev/null && info "Service started (init.d)." || warn "Failed to start via service"
else
    warn "Please start OpenClaw manually."
fi

# Check if it's running
sleep 2
if check_openclaw_running; then
    info "✓ OpenClaw is now running."
else
    warn "✗ OpenClaw does not appear to be running. Please check manually."
fi

# ---------------------------
# 6. Final Status and Checks
# ---------------------------
info "=== Unhardening Complete ==="
info "Your system is now in a LESS SECURE state."
info ""
info "╔══════════════════════════════════════════════════════════════════════════╗"
info "║                           CHANGES MADE                                   ║"
info "╠══════════════════════════════════════════════════════════════════════════╣"
info "║  ✓ SSH configuration restored (password auth may be re-enabled)         ║"
info "║  ✓ Firewall reset to allow ALL traffic (ALL ports open)                 ║"
info "║  ✓ Private network rules REMOVED (10.0.0.0/8, etc.)                     ║"
info "║  ✓ Cloud metadata access rules REMOVED (169.254.169.254)                ║"
info "║  ✓ Kernel hardening removed                                             ║"
info "║  ✓ OpenClaw config restored (if backup found)                           ║"
info "║  ✓ OpenClaw service restarted                                           ║"
info "╚══════════════════════════════════════════════════════════════════════════╝"
info ""
info "=== Current System Status ==="

# Show open ports
info "Currently listening ports (ALL should be open now):"
if command -v ss >/dev/null; then
    ss -tulpn 2>/dev/null | head -20 || warn "Could not list open ports"
elif command -v netstat >/dev/null; then
    netstat -tulpn 2>/dev/null | head -20 || warn "Could not list open ports"
else
    warn "Neither ss nor netstat found - cannot list open ports"
fi

# Show SSH status
info ""
info "SSH authentication methods (should show password may be enabled):"
if [[ -f "$SSHD_CONFIG" ]]; then
    grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" "$SSHD_CONFIG" || echo "  (Settings not found)"
fi

# Show firewall status
info ""
info "Firewall status (should be ACCEPT all):"
if command -v iptables >/dev/null; then
    iptables -L -n | head -10 || true
else
    warn "iptables not installed"
fi

# Show cloud environment reminder if applicable
if [[ "$CLOUD_ENV" != "unknown" ]]; then
    info ""
    info "⚠️  CLOUD ENVIRONMENT REMINDER:"
    info "   You are running in $CLOUD_ENV and have removed metadata access rules."
    info "   If cloud-init or metadata services stop working, you may need to:"
    info "   • Reboot the instance (metadata services should recover)"
    info "   • Or manually add back metadata access:"
    info "     iptables -A INPUT -s 169.254.169.254 -j ACCEPT"
fi

# Show OpenClaw status
info ""
info "OpenClaw status:"
if check_openclaw_running; then
    info "  ✓ OpenClaw is running"
    ps aux | grep -v grep | grep "openclaw" || true
else
    warn "  ✗ OpenClaw is not running"
fi

info ""
info "=== Next Steps ==="
info "1. Verify that all your services are working correctly"
info "2. Check that you can still access OpenClaw through your channels"
info "3. If you need to re-harden your system, run the original hardening script again"
info "4. Consider creating a new backup of your configuration"
info ""
info "To check specific ports:"
info "  • View all open ports: ss -tulpn | grep LISTEN"
info "  • Test specific port: nc -zv localhost <port>"
info "  • Test from remote: telnet <server-ip> <port>"
info ""
info "If you experience issues:"
info "  • Check OpenClaw logs: journalctl -u $OPENCLAW_SERVICE_NAME -f"
info "  • Check system logs: tail -f /var/log/syslog"
info "  • Verify OpenClaw config: openclaw config validate"

# Save a summary for reference
SUMMARY_FILE="/root/openclaw-unharden-summary-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "AIP Unhardening Summary - $(date)"
    echo "========================================"
    echo "Cloud Environment: $CLOUD_ENV"
    echo ""
    echo "Changes Made:"
    echo "  - SSH configuration restored"
    echo "  - Firewall reset to ACCEPT ALL"
    echo "  - Private network rules removed"
    echo "  - Cloud metadata rules removed"
    echo "  - Kernel hardening removed"
    echo "  - OpenClaw config restored"
    echo ""
    echo "Open ports after unhardening:"
    ss -tulpn 2>/dev/null | grep LISTEN || echo "None"
} > "$SUMMARY_FILE"
info "Summary saved to: $SUMMARY_FILE"

exit 0
