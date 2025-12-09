#!/usr/bin/env zsh
set -euo pipefail

cd "G:/pub/creative"

echo "Replacing multimedia tools with pub2 complete versions..."

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/multimedia/dilla.rb -o dilla.rb
echo "✓ dilla.rb (29KB - J Dilla chord progressions & harmonies)"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/multimedia/postpro.rb -o postpro.rb
echo "✓ postpro.rb (25KB - libvips analog effects)"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/multimedia/repligen.rb -o repligen.rb
echo "✓ repligen.rb (22KB - Replicate.com scraper + generator)"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/multimedia/dilla_README.md -o dilla_README.md
echo "✓ dilla_README.md"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/multimedia/postpro_README.md -o postpro_README.md
echo "✓ postpro_README.md"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/multimedia/repligen_README.md -o repligen_README.md
echo "✓ repligen_README.md"

echo ""
echo "All multimedia tools replaced! Total: 76KB + READMEs"
echo ""
echo "Next: Test on VPS (openbsd.amsterdam)"
echo "  ruby dilla.rb --help"
echo "  ruby postpro.rb --help"
echo "  ruby repligen.rb --help"
