# OpenBSD & Rails

This guide provides a step-by-step approach to setting up a secure and efficient Ruby on Rails environment on an OpenBSD server. It leverages OpenBSD’s built-in tools and configurations for optimal performance and security.

## Overview

The setup script performs the following tasks:

- **Package Installation**: Installs essential packages including Ruby, PostgreSQL, Redis, and others.
- **PostgreSQL Configuration**: Configures PostgreSQL for database management.
- **Redis Setup**: Configures Redis for caching and background jobs.
- **DNS Configuration**: Sets up `nsd` for secure DNS services with DNSSEC.
- **Web Server Setup**: Configures `httpd` for handling Let's Encrypt ACME challenges and HTTP requests.
- **Reverse Proxy Configuration**: Sets up `relayd` for reverse proxying and TLS termination.
- **Firewall Configuration**: Configures `pf` for advanced firewall and network security.
- **Certificate Management**: Manages domain certificates with Let's Encrypt.
- **System Optimization**: Adjusts system settings for performance.

## Components

### PostgreSQL

- **Purpose**: Provides a reliable and scalable database solution.
- **Security**: Operates as an unprivileged user to enhance security.
- **Performance**: Tuned for high-concurrency workloads.

### Redis

- **Purpose**: Manages caching and background jobs to improve performance.
- **Speed**: Utilizes in-memory data storage for fast access.

### nsd (DNS Server)

- **Configuration**: Acts as the primary DNS server with DNSSEC to prevent spoofing.
- **Security**: Ensures DNS queries are secure.
- **Reliability**: Provides high availability for DNS services.

### httpd (Web Server)

- **ACME Challenge Handling**: Manages Let's Encrypt ACME challenges to automate certificate issuance.
- **Request Management**: Handles HTTP requests and serves static content.

### relayd (Load Balancer and Proxy)

- **Reverse Proxy**: Forwards client requests to Rails applications.
- **TLS Termination**: Manages HTTPS connections and offloads TLS processing from Rails.
- **Performance**: Enhances overall system performance by handling TLS separately.

### pf (Packet Filter)

- **Firewall Configuration**: Filters network traffic to protect against unauthorized access.
- **Network Security**: Implements advanced rules to control traffic.
- **Performance**: Designed for low latency and high throughput.

### acme-client (Let's Encrypt)

- **Certificate Management**: Automates the process of obtaining and renewing TLS certificates.
- **Security**: Ensures secure HTTPS connections across all domains.

## Setup Script Details

The setup script configures various aspects of your OpenBSD server:

1. **Installation**: It installs necessary packages like Ruby, PostgreSQL, and DNSCrypt.
2. **Configuration**:
   - **pf**: Configures firewall rules to protect against attacks while allowing necessary traffic.
   - **relayd**: Sets up reverse proxy rules and TLS termination for your Rails apps.
   - **httpd**: Configures the web server to handle Let's Encrypt challenges and manage HTTP requests.
   - **nsd**: Sets up DNS with secure configurations.
3. **User Accounts**: Creates system users for each application.
4. **Startup Scripts**: Sets up scripts to manage the Rails applications as services.

Ensure you test the script in a staging environment before deploying to production to verify that all configurations work as expected.

