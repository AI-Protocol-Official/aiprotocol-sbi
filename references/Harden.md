AIP Security Hardening Guide
Overview

This repository contains two scripts for securing OpenClaw-based agents:

    harden.sh - Applies security hardening

    unharden.sh - Reverts all changes (if needed)

Quick Start
bash

# Make scripts executable
chmod +x harden.sh unharden.sh

# Run hardening (as root)
sudo ./harden.sh

# If something breaks, revert changes
sudo ./unharden.sh

What the Hardening Script Does
1. Firewall Lockdown

    Closes ALL incoming ports except those explicitly allowed

    Preserves access from:

        Localhost (127.0.0.0/8) - always accessible

        Private networks (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)

        Cloud metadata (169.254.169.254) - AWS/GCP/Azure

        Link-local (169.254.0.0/16)

2. SSH Hardening

    Disables root login

    Disables password authentication (SSH keys only)

    Enables public key authentication

    Disables X11 forwarding

3. Kernel Hardening

    Enables TCP syncookies (SYN flood protection)

    Disables ICMP redirects

    Disables source routing

    Enables reverse path filtering

4. OpenClaw-Specific Hardening

    Binds gateway to localhost only (prevents remote access)

    Sets DM policy to "pairing" (users must be approved)

    Sets log level to "info" (less verbose)

    Restricts file permissions

Configuration Options

#Edit the variables at the top of harden.sh:
bash
    
    # Basic Settings
    SSH_PORT="22"                          # SSH port
    ALLOW_REMOTE_GATEWAY="no"               # Set "yes" to expose OpenClaw remotely
    GATEWAY_PORT="18789"                     # OpenClaw gateway port
    
    # OpenClaw Settings set to yes to harden default no
    HARDEN_OPENCLAW_CONFIG="yes"             # Apply OpenClaw-specific hardening
    
    # Port Whitelisting set to true to expose any port default is false
    DO_WHITELIST_PORTS="true"                # Enable additional ports
    WHITELIST_PORTS="8000,9090"               # Ports to open (comma-separated)
    WHITELIST_PROTOCOL="tcp"                   # Default protocol (tcp/udp/both)
    
    # Advanced: Protocol per port
    # WHITELIST_PORTS="8000:tcp,9090:udp,8080:both,53:udp"
    
    # Private Network Preservation
    PRESERVE_PRIVATE_NETWORKS="true"          # Keep private network access
    PRIVATE_NETWORKS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16"
    PRESERVE_METADATA="true"                   # Keep cloud metadata access
    METADATA_IPS="169.254.169.254,fd00:ec2::254"  # AWS/GCP/Azure metadata
    
    Port Whitelisting Examples
    bash
    
    # Open TCP ports 8000 and 9090
    DO_WHITELIST_PORTS="true"
    WHITELIST_PORTS="8000,9090"
    WHITELIST_PROTOCOL="tcp"
    
    # Mixed protocols
    DO_WHITELIST_PORTS="true"
    WHITELIST_PORTS="8000:tcp,9090:udp,8080:both,53:udp,443:tcp"
    
    # UDP only (e.g., for WireGuard)
    DO_WHITELIST_PORTS="true"
    WHITELIST_PORTS="51820,51821"
    WHITELIST_PROTOCOL="udp"

Accessing OpenClaw After Hardening
Option 1: Localhost Only (Default - Most Secure)
bash

# OpenClaw is only accessible from the same machine
curl http://localhost:18789

Option 2: SSH Tunneling (Recommended for Remote Access)
bash

# From your local machine, create an SSH tunnel
ssh -L 18789:localhost:18789 user@your-server

# Then access locally
curl http://localhost:18789

Option 3: Direct Remote Access (Less Secure)

Set ALLOW_REMOTE_GATEWAY="yes" in the script to open the firewall port.
Before You Run
  Prerequisites
  Root/sudo access
  SSH key-based access already configured
  OpenClaw installed and configured
  iptables installed

Critical Warnings

    Keep your current SSH session OPEN while testing

    Ensure you have SSH key access - password auth will be disabled

    Test from a SECOND terminal before closing your main session

    Backup your OpenClaw config - the script creates backups automatically

What to Expect
During Hardening

The script will:

    Show a warning banner

    Ask for confirmation

    Apply firewall rules

    Harden SSH

    Apply kernel settings

    Modify OpenClaw config

    Restart services

    Show final status

After Hardening

    Only SSH (port 22) will be publicly accessible

    Localhost and private networks remain fully accessible

    Cloud metadata remains accessible

    OpenClaw will only be available locally (unless configured otherwise)


 =====================================================================================

   # Security Best Practices

    Always use SSH keys, never passwords

    Keep your system updated: apt update && apt upgrade

    Monitor logs: journalctl -u openclaw -f

    Regular backups: Backup /etc/openclaw/

    Least privilege: Run OpenClaw as dedicated user (not root)

Support

If you encounter issues:

    Check logs: journalctl -xe

    Verify firewall: iptables -L -n

    Test SSH: ssh -vvv localhost

    Run unhardening script if needed

License

This script is provided as-is. Test in a non-production environment first!
