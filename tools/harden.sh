#!/bin/bash
# Universal hardening script for SBI agents
# Must be run as root.

set -e  # Exit on any error

# ---------------------------
# Configuration variables (edit as needed)
# ---------------------------
SSH_PORT="22"
OPENCLAW_CONFIG_PATHS=(
    "/etc/openclaw/openclaw.json"
    "/opt/openclaw/config.json"
    "/usr/local/openclaw/config.json"
    "$HOME/.openclaw/config.json"
)
OPENCLAW_SERVICE_NAME="openclaw"          # systemd service name
OPENCLAW_USER="openclaw"                   # dedicated user for OpenClaw (if exists)
ALLOW_REMOTE_GATEWAY="no"                   # Set to "yes" to open firewall for gateway port
GATEWAY_PORT="18789"                         # Default OpenClaw gateway port

# Boolean: set to "yes" to apply OpenClaw-specific configuration hardening
HARDEN_OPENCLAW_CONFIG="no"

# Port whitelisting configuration
DO_WHITELIST_PORTS="no"                    # Set to "true" to whitelist additional ports
WHITELIST_PORTS="8000,9090"                   # Comma-separated list of ports to whitelist
WHITELIST_PROTOCOL="tcp"                       # Protocol: tcp, udp, or "both" (comma-separated also supported)
# You can also specify protocol per port like: "8000:tcp,9090:udp,8080:both"

# Private network preservation
PRESERVE_PRIVATE_NETWORKS="true"              # Set to "true" to preserve private network access
PRIVATE_NETWORKS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16"  # RFC 1918 + link-local
PRESERVE_METADATA="true"                       # Preserve AWS/GCP/Azure metadata access
METADATA_IPS="169.254.169.254,fd00:ec2::254"   # Cloud metadata IPs (AWS, GCP, Azure)

# ---------------------------
# Security Warnings and Prerequisites
# ---------------------------
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    AIPROTOCOL Security Hardening Warning                       ║
                                        License
    This script is provided as-is. Test in a non-production environment first!
╠══════════════════════════════════════════════════════════════════════════════╣
║ WHAT THIS SCRIPT DOES:                                                       ║
║   • Closes ALL incoming ports except SSH (port 22)                          ║
║   • PRESERVES access from localhost and private networks                    ║
║   • PRESERVES cloud metadata endpoints (AWS, GCP, Azure)                    ║
║   • Hardens SSH configuration (disables root login, password auth)          ║
║   • Applies kernel-level security settings                                  ║
║   • Configures OpenClaw for secure operation                                ║
║                                                                                ║
║ ⚠️  CRITICAL WARNINGS:                                                   ║
║   1. Ensure you have SSH access with SSH KEYS before running!                  ║
║      Password authentication will be DISABLED.                                 ║
║                                                                                ║
║   2. Keep your current SSH session OPEN while testing new connections.      ║
║      If you get locked out, use the unhardening script from another         ║
║      session or console access.                                             ║
║                                                                              ║
║   3. PRIVATE NETWORK ACCESS:                                                ║
║      • Localhost (127.0.0.0/8) will remain accessible                       ║
║      • Private IPs (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) preserved   ║
║      • Cloud metadata (169.254.169.254) preserved                           ║
║      • Link-local (169.254.0.0/16) preserved                                ║
║                                                                              ║
EOF

if [[ "$DO_WHITELIST_PORTS" == "true" ]]; then
    echo "║   4. PORT WHITELISTING:"
    echo "║      • Additional ports will be OPENED: $WHITELIST_PORTS"
    echo "║      • Protocol: $WHITELIST_PROTOCOL"
else
    echo "║   4. PORT WHITELISTING:"
    echo "║      • No additional ports will be opened (strict mode)"
fi

cat << "EOF"
║                                                                              ║
║   5. For REMOTE access to OpenClaw after hardening:                         ║
║      • Use SSH tunneling: ssh -L 18789:localhost:18789 user@server        
║      • Or set ALLOW_REMOTE_GATEWAY="yes" in the script                    ║
║                                                                              ║
║   6. BACKUP your OpenClaw configuration and SSH keys before proceeding!     ║
║                                                                              ║
║   7. An UNHARDENING script is available to revert all changes if needed.    ║
║                                                                              ║
║ PREREQUISITES:                                                               ║
║   • Root/sudo access                                                         ║
║   • SSH key-based access already configured                                  ║
║   • OpenClaw installed and configured                                        ║
║   • iptables installed (for firewall)                                        ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

