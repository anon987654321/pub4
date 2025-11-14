#!/bin/bash
# Quick deployment script for Brgen on OpenBSD

# Run this from your local machine (Cygwin)

set -e
SERVER="dev@brgen.no"
DEPLOY_DIR="~/deploy"

LOCAL_PACKAGE="G:/pub4/DEPLOY_PACKAGE"

echo "=== Brgen Deployment Script ==="
echo ""

# Step 1: Create remote directory
echo "[1/4] Creating deployment directory on server..."

ssh $SERVER "mkdir -p $DEPLOY_DIR"

# Step 2: Upload files
echo "[2/4] Uploading deployment package..."

scp -r ${LOCAL_PACKAGE}/* ${SERVER}:${DEPLOY_DIR}/

# Step 3: Check infrastructure status
echo "[3/4] Checking infrastructure status..."

ssh $SERVER << 'ENDSSH'

  echo "Checking PostgreSQL..."

  doas rcctl check postgresql && echo "✓ PostgreSQL running" || echo "✗ PostgreSQL not running"

  echo "Checking NSD..."
  doas rcctl check nsd && echo "✓ NSD running" || echo "✗ NSD not running"

  echo "Checking if Brgen app exists..."
  if [ -d /home/brgen/app ]; then

    echo "✓ App directory exists"

  else

    echo "✗ App directory missing - run openbsd.sh --pre-point"

  fi

ENDSSH

# Step 4: Show next steps
echo "[4/4] Deployment package uploaded successfully!"

echo ""

echo "Next steps:"

echo "  1. SSH into server: ssh $SERVER"

echo "  2. cd ~/deploy"

echo "  3. If infrastructure not set up: doas zsh openbsd.sh --pre-point"

echo "  4. Deploy Brgen: doas zsh brgen.sh"

echo "  5. Deploy Marketplace: doas zsh brgen_marketplace.sh"

echo ""

echo "See DEPLOYMENT_GUIDE.md for detailed instructions"

