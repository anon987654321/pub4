#!/bin/sh

# OpenBSD System Hardening Script
# Run as root or with doas

set -e

echo "OpenBSD System Hardening Script"
echo "================================"

# Update system
echo "Updating system..."
syspatch

# Secure SSH configuration
echo "Hardening SSH configuration..."
cat >> /etc/ssh/sshd_config << 'EOF'

# Security hardening
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding no
MaxAuthTries 3
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# Enable and configure PF firewall
echo "Enabling PF firewall..."
pfctl -ef /etc/pf.conf
rcctl enable pf

# Set secure file permissions
echo "Setting secure file permissions..."
chmod 700 /root
chmod 600 /etc/ssh/sshd_config

# Disable unnecessary services
echo "Disabling unnecessary services..."
rcctl disable sndiod
rcctl disable slaacd

# Configure login.conf for security
echo "Configuring login limits..."
cat >> /etc/login.conf << 'EOF'

# Security limits
default:\
    :datasize-cur=512M:\
    :maxproc-cur=256:\
    :openfiles-cur=1024:
EOF

# Rebuild login.conf database
cap_mkdb /etc/login.conf

echo "System hardening complete!"
echo "Please review changes and reboot the system."
