# Brgen Deployment Guide for OpenBSD
## Prerequisites
- OpenBSD 7.6+ VM at brgen.no

- SSH access as user `dev`

- doas privileges

## Step 1: Upload Files to Server
From your local machine (Cygwin):
```bash

# Create deployment directory on server

ssh dev@brgen.no "mkdir -p ~/deploy"

# Upload deployment package
scp -r G:/pub4/DEPLOY_PACKAGE/* dev@brgen.no:~/deploy/

# OR use rsync if available
rsync -avz G:/pub4/DEPLOY_PACKAGE/ dev@brgen.no:~/deploy/

```

## Step 2: Initial Infrastructure Setup
SSH into the server:
```bash

ssh dev@brgen.no

cd ~/deploy

```

Check if openbsd.sh has already been run:
```bash

# Check if services are running

doas rcctl ls on | grep -E '(postgresql|nsd|httpd)'

# Check if apps exist
ls -la /home/brgen/app 2>/dev/null

```

If infrastructure is already set up, proceed to Step 3. Otherwise:
```bash

# Run infrastructure setup (if not already done)

doas zsh openbsd.sh --pre-point

# This sets up:
# - Ruby 3.3 + Rails 8

# - PostgreSQL + Redis

# - NSD DNS with DNSSEC

# - PF Firewall

# - Creates /home/brgen/app structure

```

## Step 3: Deploy Brgen Core Application
```bash
cd ~/deploy

# Make scripts executable
chmod +x brgen.sh brgen_marketplace.sh

chmod +x __shared/*.sh

# Run Brgen setup
doas zsh brgen.sh

# This will:
# - Install Rails 8 with Solid Stack

# - Create models (Community, Post, Comment, Vote)

# - Generate views with tag helpers

# - Set up StimulusReflex

# - Configure dark theme styles

# - Seed sample data

```

## Step 4: Deploy Brgen Marketplace
```bash
# Run marketplace setup

doas zsh brgen_marketplace.sh

# This adds:
# - Solidus 4.0 e-commerce

# - Multi-vendor support

# - Product listings

# - Stripe/PayPal integration

```

## Step 5: Post-Point Setup (TLS & Proxy)
After DNS has propagated (check with `dig @8.8.8.8 brgen.no`):
```bash

cd ~/deploy

doas zsh openbsd.sh --post-point

# This sets up:
# - TLS certificates (Let's Encrypt)

# - Relayd reverse proxy (HTTPS→HTTP)

# - PTR records

# - Cron jobs for certificate renewal

```

## Step 6: Start Brgen Application
```bash
# The app should be managed by rcctl

doas rcctl start brgen

# Check status
doas rcctl check brgen

# View logs
tail -f /var/log/rails/brgen.log

```

## Step 7: Verify Deployment
```bash
# Check services

doas rcctl ls on

# Should show:
# - postgresql

# - nsd

# - httpd

# - relayd

# - brgen

# Test locally
curl http://localhost:11006

# Test via relayd
curl https://brgen.no

```

## Troubleshooting
### Check PostgreSQL
```bash

doas rcctl check postgresql

doas -u _postgresql psql -U postgres -c '\l'

```

### Check Rails App
```bash

cd /home/brgen/app

doas -u brgen bin/rails console

# In console:

> User.count

> Community.count

> Post.count

```

### Check Logs
```bash

tail -f /var/log/rails/unified.log

tail -f /var/log/httpd/*.log

tail -f /var/log/daemon

```

### Reset Database
```bash

cd /home/brgen/app

doas -u brgen bin/rails db:drop db:create db:migrate db:seed

```

### Reload Relayd Config
```bash

doas relayctl reload

doas pfctl -f /etc/pf.conf

```

## Architecture
```
Internet

  ↓

PF Firewall (port 443, 80, 22, 53)

  ↓

Relayd (HTTPS:443 → HTTP:11006)

  ↓

bin/rails server (port 11006)

  ↓

Rails 8 App (Brgen)

  ↓

PostgreSQL (local socket)

```

## Domains Configured
All pointing to brgen.no (185.52.176.18):
- brgen.no (main)

- oshlo.no

- trndheim.no

- stvanger.no

- trmso.no

- reykjavk.is

- kobenhvn.dk

- stholm.se

- ... and 30+ more

## Post-Deployment Tasks
1. **Set PTR records** (already done if pre-point completed):
   ```bash

   # Follow https://openbsd.amsterdam/ptr.html

   ```

2. **Configure Vipps OAuth** (Norwegian BankID):
   ```bash

   # Add to /home/brgen/app/.env:

   VIPPS_CLIENT_ID=your_client_id

   VIPPS_CLIENT_SECRET=your_client_secret

   ```

3. **Add Mapbox token** (for location features):
   ```bash

   # Add to /home/brgen/app/.env:

   MAPBOX_ACCESS_TOKEN=your_token

   ```

4. **Configure Stripe** (for marketplace):
   ```bash

   # Add to /home/brgen/app/.env:

   STRIPE_PUBLISHABLE_KEY=your_key

   STRIPE_SECRET_KEY=your_secret

   ```

5. **Set up backups**:
   ```bash

   # Follow https://openbsd.amsterdam/backup.html

   ```

## Monitoring
```bash
# System resources

systat vmstat

# Network connections
systat netstat

# Service status
doas rcctl ls on

# Disk usage
df -h

# Memory usage
top

```

## Next Steps
After Brgen core is running:
1. Deploy brgen_dating.sh

2. Deploy brgen_playlist.sh

3. Deploy brgen_takeaway.sh

4. Deploy brgen_tv.sh

5. Deploy amber.sh

6. Deploy other apps (baibl, blognet, etc.)

---
**Support:**
- OpenBSD Amsterdam: https://openbsd.amsterdam/onboard.html

- Rails Guides: https://edgeguides.rubyonrails.org

- Solidus Guides: https://edgeguides.solidus.io

Last Updated: 2025-11-14T14:25:00Z