echo ""
read -p "Do you want to continue? (yes/no): " -r CONTINUE
if [[ ! "$CONTINUE" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Exiting as requested."
    exit 0
fi
echo ""

# ---------------------------
# Helper functions
# ---------------------------
die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
info() { echo "INFO: $*"; }

# Function to parse and add whitelisted ports
add_whitelisted_ports() {
    if [[ "$DO_WHITELIST_PORTS" != "true" ]] || [[ -z "$WHITELIST_PORTS" ]]; then
        return 0
    fi
    
    info "Processing whitelisted ports: $WHITELIST_PORTS"
    
    # Split the comma-separated list
    IFS=',' read -ra PORTS_ARRAY <<< "$WHITELIST_PORTS"
    
    for item in "${PORTS_ARRAY[@]}"; do
        # Trim whitespace
        item=$(echo "$item" | xargs)
        
        # Check if item has protocol specified (format: port:protocol)
        if [[ "$item" == *:* ]]; then
            port=$(echo "$item" | cut -d':' -f1 | xargs)
            protocol=$(echo "$item" | cut -d':' -f2 | xargs | tr '[:upper:]' '[:lower:]')
        else
            port="$item"
            protocol="$WHITELIST_PROTOCOL"
        fi
        
        # Validate port number
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
            warn "Invalid port number: $port - skipping"
            continue
        fi
        
        # Add firewall rules based on protocol
        case "$protocol" in
            tcp)
                iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
                info "  ✓ Opened TCP port $port"
                ;;
            udp)
                iptables -A INPUT -p udp --dport "$port" -j ACCEPT
                info "  ✓ Opened UDP port $port"
                ;;
            both)
                iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
                iptables -A INPUT -p udp --dport "$port" -j ACCEPT
                info "  ✓ Opened TCP and UDP port $port"
                ;;
            *)
                warn "Unknown protocol: $protocol for port $port - using TCP"
                iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
                ;;
        esac
    done
}

# Function to add private network preservation rules
add_private_network_rules() {
    if [[ "$PRESERVE_PRIVATE_NETWORKS" != "true" ]]; then
        return 0
    fi
    
    info "Adding private network preservation rules..."
    
    # Split private networks
    IFS=',' read -ra NETWORKS_ARRAY <<< "$PRIVATE_NETWORKS"
    
    for network in "${NETWORKS_ARRAY[@]}"; do
        network=$(echo "$network" | xargs)
        if [[ -n "$network" ]]; then
            # Allow all traffic from private network
            iptables -A INPUT -s "$network" -j ACCEPT
            info "  ✓ Allowed traffic from private network: $network"
        fi
    done
    
    # Add link-local if not already included
    if [[ ! "$PRIVATE_NETWORKS" =~ "169.254.0.0/16" ]]; then
        iptables -A INPUT -s "169.254.0.0/16" -j ACCEPT
        info "  ✓ Allowed traffic from link-local: 169.254.0.0/16"
    fi
}

# Function to add cloud metadata preservation rules
add_metadata_rules() {
    if [[ "$PRESERVE_METADATA" != "true" ]]; then
        return 0
    fi
    
    info "Adding cloud metadata preservation rules..."
    
    # Split metadata IPs
    IFS=',' read -ra METADATA_ARRAY <<< "$METADATA_IPS"
    
    for ip in "${METADATA_ARRAY[@]}"; do
        ip=$(echo "$ip" | xargs)
        if [[ -n "$ip" ]]; then
            # Check if IPv6
            if [[ "$ip" == *:* ]]; then
                # IPv6 metadata
                ip6tables -A INPUT -s "$ip" -j ACCEPT 2>/dev/null && \
                info "  ✓ Allowed IPv6 metadata access from: $ip" || \
                warn "Could not add IPv6 rule for $ip (ip6tables may not be available)"
            else
                # IPv4 metadata
                iptables -A INPUT -s "$ip" -j ACCEPT
                info "  ✓ Allowed metadata access from: $ip"
            fi
        fi
    done
    
    # Also allow outbound metadata access (important for cloud instances)
    for ip in "${METADATA_ARRAY[@]}"; do
        ip=$(echo "$ip" | xargs)
        if [[ -n "$ip" ]]; then
            if [[ "$ip" == *:* ]]; then
                ip6tables -A OUTPUT -d "$ip" -j ACCEPT 2>/dev/null
            else
                iptables -A OUTPUT -d "$ip" -j ACCEPT
            fi
        fi
    done
    info "  ✓ Allowed outbound metadata access"
}

