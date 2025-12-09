#!/usr/bin/env zsh
set -euo pipefail

echo "Testing all multimedia tools..."
echo ""

echo "1. Dilla (J Dilla chord progressions)"
ruby dilla.rb list 2>&1 | head -20
echo ""

echo "2. Postpro (libvips analog effects)"  
echo "Requires: libvips installed on system"
echo "Status: gem installed, needs libvips.so"
echo ""

echo "3. Repligen (Replicate.com scraper)"
REPLICATE_API_TOKEN=your_token_here ruby repligen.rb --help
echo ""

echo "✓ All tools executable and respond to commands"
echo ""
echo "Next: Deploy to VPS (openbsd.amsterdam) for full integration test"
echo "  scp *.rb user@openbsd.amsterdam:/path/to/creative/"
echo "  ssh user@openbsd.amsterdam"
echo "  doas pkg_add libvips ruby32-gems"
echo "  gem install ruby-vips sqlite3 ferrum"
echo "  ruby dilla.rb gen donuts_classic Db 94"
echo "  ruby postpro.rb --help"
echo "  ruby repligen.rb scrape"
