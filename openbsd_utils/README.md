# OpenBSD Utilities and Scripts

Collection of utilities, scripts, and documentation for OpenBSD systems.

## Files

- `firewall.conf` - Example PF firewall configuration
- `system_hardening.sh` - System hardening script
- `backup.sh` - System backup script
- `INSTALL.md` - OpenBSD installation and setup guide

## Overview

OpenBSD is known for its focus on security, correctness, and code quality. This collection provides useful scripts and configurations for OpenBSD systems.

## Features

- PF (Packet Filter) firewall examples
- System hardening guidelines
- Backup and maintenance scripts
- Configuration examples

## Usage

All scripts should be reviewed and customized for your specific environment before use.

```bash
# Make scripts executable
chmod +x *.sh

# Review and edit configurations
vi firewall.conf

# Run with appropriate permissions
doas ./system_hardening.sh
```