# Function to safely apply sysctl settings
apply_sysctl() {
    local key="$1"
    local value="$2"
    local description="$3"
    
    # Check if the key exists in sysctl
    if sysctl -n "$key" &>/dev/null; then
        # Apply the setting
        echo "$key = $value" >> /etc/sysctl.d/99-hardening.conf
        sysctl -w "$key=$value" &>/dev/null && info "Set $key = $value ($description)"
    else
        warn "Sysctl key '$key' not found - skipping ($description)"
    fi
}

# Function to save iptables rules in a distribution-agnostic way
save_iptables_rules() {
    info "Attempting to save iptables rules..."
    
    # Try different methods based on what's available
    if command -v iptables-save >/dev/null; then
        # Try Debian/Ubuntu style
        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null && {
                info "Rules saved to /etc/iptables/rules.v4"
                
                # Also save ip6tables if available
                if command -v ip6tables-save >/dev/null && [ -f "/etc/iptables/rules.v6" ]; then
                    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
                    info "IPv6 rules saved to /etc/iptables/rules.v6"
                fi
                return 0
            }
        fi
        
        # Try RHEL/CentOS style
        if [ -d "/etc/sysconfig" ]; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null && {
                info "Rules saved to /etc/sysconfig/iptables"
                
                # Also save ip6tables if available
                if command -v ip6tables-save >/dev/null; then
                    ip6tables-save > /etc/sysconfig/ip6tables 2>/dev/null
                    info "IPv6 rules saved to /etc/sysconfig/ip6tables"
                fi
                return 0
            }
        fi
        
        # Try to save to a common location and provide instructions
        iptables-save > /root/iptables.rules.backup 2>/dev/null && {
            warn "Could not save to standard location. Rules backed up to /root/iptables.rules.backup"
            warn "To make rules persistent, manually run: iptables-save > /etc/iptables/rules.v4 (Debian/Ubuntu)"
            warn "or: iptables-save > /etc/sysconfig/iptables (RHEL/CentOS)"
            return 0
        }
    else
        warn "iptables-save not found. Cannot persist firewall rules."
        warn "You may need to install iptables-persistent or manually configure persistence."
    fi
    
    # Try using service iptables save for older systems
    if command -v service >/dev/null && service iptables save 2>/dev/null; then
        info "Rules saved using 'service iptables save'"
        return 0
    fi
    
    return 1
}

# Check root
if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root."
fi

# ---------------------------
# 1. System Hardening
# ---------------------------
info "=== System Hardening ==="

# 1.1 Firewall: close all ports except SSH (and optionally gateway + whitelist)
info "Configuring firewall (iptables)..."

# Check if iptables is available
if ! command -v iptables >/dev/null; then
    warn "iptables command not found. Skipping firewall configuration."
else
    # Flush existing rules and set default policies
    iptables -F
    iptables -X
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Allow established/related connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow loopback (localhost)
    iptables -A INPUT -i lo -j ACCEPT
    info "Loopback (localhost) access preserved."

    # Add private network preservation rules
    add_private_network_rules
    
    # Add cloud metadata preservation rules
    add_metadata_rules

    # Allow SSH
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    info "SSH port $SSH_PORT opened."

    # Optionally allow OpenClaw gateway port for remote access
    if [[ "$ALLOW_REMOTE_GATEWAY" == "yes" ]]; then
        iptables -A INPUT -p tcp --dport "$GATEWAY_PORT" -j ACCEPT
        info "Gateway port $GATEWAY_PORT opened (remote access enabled)."
    else
        info "Gateway port remains closed (only localhost access)."
    fi

    # Add whitelisted ports
    add_whitelisted_ports

    # Show final rules
    info "Current firewall rules:"
    iptables -L -n | while read line; do
        info "  $line"
    done

    # Save rules using our function
    save_iptables_rules || warn "Firewall rules may not persist after reboot."
