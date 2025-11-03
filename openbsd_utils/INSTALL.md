# OpenBSD Installation Guide

A guide for installing and configuring OpenBSD.

## Pre-Installation

1. Download OpenBSD installation ISO from [openbsd.org](https://www.openbsd.org)
2. Verify checksums with signify
3. Create bootable USB or burn to CD

## Installation Steps

1. Boot from installation media
2. Choose `(I)nstall` at the boot prompt
3. Follow the installer prompts:
   - Choose keyboard layout
   - Set hostname
   - Configure network interfaces
   - Set root password
   - Create user account
   - Select disk for installation
   - Choose disk layout (automatic or manual)
   - Select package sets to install

## Post-Installation

### Update System

```sh
# Apply security patches
doas syspatch

# Update packages
doas pkg_add -u
```

### Configure Firewall

```sh
# Copy and edit firewall configuration
doas cp firewall.conf /etc/pf.conf
doas vi /etc/pf.conf

# Enable and load firewall
doas rcctl enable pf
doas pfctl -ef /etc/pf.conf
```

### Install Additional Packages

```sh
# Install common packages
doas pkg_add vim git curl wget tmux

# Search for packages
pkg_info -Q package_name
```

### Configure Services

```sh
# Enable and start services
doas rcctl enable httpd
doas rcctl start httpd

# Check service status
doas rcctl check httpd
```

## Security Considerations

- Keep system updated with `syspatch`
- Use `doas` instead of sudo
- Configure PF firewall properly
- Disable unnecessary services
- Use strong passwords or SSH keys
- Regular backups

## Resources

- [OpenBSD FAQ](https://www.openbsd.org/faq/)
- [OpenBSD Manual Pages](https://man.openbsd.org/)
- [PF User Guide](https://www.openbsd.org/faq/pf/)
