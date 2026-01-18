# Deploy to OpenBSD VPS
# Run this manually: .\deploy_vps.ps1

$vps = "dev@185.52.176.18"
Write-Host "=== OpenBSD Deployment ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Pull latest code" -ForegroundColor Yellow

ssh $vps "cd pub4 && git pull"

Write-Host ""
Write-Host "Step 2: Deploy infrastructure (--pre-point)" -ForegroundColor Yellow

Write-Host "This will setup: DNS, PF, relayd, PostgreSQL, Falcon configs" -ForegroundColor Gray

ssh $vps "cd pub4/openbsd && doas zsh openbsd.sh --pre-point"

Write-Host ""
Write-Host "✓ Pre-point deployment complete" -ForegroundColor Green

Write-Host ""

Write-Host "Next steps:" -ForegroundColor Cyan

Write-Host "1. Point DNS records to 185.52.176.18"

Write-Host "2. Run: ssh $vps 'cd pub4/openbsd && doas zsh openbsd.sh --post-point'"

Write-Host "3. Deploy Rails apps: ssh $vps 'cd pub4/rails && zsh brgen.sh'"