fi

# 1.2 SSH Hardening
info "Hardening SSH configuration..."
if [ ! -f "/etc/ssh/sshd_config" ]; then
    warn "SSH configuration file not found. Skipping SSH hardening."
else
    SSHD_CONFIG="/etc/ssh/sshd_config"
    cp "$SSHD_CONFIG" "$SSHD_CONFIG.bak.$(date +%Y%m%d-%H%M%S)"

    # Use sed to set/uncomment options
    sed -i 's/^#PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CONFIG"
    sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CONFIG"

    sed -i 's/^#PasswordAuthentication .*/PasswordAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' "$SSHD_CONFIG"

    sed -i 's/^#PubkeyAuthentication .*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^PubkeyAuthentication .*/PubkeyAuthentication yes/' "$SSHD_CONFIG"

    sed -i 's/^#AuthorizedKeysFile .*/AuthorizedKeysFile .ssh\/authorized_keys/' "$SSHD_CONFIG"
    sed -i 's/^AuthorizedKeysFile .*/AuthorizedKeysFile .ssh\/authorized_keys/' "$SSHD_CONFIG"

    sed -i 's/^#X11Forwarding .*/X11Forwarding no/' "$SSHD_CONFIG"
    sed -i 's/^X11Forwarding .*/X11Forwarding no/' "$SSHD_CONFIG"

    # Restart SSH
    if systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null || service ssh restart 2>/dev/null; then
        info "SSH service restarted."
    else
        warn "Could not restart SSH – please do so manually."
    fi
fi

# 1.3 Basic OS hardening with safe sysctl settings
info "Applying basic OS hardening..."

# Create sysctl config file
SYSCTL_CONF="/etc/sysctl.d/99-hardening.conf"
echo "# Kernel hardening settings - added by OpenClaw hardening script" > "$SYSCTL_CONF"
echo "# Date: $(date)" >> "$SYSCTL_CONF"
echo "" >> "$SYSCTL_CONF"

# Apply each setting safely
apply_sysctl "net.ipv4.tcp_syncookies" "1" "Enable TCP syncookies (protection against SYN flood)"
apply_sysctl "net.ipv4.icmp_echo_ignore_broadcasts" "1" "Ignore ICMP echo broadcasts"
apply_sysctl "net.ipv4.icmp_ignore_bogus_error_responses" "1" "Ignore bogus ICMP errors"
apply_sysctl "net.ipv4.conf.all.rp_filter" "1" "Enable reverse path filtering"
apply_sysctl "net.ipv4.conf.default.rp_filter" "1" "Enable reverse path filtering (default)"
apply_sysctl "net.ipv4.conf.all.accept_source_route" "0" "Disable source routing"
apply_sysctl "net.ipv4.conf.default.accept_source_route" "0" "Disable source routing (default)"
apply_sysctl "net.ipv4.conf.all.accept_redirects" "0" "Disable ICMP redirect acceptance"
apply_sysctl "net.ipv4.conf.default.accept_redirects" "0" "Disable ICMP redirect acceptance (default)"
apply_sysctl "net.ipv4.conf.all.secure_redirects" "0" "Disable secure ICMP redirects"
apply_sysctl "net.ipv4.conf.default.secure_redirects" "0" "Disable secure ICMP redirects (default)"
apply_sysctl "net.ipv4.conf.all.send_redirects" "0" "Disable sending ICMP redirects"
apply_sysctl "net.ipv4.conf.default.send_redirects" "0" "Disable sending ICMP redirects (default)"
apply_sysctl "net.ipv6.conf.all.accept_redirects" "0" "Disable IPv6 ICMP redirects"
apply_sysctl "net.ipv6.conf.default.accept_redirects" "0" "Disable IPv6 ICMP redirects (default)"

# Apply the settings
if sysctl -p "$SYSCTL_CONF" &>/dev/null; then
    info "Kernel hardening applied successfully."
else
    warn "Some sysctl settings may not have applied. This is normal if your kernel doesn't support all options."
    info "The settings that were supported have been applied."
fi

