#!/bin/ksh
# Deployment script for OpenBSD VPS
# Run this from your local machine where SSH works

# Upload script
echo "Uploading openbsd.sh..."
scp G:\pub\openbsd\openbsd.sh dev@185.52.176.18:~/

# Connect and deploy
echo "Connecting to VPS..."
ssh dev@185.52.176.18 << 'ENDSSH'
  # Make executable
  chmod +x openbsd.sh
  
  # Check current state
  echo "Current state:"
  ls -la openbsd_setup_state 2>/dev/null || echo "No state file (fresh install)"
  
  # Run Stage 2 (DNS already propagated)
  echo "Starting Stage 2..."
  doas zsh openbsd.sh --resume
ENDSSH

echo "Deployment complete!"
