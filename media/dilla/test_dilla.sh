#!/bin/bash
# Quick test script for dilla.rb

cd "$(dirname "$0")"

echo "=== Testing dilla.rb ==="
echo

echo "1. Checking Ruby..."
ruby --version || { echo "❌ Ruby not found"; exit 1; }

echo

echo "2. Checking FFmpeg..."
which ffmpeg || { echo "❌ FFmpeg not found. Install with: apt-cyg install ffmpeg"; exit 1; }
ffmpeg -version | head -1

echo

echo "3. Testing dilla.rb help..."
ruby dilla.rb --help || { echo "❌ dilla.rb failed to run"; exit 1; }

echo

echo "4. Generating test beat..."
ruby dilla.rb dilla donuts C 95

echo

echo "5. Checking output..."
ls -lh ~/dilla_output/*.wav 2>/dev/null || echo "⚠️ No output files found"

echo
echo "=== Test complete ==="