# ---------------------------
# 2. OpenClaw-Specific Hardening (only if enabled)
# ---------------------------
if [[ "$HARDEN_OPENCLAW_CONFIG" == "yes" ]]; then
    info "=== OpenClaw Hardening (enabled) ==="

    # 2.1 Locate OpenClaw configuration file
    CONFIG_FILE=""
    for path in "${OPENCLAW_CONFIG_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            CONFIG_FILE="$path"
            break
        fi
    done

    if [[ -z "$CONFIG_FILE" ]]; then
        warn "OpenClaw configuration file not found in searched paths: ${OPENCLAW_CONFIG_PATHS[*]}"
        warn "Skipping OpenClaw configuration hardening."
    else
        info "Found configuration at: $CONFIG_FILE"

        # Backup config
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
        info "Backup created."

        # 2.2 Modify configuration using sed (JSON-aware but simple line matching)
        info "Modifying OpenClaw configuration..."

        # Function to safely replace a JSON key-value using sed (assumes key is at start of line, with indentation)
        # Usage: set_json_value "key" "new_value"
        set_json_value() {
            local key="$1"
            local value="$2"
            # Escape slashes in value for sed
            value=$(echo "$value" | sed 's/[\/&]/\\&/g')
            # Check if the file exists and is readable
            if [[ ! -f "$CONFIG_FILE" || ! -r "$CONFIG_FILE" ]]; then
                warn "Cannot read config file $CONFIG_FILE"
                return 1
            fi
            # Match lines like: "key": "old", or "key": "old" (with or without comma)
            if grep -q "\"$key\":" "$CONFIG_FILE" 2>/dev/null; then
                sed -i "s/\(\"$key\":\)\s*\".*\"/\1 \"$value\"/" "$CONFIG_FILE" 2>/dev/null
                info "Set $key to $value"
            else
                warn "Key '$key' not found in config – please add manually if needed."
            fi
        }

        # 2.2.1 Bind gateway to loopback (most secure) unless remote access is explicitly enabled
        if [[ "$ALLOW_REMOTE_GATEWAY" != "yes" ]]; then
            set_json_value "gateway.bind" "loopback" 2>/dev/null || \
            set_json_value "gateway" "{\"bind\": \"loopback\"}" 2>/dev/null || \
            warn "Could not set gateway.bind - check your config structure"
            info "Gateway binding set to loopback (localhost only)."
        else
            # If remote access wanted, ensure it binds to appropriate interface (0.0.0.0 or specific IP)
            set_json_value "gateway.bind" "0.0.0.0" 2>/dev/null || \
            warn "Could not set gateway.bind - check your config structure"
            info "Gateway binding set to 0.0.0.0 (remote access enabled). Ensure firewall port $GATEWAY_PORT is open."
        fi

        # 2.2.2 Enforce strict DM policy to prevent unauthorized message processing
        set_json_value "dmPolicy" "pairing" 2>/dev/null || \
        warn "Could not set dmPolicy - check your config structure"
        info "DM policy set to 'pairing' – unknown users must be paired."

        # 2.2.3 Disable any insecure features (example: disable HTTP admin panel if exists)
        if grep -q '"enable_http_admin"' "$CONFIG_FILE" 2>/dev/null; then
            set_json_value "enable_http_admin" "false" 2>/dev/null
            info "HTTP admin interface disabled."
        fi

        # 2.2.4 Set secure logging levels (avoid verbose logging that might leak secrets)
        set_json_value "logLevel" "info" 2>/dev/null || \
        warn "Could not set logLevel - check your config structure"
        info "Log level set to info."

        # 2.3 Secure file permissions
        info "Setting secure permissions on OpenClaw directories..."
        CONFIG_DIR="$(dirname "$CONFIG_FILE")"
        if [[ -d "$CONFIG_DIR" ]]; then
            if [[ -n "$OPENCLAW_USER" ]] && id "$OPENCLAW_USER" &>/dev/null; then
                chown -R "$OPENCLAW_USER":"$OPENCLAW_USER" "$CONFIG_DIR" 2>/dev/null || warn "Could not chown config directory."
            fi
            find "$CONFIG_DIR" -type f -exec chmod 640 {} \; 2>/dev/null || warn "Could not set file permissions"
            find "$CONFIG_DIR" -type d -exec chmod 750 {} \; 2>/dev/null || warn "Could not set directory permissions"
            info "Permissions set on $CONFIG_DIR"
        else
            warn "Config directory $CONFIG_DIR not found"
        fi

        # 2.4 Run OpenClaw's built-in security audit (if available)
        info "Running OpenClaw security audit..."
        if command -v openclaw &>/dev/null; then
            if openclaw security audit --fix 2>/dev/null; then
                info "Security audit completed successfully."
            else
                warn "Security audit encountered issues (check manually)."
            fi
        else
            warn "'openclaw' command not found – skipping audit."
        fi

        # 2.5 Restart OpenClaw service
        info "Restarting OpenClaw service..."
        if systemctl list-units --full -all 2>/dev/null | grep -q "$OPENCLAW_SERVICE_NAME.service"; then
            systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null && info "Service restarted (systemd)." || warn "Failed to restart via systemd"
        elif command -v service >/dev/null && service --status-all 2>/dev/null | grep -q "$OPENCLAW_SERVICE_NAME"; then
            service "$OPENCLAW_SERVICE_NAME" restart 2>/dev/null && info "Service restarted (init.d)." || warn "Failed to restart via service"
        else
            # Try to find any process named openclaw
            if pgrep -f "openclaw" >/dev/null; then
                warn "OpenClaw process found but no service detected. Please restart manually."
            else
                info "No running OpenClaw service detected."
            fi
        fi
    fi
