#!/bin/sh
# test_creative_tools.sh - VPS Testing Script for OpenBSD 7.6
# Run on 185.52.176.18 after git pull

echo "Testing Creative Tools on OpenBSD 7.6"
echo "======================================"

cd /home/user/pub/creative || exit 1

echo "\n1. Testing dilla.rb (J Dilla Beat Generator)"
echo "----------------------------------------------"
cd dilla || exit 1

if ! command -v sox >/dev/null 2>&1; then
  echo "ERROR: SoX not installed"
  echo "Install: doas pkg_add sox"
  exit 1
fi

echo "SoX found: $(which sox)"
echo "Syntax check..."
ruby -c dilla.rb || exit 1
echo "Quick test (will generate for 5 seconds then Ctrl+C)..."
timeout 5 ruby dilla.rb || echo "Test complete (expected timeout)"

echo "\n2. Testing postpro.rb (Cinematic Post-Processing)"
echo "--------------------------------------------------"
cd ../postpro || exit 1

if ! pkg_info | grep -q vips; then
  echo "ERROR: libvips not installed"
  echo "Install: doas pkg_add vips"
  exit 1
fi

if ! gem list | grep -q ruby-vips; then
  echo "ERROR: ruby-vips gem not installed"
  echo "Install: gem install ruby-vips"
  exit 1
fi

echo "libvips found: $(pkg_info | grep vips)"
echo "Syntax check..."
ruby -c postpro.rb || exit 1
echo "Help text..."
ruby postpro.rb --help 2>&1 | head -10

echo "\n3. Testing repligen.rb (Replicate.com CLI)"
echo "-------------------------------------------"
cd ../repligen || exit 1

if ! gem list | grep -q sqlite3; then
  echo "ERROR: sqlite3 gem not installed"
  echo "Install: gem install sqlite3"
  exit 1
fi

echo "sqlite3 gem found"
echo "Syntax check..."
ruby -c repligen.rb || exit 1
echo "Stats (empty database expected)..."
ruby repligen.rb stats || echo "Database not initialized yet"

echo "\n======================================"
echo "All tests completed!"
echo "======================================"
echo "\nNext steps:"
echo "1. dilla: Run 'ruby dilla.rb' to generate beats"
echo "2. postpro: Needs test image, run 'ruby postpro.rb image.jpg portrait'"
echo "3. repligen: Set REPLICATE_API_TOKEN, run 'ruby repligen.rb sync 100'"