else
    info "=== OpenClaw Hardening (disabled by HARDEN_OPENCLAW_CONFIG) ==="
fi

# ---------------------------
# 3. Final Checks
# ---------------------------
info "=== Hardening Complete ==="
info "Current open ports (public):"
if command -v ss >/dev/null; then
    ss -tulpn 2>/dev/null | grep LISTEN | grep -v "127.0.0.1" | grep -v "::1" || echo "  No public ports open"
elif command -v netstat >/dev/null; then
    netstat -tulpn 2>/dev/null | grep LISTEN | grep -v "127.0.0.1" | grep -v "::1" || echo "  No public ports open"
else
    warn "Neither ss nor netstat found - cannot list open ports"
fi

info ""
info "Open ports summary:"
info "  • SSH: $SSH_PORT (always open to public)"
if [[ "$ALLOW_REMOTE_GATEWAY" == "yes" ]]; then
    info "  • OpenClaw Gateway: $GATEWAY_PORT (remote access enabled)"
fi
if [[ "$DO_WHITELIST_PORTS" == "true" && -n "$WHITELIST_PORTS" ]]; then
    info "  • Whitelisted ports: $WHITELIST_PORTS (open to public)"
fi

info ""
info "Preserved private access:"
info "  • Localhost (127.0.0.0/8) - fully accessible"
if [[ "$PRESERVE_PRIVATE_NETWORKS" == "true" ]]; then
    info "  • Private networks: $PRIVATE_NETWORKS"
fi
if [[ "$PRESERVE_METADATA" == "true" ]]; then
    info "  • Cloud metadata: $METADATA_IPS"
fi

info ""
info "SSH configuration hardened."
if [[ "$HARDEN_OPENCLAW_CONFIG" == "yes" && -n "$CONFIG_FILE" ]]; then
    info "OpenClaw configuration backed up and modified."
else
    info "OpenClaw configuration was not modified (either disabled or config not found)."
fi
info "Review the changes and test connectivity before closing this session."

# Show summary of sysctl settings applied
if [[ -f "$SYSCTL_CONF" ]]; then
    echo ""
    info "=== Kernel Hardening Summary ==="
    info "The following settings were added to $SYSCTL_CONF:"
    grep -v "^#" "$SYSCTL_CONF" | grep -v "^$" | while read line; do
        info "  $line"
    done
fi

# Show next steps for iptables persistence if needed
if command -v iptables >/dev/null && ! command -v iptables-save >/dev/null; then
    echo ""
    info "=== Next Steps for Firewall Persistence ==="
    info "To make iptables rules persistent after reboot:"
    info "  - Debian/Ubuntu: apt-get install iptables-persistent"
    info "  - RHEL/CentOS: yum install iptables-services && systemctl enable iptables"
    info "  - Or add iptables commands to /etc/rc.local"
fi

exit 0
